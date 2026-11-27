import type { Env } from "./env";

export const TASK_NAMES = [
  "summary",
  "section_summary",
  "qa",
  "extract",
  "translate",
  "flashcards",
  "admin_analysis",
] as const;
export type TaskName = (typeof TASK_NAMES)[number];

export const EFFORT_LEVELS = ["low", "medium", "high", "xhigh", "max"] as const;
export type EffortLevel = (typeof EFFORT_LEVELS)[number];

export interface AppConfig {
  anthropic: {
    model: string;
    effort: EffortLevel;
    /** Send `fallbacks: "default"` so a safety-classifier decline is retried server-side. */
    refusalFallback: boolean;
    maxRetries: number;
    timeoutMs: number;
  };
  quotas: {
    /** Requests per UTC day for a verified premium purchase. */
    dailyRequests: number;
    /** Requests per UTC day for a non-premium install. 0 disables the free trial. */
    freeDailyRequests: number;
    /** Requests per UTC day for all non-premium installs together. */
    freeGlobalDailyRequests: number;
    /** Budget units per UTC month and per subject (purchase or install). */
    monthlyTokenBudget: number;
    /** Budget units per UTC day for the whole service (kill-switch). */
    globalDailyTokenBudget: number;
  };
  rateLimit: {
    windowSeconds: number;
    aiMax: number;
    verifyMax: number;
  };
  limits: {
    maxBodyBytes: number;
    maxDocumentChars: number;
    maxTranslateChars: number;
    maxQuestionChars: number;
    maxOutputTokens: Record<TaskName, number>;
  };
  google: {
    timeoutMs: number;
    entitlementCacheSeconds: number;
    entitlementNegativeCacheSeconds: number;
  };
  integrity: {
    mode: "off" | "enforce";
    maxAgeSeconds: number;
  };
}

export interface LoadedConfig {
  config: AppConfig;
  /** Names of variables whose value was rejected (the safe default is used). */
  invalid: string[];
}

interface IntSpec {
  fallback: number;
  min: number;
  max: number;
}

const INT_SPECS = {
  ANTHROPIC_MAX_RETRIES: { fallback: 1, min: 0, max: 3 },
  UPSTREAM_TIMEOUT_MS: { fallback: 60_000, min: 1, max: 120_000 },
  DAILY_REQUEST_LIMIT: { fallback: 30, min: 0, max: 10_000 },
  FREE_DAILY_REQUESTS: { fallback: 0, min: 0, max: 1_000 },
  FREE_GLOBAL_DAILY_REQUESTS: { fallback: 200, min: 0, max: 1_000_000 },
  MONTHLY_TOKEN_BUDGET: { fallback: 600_000, min: 0, max: 1_000_000_000 },
  GLOBAL_DAILY_TOKEN_BUDGET: { fallback: 1_000_000, min: 0, max: 10_000_000_000 },
  RATE_LIMIT_WINDOW_SECONDS: { fallback: 60, min: 1, max: 3_600 },
  RATE_LIMIT_AI_MAX: { fallback: 10, min: 0, max: 10_000 },
  RATE_LIMIT_VERIFY_MAX: { fallback: 20, min: 0, max: 10_000 },
  MAX_BODY_BYTES: { fallback: 262_144, min: 1_024, max: 2_097_152 },
  MAX_DOCUMENT_CHARS: { fallback: 60_000, min: 100, max: 400_000 },
  MAX_TRANSLATE_CHARS: { fallback: 12_000, min: 100, max: 400_000 },
  MAX_QUESTION_CHARS: { fallback: 500, min: 10, max: 4_000 },
  MAX_OUTPUT_TOKENS_SUMMARY: { fallback: 2_000, min: 256, max: 16_000 },
  MAX_OUTPUT_TOKENS_SECTION_SUMMARY: { fallback: 4_000, min: 256, max: 16_000 },
  MAX_OUTPUT_TOKENS_QA: { fallback: 1_500, min: 256, max: 16_000 },
  MAX_OUTPUT_TOKENS_EXTRACT: { fallback: 4_000, min: 256, max: 16_000 },
  MAX_OUTPUT_TOKENS_TRANSLATE: { fallback: 8_000, min: 256, max: 16_000 },
  MAX_OUTPUT_TOKENS_FLASHCARDS: { fallback: 3_000, min: 256, max: 16_000 },
  MAX_OUTPUT_TOKENS_ADMIN_ANALYSIS: { fallback: 3_000, min: 256, max: 16_000 },
  GOOGLE_TIMEOUT_MS: { fallback: 10_000, min: 1, max: 30_000 },
  ENTITLEMENT_CACHE_SECONDS: { fallback: 600, min: 0, max: 86_400 },
  ENTITLEMENT_NEGATIVE_CACHE_SECONDS: { fallback: 60, min: 0, max: 3_600 },
  PLAY_INTEGRITY_MAX_AGE_SECONDS: { fallback: 120, min: 10, max: 3_600 },
} as const satisfies Record<string, IntSpec>;

type IntVar = keyof typeof INT_SPECS;

