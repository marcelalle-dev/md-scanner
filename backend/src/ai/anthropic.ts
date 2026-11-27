import Anthropic from "@anthropic-ai/sdk";
import type { AppConfig } from "../config";
import { BUDGET_WEIGHTS } from "../constants";
import { upstreamUnavailable, type ApiError } from "../http/errors";
import type { RequestLog } from "../logging/logger";
import type { FetchLike } from "../runtime";
import type { JsonSchemaFormat } from "./tasks";

type CreateParams = Anthropic.Beta.Messages.MessageCreateParamsNonStreaming;
type TextBlockParam = Anthropic.Beta.Messages.BetaTextBlockParam;

/** Beta flag of the server-side refusal fallback (`fallbacks: "default"`). */
const REFUSAL_FALLBACK_BETA = "server-side-fallback-2026-07-01";

const DEFAULT_RETRY_AFTER_SECONDS = 20;
const MAX_UPSTREAM_RETRY_AFTER_SECONDS = 300;

export interface TokenUsage {
  inputTokens: number;
  outputTokens: number;
  cacheWriteTokens: number;
  cacheReadTokens: number;
}

export const NO_USAGE: TokenUsage = { inputTokens: 0, outputTokens: 0, cacheWriteTokens: 0, cacheReadTokens: 0 };

export type ModelOutcome =
  | { kind: "ok"; json: unknown; usage: TokenUsage }
  | { kind: "refusal"; usage: TokenUsage }
  | { kind: "invalid_output"; cause: "output_truncated" | "unexpected_stop" | "no_text" | "not_json"; usage: TokenUsage };

export interface ModelCall {
  apiKey: string;
  config: AppConfig["anthropic"];
  fetch: FetchLike;
  system: string;
  documentBlock: string;
  trailerBlock: string;
  /** Marks the document as a prompt-cache breakpoint (useful for follow-up questions). */
  cacheDocument: boolean;
  format: JsonSchemaFormat;
  maxOutputTokens: number;
  log: RequestLog;
}

/** Budget units (input-token equivalents) consumed by a call. */
export function budgetUnits(usage: TokenUsage): number {
  return Math.ceil(
    usage.inputTokens * BUDGET_WEIGHTS.input +
      usage.cacheWriteTokens * BUDGET_WEIGHTS.cacheWrite +
      usage.cacheReadTokens * BUDGET_WEIGHTS.cacheRead +
      usage.outputTokens * BUDGET_WEIGHTS.output,
  );
}

function tokenCount(source: unknown, field: string): number {
  if (typeof source !== "object" || source === null) return 0;
  const value = (source as Record<string, unknown>)[field];
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : 0;
}

/**
 * Sums the usage of every attempt of a request. When a refusal fallback ran,
 * `usage.iterations` lists each attempt and is the billing source of truth;
 * otherwise the top-level usage is the only attempt.
 */
export function collectUsage(usage: Anthropic.Beta.Messages.BetaUsage): TokenUsage {
  const attempts: readonly unknown[] =
    Array.isArray(usage.iterations) && usage.iterations.length > 0 ? usage.iterations : [usage];
  const total: TokenUsage = { ...NO_USAGE };
  for (const attempt of attempts) {
    total.inputTokens += tokenCount(attempt, "input_tokens");
    total.outputTokens += tokenCount(attempt, "output_tokens");
    total.cacheWriteTokens += tokenCount(attempt, "cache_creation_input_tokens");
    total.cacheReadTokens += tokenCount(attempt, "cache_read_input_tokens");
  }
  return total;
}

/**
 * Calls Claude once, without streaming, and returns the parsed JSON candidate.
 *
 * - The model is asked for structured output (`output_config.format`), so the
 *   reply is constrained to the task schema while it is generated. The caller
 *   still validates it: model output is untrusted.
 * - Non-streaming on purpose: one JSON response costs far less Worker CPU than
 *   parsing a token stream, which matters on the 10 ms CPU allowance of the
 *   Workers Free plan. `max_tokens` is small and the call has a hard deadline.
 * - Thinking stays adaptive (the only mode of current models); `effort` is the
 *   cost and latency control.
 *
 * Throws an `ApiError` (`upstream_unavailable`) when the provider cannot serve
 * the request. Nothing from the prompt or the response is logged.
 */
