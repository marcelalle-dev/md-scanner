import { readBody, requireJsonContentType } from "../http/body";
import {
  internalError,
  invalidRequest,
  premiumRequired,
  quotaExceeded,
  rateLimited,
  upstreamUnavailable,
  type ApiError,
} from "../http/errors";
import { clientIpKey, parseInstallId, parsePurchaseCredentials } from "../http/identity";
import { enforcePlayIntegrity } from "../http/integrity-guard";
import type { RequestContext } from "../http/request-context";
import { jsonResponse } from "../http/responses";
import { getLimiter } from "../limiter/client";
import { utcDayKey } from "../limiter/time";
import type { AdmitInput, Admission, AdmitResult, LimiterApi, LimiterLimits, SettleResult } from "../limiter/types";
import { safeErrorName } from "../logging/logger";
import { purchaseKeyFor, toCachedEntitlement, verifyEntitlement } from "../purchases/entitlement";
import { sha256Hex } from "../util/encoding";
import { budgetUnits, callModel, NO_USAGE, type ModelOutcome, type TokenUsage } from "./anthropic";
import { estimateReserveUnits, parseAiTaskRequest } from "./request";
import { buildDocumentBlock, buildSystemPrompt, buildTrailerBlock, TASKS, type PromptParams } from "./tasks";
import type { AppConfig } from "../config";

function limiterLimits(config: AppConfig): LimiterLimits {
  return {
    rateLimitMax: config.rateLimit.aiMax,
    rateLimitWindowSeconds: config.rateLimit.windowSeconds,
    dailyRequests: config.quotas.dailyRequests,
    freeDailyRequests: config.quotas.freeDailyRequests,
    freeGlobalDailyRequests: config.quotas.freeGlobalDailyRequests,
    monthlyTokenBudget: config.quotas.monthlyTokenBudget,
    globalDailyTokenBudget: config.quotas.globalDailyTokenBudget,
    entitlementCacheSeconds: config.google.entitlementCacheSeconds,
    entitlementNegativeCacheSeconds: config.google.entitlementNegativeCacheSeconds,
  };
}

function rejection(result: Exclude<AdmitResult, Admission>): ApiError {
  switch (result.outcome) {
    case "rate_limited":
      return rateLimited(result.retryAfterSeconds);
    case "premium_required":
      return premiumRequired(result.purchaseState);
    case "quota_exceeded":
      return quotaExceeded(result.reason, result.retryAfterSeconds, {
        tier: result.tier,
        limit: result.limit,
        resetsAt: new Date(result.resetsAt).toISOString(),
      });
    case "global_budget_exhausted":
      // Kill-switch: the whole service has spent its daily AI budget.
      return upstreamUnavailable(503, "global_budget_exhausted", { retryAfterSeconds: result.retryAfterSeconds });
    case "needs_verification":
      return internalError("entitlement_unresolved");
  }
}

function quotaView(admission: Admission, settled: SettleResult | null) {
  const dailyUsed = settled?.dailyUsed ?? admission.daily.used;
  const monthlyUsed = settled?.monthlyUsed ?? admission.monthly.used;
  return {
    tier: admission.tier,
    limit: admission.daily.limit,
    remaining: Math.max(0, admission.daily.limit - dailyUsed),
    resetsAt: new Date(admission.daily.resetsAt).toISOString(),
    monthlyTokens: {
      limit: admission.monthly.limit,
      remaining: Math.max(0, admission.monthly.limit - monthlyUsed),
      resetsAt: new Date(admission.monthly.resetsAt).toISOString(),
    },
  };
}

/**
 * POST /v1/ai/tasks
 *
 * Order of operations (cheap and local first, paid last):
 *   1. headers and body validation (no I/O),
 *   2. optional Play Integrity attestation,
 *   3. admission by the limiter: burst limit, global kill-switch, premium
 *      entitlement (verified with Google when not cached), daily quota,
 *      monthly budget; the worst-case cost is reserved atomically,
 *   4. one model call,
 *   5. validation of the model output against the task schema,
 *   6. settlement of the reservation with the real usage.
 * The request is stateless with respect to content: the document, the
 * question and the model output exist only in memory for its duration.
 */