const DEFAULT_MODEL = "claude-opus-5-5";
const DEFAULT_EFFORT: EffortLevel = "low";
const MODEL_ID_PATTERN = /^claude-[a-z0-9][a-z0-9.-]{1,62}$/;
const UNSIGNED_INT_PATTERN = /^\d{1,12}$/;

const cache = new WeakMap<object, LoadedConfig>();

/**
 * Reads the non-secret configuration from the environment.
 * A malformed or out-of-range value never disables a protection: the safe
 * default is used instead and the variable name is reported in `invalid`.
 */
export function loadConfig(env: Env): LoadedConfig {
  const cached = cache.get(env);
  if (cached) return cached;

  const invalid: string[] = [];
  const raw = env as unknown as Record<string, unknown>;

  const int = (name: IntVar): number => {
    const spec: IntSpec = INT_SPECS[name];
    const value = raw[name];
    if (value === undefined || value === null || value === "") return spec.fallback;
    const text = typeof value === "string" ? value.trim() : String(value);
    if (!UNSIGNED_INT_PATTERN.test(text)) {
      invalid.push(name);
      return spec.fallback;
    }
    const parsed = Number(text);
    if (parsed < spec.min || parsed > spec.max) {
      invalid.push(name);
      return spec.fallback;
    }
    return parsed;
  };

  const choice = <T extends string>(name: keyof Env & string, allowed: readonly T[], fallback: T): T => {
    const value = raw[name];
    if (value === undefined || value === null || value === "") return fallback;
    const text = String(value).trim().toLowerCase();
    const match = allowed.find((candidate) => candidate === text);
    if (match === undefined) {
      invalid.push(name);
      return fallback;
    }
    return match;
  };

  const model = ((): string => {
    const value = raw["ANTHROPIC_MODEL"];
    if (value === undefined || value === null || value === "") return DEFAULT_MODEL;
    const text = String(value).trim();
    if (!MODEL_ID_PATTERN.test(text)) {
      invalid.push("ANTHROPIC_MODEL");
      return DEFAULT_MODEL;
    }
    return text;
  })();

  const config: AppConfig = {
    anthropic: {
      model,
      effort: choice("ANTHROPIC_EFFORT", EFFORT_LEVELS, DEFAULT_EFFORT),
      refusalFallback: choice("ANTHROPIC_REFUSAL_FALLBACK", ["default", "off"] as const, "default") === "default",
      maxRetries: int("ANTHROPIC_MAX_RETRIES"),
      timeoutMs: int("UPSTREAM_TIMEOUT_MS"),
    },
    quotas: {
      dailyRequests: int("DAILY_REQUEST_LIMIT"),
      freeDailyRequests: int("FREE_DAILY_REQUESTS"),
      freeGlobalDailyRequests: int("FREE_GLOBAL_DAILY_REQUESTS"),
      monthlyTokenBudget: int("MONTHLY_TOKEN_BUDGET"),
      globalDailyTokenBudget: int("GLOBAL_DAILY_TOKEN_BUDGET"),
    },
    rateLimit: {
      windowSeconds: int("RATE_LIMIT_WINDOW_SECONDS"),
      aiMax: int("RATE_LIMIT_AI_MAX"),
      verifyMax: int("RATE_LIMIT_VERIFY_MAX"),
    },
    limits: {
      maxBodyBytes: int("MAX_BODY_BYTES"),
      maxDocumentChars: int("MAX_DOCUMENT_CHARS"),
      maxTranslateChars: int("MAX_TRANSLATE_CHARS"),
      maxQuestionChars: int("MAX_QUESTION_CHARS"),
      maxOutputTokens: {
        summary: int("MAX_OUTPUT_TOKENS_SUMMARY"),
        section_summary: int("MAX_OUTPUT_TOKENS_SECTION_SUMMARY"),
        qa: int("MAX_OUTPUT_TOKENS_QA"),
        extract: int("MAX_OUTPUT_TOKENS_EXTRACT"),
        translate: int("MAX_OUTPUT_TOKENS_TRANSLATE"),
        flashcards: int("MAX_OUTPUT_TOKENS_FLASHCARDS"),
        admin_analysis: int("MAX_OUTPUT_TOKENS_ADMIN_ANALYSIS"),
      },
    },
    google: {
      timeoutMs: int("GOOGLE_TIMEOUT_MS"),
      entitlementCacheSeconds: int("ENTITLEMENT_CACHE_SECONDS"),
      entitlementNegativeCacheSeconds: int("ENTITLEMENT_NEGATIVE_CACHE_SECONDS"),
    },
    integrity: {
      // Unset means "off"; a value that is set but not recognised fails closed.
      mode:
        raw["PLAY_INTEGRITY_MODE"] === undefined || raw["PLAY_INTEGRITY_MODE"] === ""
          ? "off"
          : choice("PLAY_INTEGRITY_MODE", ["off", "enforce"] as const, "enforce"),
      maxAgeSeconds: int("PLAY_INTEGRITY_MAX_AGE_SECONDS"),
    },
  };

  const loaded: LoadedConfig = { config, invalid };
  cache.set(env, loaded);
  return loaded;
}