export async function callModel(call: ModelCall): Promise<ModelOutcome> {
  const client = new Anthropic({
    apiKey: call.apiKey,
    fetch: call.fetch,
    maxRetries: call.config.maxRetries,
    timeout: call.config.timeoutMs,
    // The SDK must never log request or response bodies.
    logLevel: "off",
  });

  const documentBlock: TextBlockParam = { type: "text", text: call.documentBlock };
  if (call.cacheDocument) documentBlock.cache_control = { type: "ephemeral" };

  const params: CreateParams = {
    model: call.config.model,
    max_tokens: call.maxOutputTokens,
    system: [{ type: "text", text: call.system }],
    messages: [{ role: "user", content: [documentBlock, { type: "text", text: call.trailerBlock }] }],
    output_config: { effort: call.config.effort, format: call.format },
  };
  if (call.config.refusalFallback) {
    // If a safety classifier declines the request, the API retries it on the
    // fallback model Anthropic recommends, inside the same call.
    params.betas = [REFUSAL_FALLBACK_BETA];
    params.fallbacks = "default";
  }

  let message: Anthropic.Beta.Messages.BetaMessage;
  try {
    // Overall deadline for the call, retries included.
    message = await client.beta.messages.create(params, { signal: AbortSignal.timeout(call.config.timeoutMs) });
  } catch (error) {
    throw translateAnthropicError(error, call.log);
  }

  const usage = collectUsage(message.usage);
  call.log.set({ stopReason: message.stop_reason ?? "none" });

  if (message.stop_reason === "refusal") return { kind: "refusal", usage };
  if (message.stop_reason === "max_tokens") return { kind: "invalid_output", cause: "output_truncated", usage };
  if (message.stop_reason !== "end_turn") return { kind: "invalid_output", cause: "unexpected_stop", usage };

  // Read blocks by type: a response can start with thinking blocks.
  let text = "";
  for (const block of message.content) {
    if (block.type === "text") text += block.text;
  }
  if (text.trim() === "") return { kind: "invalid_output", cause: "no_text", usage };

  try {
    return { kind: "ok", json: JSON.parse(text) as unknown, usage };
  } catch {
    return { kind: "invalid_output", cause: "not_json", usage };
  }
}

function retryAfterFrom(error: InstanceType<typeof Anthropic.APIError>): number {
  const header = error.headers?.get("retry-after");
  const seconds = header === null || header === undefined ? Number.NaN : Number(header);
  if (!Number.isFinite(seconds) || seconds <= 0) return DEFAULT_RETRY_AFTER_SECONDS;
  return Math.min(MAX_UPSTREAM_RETRY_AFTER_SECONDS, Math.ceil(seconds));
}

/**
 * Maps SDK errors to the public error, most specific class first. Only the
 * upstream status and a fixed reason are logged: SDK error messages can quote
 * the request and are never logged or returned.
 */
function translateAnthropicError(error: unknown, log: RequestLog): unknown {
  let translated: ApiError;
  if (error instanceof Anthropic.APIUserAbortError || error instanceof Anthropic.APIConnectionTimeoutError) {
    translated = upstreamUnavailable(504, "ai_timeout", { retryAfterSeconds: DEFAULT_RETRY_AFTER_SECONDS });
  } else if (error instanceof Anthropic.APIConnectionError) {
    translated = upstreamUnavailable(503, "ai_unreachable", { retryAfterSeconds: DEFAULT_RETRY_AFTER_SECONDS });
  } else if (error instanceof Anthropic.RateLimitError) {
    translated = upstreamUnavailable(503, "ai_rate_limited", {
      retryAfterSeconds: retryAfterFrom(error),
      upstreamStatus: 429,
    });
  } else if (error instanceof Anthropic.AuthenticationError || error instanceof Anthropic.PermissionDeniedError) {
    translated = upstreamUnavailable(503, "ai_provider_auth", { upstreamStatus: error.status });
  } else if (error instanceof Anthropic.NotFoundError) {
    // Typically an unknown or unavailable model id.
    translated = upstreamUnavailable(503, "ai_provider_config", { upstreamStatus: 404 });
  } else if (error instanceof Anthropic.OverloadedError) {
    translated = upstreamUnavailable(503, "ai_overloaded", {
      retryAfterSeconds: retryAfterFrom(error),
      upstreamStatus: error.status,
    });
  } else if (error instanceof Anthropic.InternalServerError) {
    translated = upstreamUnavailable(503, "ai_provider_error", {
      retryAfterSeconds: retryAfterFrom(error),
      upstreamStatus: error.status,
    });
  } else if (error instanceof Anthropic.APIError) {
    // Remaining 4xx: the provider rejected the request we built.
    translated =
      typeof error.status === "number"
        ? upstreamUnavailable(502, "ai_provider_rejected", { upstreamStatus: error.status })
        : upstreamUnavailable(502, "ai_provider_rejected");
  } else {
    return error;
  }
  log.event("error", "ai_request_failed", { reason: translated.reason, upstreamStatus: translated.upstreamStatus });
  return translated;
}
