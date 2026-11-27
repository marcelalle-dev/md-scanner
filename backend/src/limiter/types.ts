/**
 * Contract between the Worker and the limiter Durable Object.
 * Every value is a plain serialisable object so it can cross the RPC boundary.
 * The Worker supplies `now` on each call: the limiter has a single, explicit
 * time source, which keeps its behaviour deterministic and testable.
 */

export type Tier = "premium" | "free";
export type RateLimitBucket = "ai" | "verify";

/** Result of a Google Play verification, cached briefly by the limiter. */
export interface CachedEntitlement {
  /** True when the purchase currently grants premium access. */
  premium: boolean;
  /** Normalised purchase state (see `google/play-purchases.ts`). */
  state: string;
  /** Subscription expiry in epoch milliseconds, null for one-time products. */
  expiryMs: number | null;
}

export interface RateLimitInput {
  now: number;
  bucket: RateLimitBucket;
  ipKey: string;
  limit: number;
  windowSeconds: number;
}

export interface RateLimitResult {
  allowed: boolean;
  limit: number;
  remaining: number;
  retryAfterSeconds: number;
}

export interface LimiterLimits {
  rateLimitMax: number;
  rateLimitWindowSeconds: number;
  dailyRequests: number;
  freeDailyRequests: number;
  freeGlobalDailyRequests: number;
  monthlyTokenBudget: number;
  globalDailyTokenBudget: number;
  entitlementCacheSeconds: number;
  entitlementNegativeCacheSeconds: number;
}

export interface AdmitInput {
  now: number;
  ipKey: string;
  installId: string;
  /** SHA-256 of `productId:purchaseToken`, or null when no purchase was presented. */
  purchaseKey: string | null;
  /** Fresh verification result, supplied on the second call after `needs_verification`. */
  verified?: CachedEntitlement;
  /** True when the burst limit was already counted for this request. */
  skipRateLimit: boolean;
  /** Worst-case budget units reserved for this request before calling the model. */
  reserveUnits: number;
  limits: LimiterLimits;
}

export interface PeriodUsage {
  limit: number;
  used: number;
  /** Epoch milliseconds at which the period resets. */
  resetsAt: number;
}

export interface Admission {
  outcome: "admitted";
  tier: Tier;
  /** Quota subject: the purchase for premium users, the install for the free tier. */
  subject: string;
  admittedAt: number;
  reservedUnits: number;
  daily: PeriodUsage;
  monthly: PeriodUsage;
}

export type QuotaReason = "daily_requests" | "monthly_tokens" | "free_pool_exhausted";

export type AdmitResult =
  | Admission
  | { outcome: "needs_verification" }
  | { outcome: "rate_limited"; retryAfterSeconds: number }
  | { outcome: "premium_required"; purchaseState: string | null }
  | {
      outcome: "quota_exceeded";
      reason: QuotaReason;
      tier: Tier;
      limit: number;
      resetsAt: number;
      retryAfterSeconds: number;
    }
  | { outcome: "global_budget_exhausted"; resetsAt: number; retryAfterSeconds: number };

export interface SettleInput {
  subject: string;
  tier: Tier;
  admittedAt: number;
  reservedUnits: number;
  /** Budget units actually consumed (0 when the model was never reached). */
  actualUnits: number;
  /** False when no result was delivered: the daily request is given back. */
  countRequest: boolean;
}

export interface SettleResult {
  dailyUsed: number;
  monthlyUsed: number;
}

export interface PutEntitlementInput {
  now: number;
  purchaseKey: string;
  entitlement: CachedEntitlement;
  positiveTtlSeconds: number;
  negativeTtlSeconds: number;
}

/** Asynchronous facade used by the Worker (Durable Object stub in production). */
export interface LimiterApi {
  rateLimit(input: RateLimitInput): Promise<RateLimitResult>;
  admit(input: AdmitInput): Promise<AdmitResult>;
  settle(input: SettleInput): Promise<SettleResult>;
  putEntitlement(input: PutEntitlementInput): Promise<void>;
}