export async function handleAiTask(rc: RequestContext): Promise<Response> {
  const { request, env, config, deps, log } = rc;

  requireJsonContentType(request);
  const installId = parseInstallId(request);
  const credentials = parsePurchaseCredentials(request);
  const apiKey = env.ANTHROPIC_API_KEY;
  if (apiKey === undefined || apiKey.trim() === "") throw upstreamUnavailable(503, "ai_not_configured");

  const body = await readBody(request, config.limits.maxBodyBytes);
  const input = parseAiTaskRequest(body.text, config);
  const task = TASKS[input.task];
  const maxOutputTokens = config.limits.maxOutputTokens[input.task];
  log.set({
    task: input.task,
    outputLanguage: input.outputLanguage,
    targetLanguage: input.targetLanguage,
    requestBytes: body.bytes.byteLength,
    documentChars: input.documentText.length,
    questionChars: input.question?.length,
    model: config.anthropic.model,
  });

  const limiter = getLimiter(env);
  const now = deps.now();
  const ipKey = await clientIpKey(request);
  const limits = limiterLimits(config);

  let burstAlreadyCounted = false;
  if (config.integrity.mode === "enforce") {
    // Count the burst limit before spending a call to Google on attestation.
    const burst = await limiter.rateLimit({
      now,
      bucket: "ai",
      ipKey,
      limit: limits.rateLimitMax,
      windowSeconds: limits.rateLimitWindowSeconds,
    });
    if (!burst.allowed) throw rateLimited(burst.retryAfterSeconds);
    burstAlreadyCounted = true;
    await enforcePlayIntegrity(rc, installId, body.bytes);
  }

  const admitInput: AdmitInput = {
    now,
    ipKey,
    installId,
    purchaseKey: credentials === null ? null : await purchaseKeyFor(credentials.productId, credentials.purchaseToken),
    skipRateLimit: burstAlreadyCounted,
    reserveUnits: estimateReserveUnits(body.bytes.byteLength, maxOutputTokens),
    limits,
  };

  let admitted = await limiter.admit(admitInput);
  if (admitted.outcome === "needs_verification" && credentials !== null) {
    const verification = await verifyEntitlement(rc, credentials.productId, credentials.purchaseToken);
    admitted = await limiter.admit({
      ...admitInput,
      skipRateLimit: true,
      verified: toCachedEntitlement(verification, now),
    });
  }
  if (admitted.outcome !== "admitted") throw rejection(admitted);
  const admission = admitted;
  log.set({ tier: admission.tier });

  const promptParams: PromptParams =
    input.targetLanguage === undefined
      ? { outputLanguage: input.outputLanguage }
      : { outputLanguage: input.outputLanguage, targetLanguage: input.targetLanguage };

  let outcome: ModelOutcome;
  const upstreamStartedAt = Date.now();
  try {
    // The marker is derived from the document itself: a document cannot
    // contain its own closing tag, and identical documents share a cache prefix.
    const marker = (await sha256Hex(input.documentText)).slice(0, 16);
    outcome = await callModel({
      apiKey,
      config: config.anthropic,
      fetch: deps.fetch,
      system: buildSystemPrompt(task, promptParams),
      documentBlock: buildDocumentBlock(input.documentText, marker),
      trailerBlock: buildTrailerBlock(
        task,
        input.question === undefined
          ? { today: utcDayKey(now) }
          : { today: utcDayKey(now), question: input.question },
      ),
      cacheDocument: input.task === "qa",
      format: task.outputFormat(),
      maxOutputTokens,
      log,
    });
  } catch (error) {
    // The model produced nothing billable: give the request and the reservation back.
    await settle(rc, limiter, admission, NO_USAGE, false);
    throw error;
  } finally {
    log.set({ upstreamLatencyMs: Date.now() - upstreamStartedAt });
  }

  const usage = outcome.usage;
  log.set({ inputTokens: totalInputTokens(usage), outputTokens: usage.outputTokens, budgetUnits: budgetUnits(usage) });

  if (outcome.kind === "refusal") {
    await settle(rc, limiter, admission, usage, false);
    throw invalidRequest(
      "content_refused",
      "The AI provider declined to process this content.",
      undefined,
      422,
    );
  }
  if (outcome.kind === "invalid_output") {
    await settle(rc, limiter, admission, usage, false);
    throw upstreamUnavailable(502, outcome.cause === "output_truncated" ? "output_truncated" : "invalid_model_output");
  }

  // Model output is untrusted: it is returned only if it matches the schema.
  const parsed = task.parse(outcome.json, promptParams);
  if (!parsed.ok) {
    await settle(rc, limiter, admission, usage, false);
    throw upstreamUnavailable(502, "invalid_model_output");
  }

  const settled = await settle(rc, limiter, admission, usage, true);
  const inputTokens = totalInputTokens(usage);
  return jsonResponse(
    200,
    {
      task: input.task,
      result: parsed.result,
      usage: { inputTokens, outputTokens: usage.outputTokens, totalTokens: inputTokens + usage.outputTokens },
      quota: quotaView(admission, settled),
    },
    rc.requestId,
  );
}

function totalInputTokens(usage: TokenUsage): number {
  return usage.inputTokens + usage.cacheWriteTokens + usage.cacheReadTokens;
}

/**
 * Replaces the reservation by the real usage. Registered with `waitUntil` so
 * it completes even if the client disconnects. If settlement itself fails,
 * the reservation simply stays counted (the safe direction for cost).
 */
async function settle(
  rc: RequestContext,
  limiter: LimiterApi,
  admission: Admission,
  usage: TokenUsage,
  countRequest: boolean,
): Promise<SettleResult | null> {
  const pending = limiter
    .settle({
      subject: admission.subject,
      tier: admission.tier,
      admittedAt: admission.admittedAt,
      reservedUnits: admission.reservedUnits,
      actualUnits: budgetUnits(usage),
      countRequest,
    })
    .catch((error: unknown) => {
      rc.log.event("error", "settle_failed", { errorName: safeErrorName(error) });
      return null;
    });
  rc.background.waitUntil(pending);
  return pending;
}
