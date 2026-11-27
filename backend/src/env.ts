import type { LimiterDO } from "./limiter/durable-object";

/**
 * Bindings available to the Worker.
 *
 * Secrets (`ANTHROPIC_API_KEY`, `GOOGLE_SERVICE_ACCOUNT_JSON`) are provisioned
 * with `wrangler secret put` and never appear in `wrangler.jsonc`.
 * Every other variable is optional non-secret configuration; see `config.ts`
 * for defaults and accepted ranges.
 */
export interface Env {
  LIMITER: DurableObjectNamespace<LimiterDO>;

  // Secrets
  ANTHROPIC_API_KEY?: string;
  GOOGLE_SERVICE_ACCOUNT_JSON?: string;

  // AI provider
  ANTHROPIC_MODEL?: string;
  ANTHROPIC_EFFORT?: string;
  ANTHROPIC_REFUSAL_FALLBACK?: string;
  ANTHROPIC_MAX_RETRIES?: string;
  UPSTREAM_TIMEOUT_MS?: string;

  // Access and quotas
  DAILY_REQUEST_LIMIT?: string;
  FREE_DAILY_REQUESTS?: string;
  FREE_GLOBAL_DAILY_REQUESTS?: string;
  MONTHLY_TOKEN_BUDGET?: string;
  GLOBAL_DAILY_TOKEN_BUDGET?: string;

  // Burst rate limits
  RATE_LIMIT_WINDOW_SECONDS?: string;
  RATE_LIMIT_AI_MAX?: string;
  RATE_LIMIT_VERIFY_MAX?: string;

  // Size limits
  MAX_BODY_BYTES?: string;
  MAX_DOCUMENT_CHARS?: string;
  MAX_TRANSLATE_CHARS?: string;
  MAX_QUESTION_CHARS?: string;
  MAX_OUTPUT_TOKENS_SUMMARY?: string;
  MAX_OUTPUT_TOKENS_SECTION_SUMMARY?: string;
  MAX_OUTPUT_TOKENS_QA?: string;
  MAX_OUTPUT_TOKENS_EXTRACT?: string;
  MAX_OUTPUT_TOKENS_TRANSLATE?: string;
  MAX_OUTPUT_TOKENS_FLASHCARDS?: string;
  MAX_OUTPUT_TOKENS_ADMIN_ANALYSIS?: string;

  // Google Play
  GOOGLE_TIMEOUT_MS?: string;
  ENTITLEMENT_CACHE_SECONDS?: string;
  ENTITLEMENT_NEGATIVE_CACHE_SECONDS?: string;
  PLAY_INTEGRITY_MODE?: string;
  PLAY_INTEGRITY_MAX_AGE_SECONDS?: string;
}
