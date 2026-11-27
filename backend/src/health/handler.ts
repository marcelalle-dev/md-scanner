import { TARGET_LANGUAGE_CODES } from "../ai/languages";
import { API_VERSION, SERVICE_NAME } from "../constants";
import { parseServiceAccount } from "../google/service-account";
import type { RequestContext } from "../http/request-context";
import { jsonResponse } from "../http/responses";

/**
 * GET /v1/health
 *
 * Shallow liveness and configuration report. It exposes booleans and public
 * limits only: no secret, no identifier, no model name, and it performs no
 * upstream or storage call (so polling it costs nothing).
 */
export function handleHealth(rc: RequestContext): Response {
  const { env, config, deps } = rc;
  const anthropic = typeof env.ANTHROPIC_API_KEY === "string" && env.ANTHROPIC_API_KEY.trim() !== "";
  const googlePlay = parseServiceAccount(env.GOOGLE_SERVICE_ACCOUNT_JSON) !== null;

  return jsonResponse(
    200,
    {
      status: "ok",
      service: SERVICE_NAME,
      apiVersion: API_VERSION,
      time: new Date(deps.now()).toISOString(),
      integrations: {
        anthropic,
        googlePlay,
        playIntegrity: config.integrity.mode === "enforce",
      },
      limits: {
        maxDocumentChars: config.limits.maxDocumentChars,
        maxTranslateChars: Math.min(config.limits.maxTranslateChars, config.limits.maxDocumentChars),
        maxQuestionChars: config.limits.maxQuestionChars,
        maxBodyBytes: config.limits.maxBodyBytes,
        targetLanguages: TARGET_LANGUAGE_CODES,
      },
    },
    rc.requestId,
  );
}
