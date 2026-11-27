import { beforeEach, describe, expect, it } from "vitest";
import { LimiterCore } from "../src/limiter/core";
import type { AdmitInput, AdmitResult, Admission, LimiterLimits } from "../src/limiter/types";
import { createSqliteDriver, DAY, HOUR, INSTALL_ID, MINUTE, OTHER_INSTALL_ID, T0 } from "./helpers/harness";

const LIMITS: LimiterLimits = {
  rateLimitMax: 3,
  rateLimitWindowSeconds: 60,
  dailyRequests: 2,
  freeDailyRequests: 0,
  freeGlobalDailyRequests: 5,
  monthlyTokenBudget: 10_000,
  globalDailyTokenBudget: 50_000,
  entitlementCacheSeconds: 600,
  entitlementNegativeCacheSeconds: 60,
};

const PURCHASE_KEY = "a".repeat(64);
const ACTIVE = { premium: true, state: "active", expiryMs: T0 + 30 * DAY };

let core: LimiterCore;

function admitInput(overrides: Partial<AdmitInput> = {}): AdmitInput {
  return {
    now: T0,
    ipKey: "ip-1",
    installId: INSTALL_ID,
    purchaseKey: PURCHASE_KEY,
    skipRateLimit: true,
    reserveUnits: 1_000,
    limits: LIMITS,
    ...overrides,
  };
}

function expectAdmitted(result: AdmitResult): Admission {
  expect(result.outcome).toBe("admitted");
  return result as Admission;
}

beforeEach(() => {
  core = new LimiterCore(createSqliteDriver());
});

describe("burst rate limit", () => {
  it("allows up to the limit per window, then rejects with the time left in the window", () => {
    const input = { now: T0 + 10_000, bucket: "verify" as const, ipKey: "ip-1", limit: 3, windowSeconds: 60 };
    expect(core.rateLimit(input)).toMatchObject({ allowed: true, remaining: 2 });
    expect(core.rateLimit(input)).toMatchObject({ allowed: true, remaining: 1 });
    expect(core.rateLimit(input)).toMatchObject({ allowed: true, remaining: 0 });
    expect(core.rateLimit(input)).toEqual({ allowed: false, limit: 3, remaining: 0, retryAfterSeconds: 50 });
  });

  it("starts a fresh window when the clock moves on", () => {
    const input = { now: T0, bucket: "verify" as const, ipKey: "ip-1", limit: 1, windowSeconds: 60 };
    expect(core.rateLimit(input).allowed).toBe(true);
    expect(core.rateLimit({ ...input, now: T0 + 59_000 }).allowed).toBe(false);
    expect(core.rateLimit({ ...input, now: T0 + 60_000 }).allowed).toBe(true);
  });

  it("keeps addresses and buckets independent", () => {
    const input = { now: T0, bucket: "verify" as const, ipKey: "ip-1", limit: 1, windowSeconds: 60 };
    expect(core.rateLimit(input).allowed).toBe(true);
    expect(core.rateLimit({ ...input, ipKey: "ip-2" }).allowed).toBe(true);
    expect(core.rateLimit({ ...input, bucket: "ai" }).allowed).toBe(true);
    expect(core.rateLimit(input).allowed).toBe(false);
  });

  it("is applied by admit unless it was already counted", () => {
    const input = admitInput({ skipRateLimit: false, verified: ACTIVE, limits: { ...LIMITS, dailyRequests: 100 } });
    for (let i = 0; i < 3; i += 1) expectAdmitted(core.admit(input));
    expect(core.admit(input)).toEqual({ outcome: "rate_limited", retryAfterSeconds: 60 });
    expectAdmitted(core.admit({ ...input, skipRateLimit: true }));
  });

  it("rejects everything when the limit is zero", () => {
    const input = { now: T0, bucket: "ai" as const, ipKey: "ip-1", limit: 0, windowSeconds: 60 };
    expect(core.rateLimit(input).allowed).toBe(false);
  });
});

describe("premium entitlement", () => {
  it("asks for verification when the purchase is unknown, then caches the verified result", () => {
    expect(core.admit(admitInput())).toEqual({ outcome: "needs_verification" });
    const admission = expectAdmitted(core.admit(admitInput({ verified: ACTIVE })));
    expect(admission.tier).toBe("premium");
    expect(admission.subject).toBe(`p:${PURCHASE_KEY}`);
    // Cached: no verification needed for the next request.
    expectAdmitted(core.admit(admitInput({ now: T0 + 5 * MINUTE })));
  });

  it("expires the cache after its TTL", () => {
    expectAdmitted(core.admit(admitInput({ verified: ACTIVE })));
    expect(core.admit(admitInput({ now: T0 + 10 * MINUTE })).outcome).toBe("needs_verification");
  });

  it("never trusts a cached subscription past its own expiry", () => {
    const expiringSoon = { premium: true, state: "active", expiryMs: T0 + 2 * MINUTE };
    expectAdmitted(core.admit(admitInput({ verified: expiringSoon })));
    expect(core.admit(admitInput({ now: T0 + 1 * MINUTE })).outcome).toBe("admitted");
    expect(core.admit(admitInput({ now: T0 + 2 * MINUTE })).outcome).toBe("needs_verification");
  });

  it("returns premium_required with the purchase state for an inactive purchase, cached briefly", () => {
    const expired = { premium: false, state: "expired", expiryMs: null };
    expect(core.admit(admitInput({ verified: expired }))).toEqual({
      outcome: "premium_required",
      purchaseState: "expired",
    });
    // Negative result is cached for 60 s, then verified again.
    expect(core.admit(admitInput({ now: T0 + 30_000 })).outcome).toBe("premium_required");
    expect(core.admit(admitInput({ now: T0 + 61_000 })).outcome).toBe("needs_verification");
  });

  it("requires premium when no purchase is presented and the free trial is off", () => {
    expect(core.admit(admitInput({ purchaseKey: null }))).toEqual({ outcome: "premium_required", purchaseState: null });
  });

  it("stores an entitlement pushed by the purchase endpoint", () => {
    core.putEntitlement({ now: T0, purchaseKey: PURCHASE_KEY, entitlement: ACTIVE, positiveTtlSeconds: 600, negativeTtlSeconds: 60 });
    expectAdmitted(core.admit(admitInput()));
  });
});

describe("daily request quota", () => {
  it("counts requests per purchase and resets at the next UTC midnight", () => {
    const first = expectAdmitted(core.admit(admitInput({ verified: ACTIVE })));
    expect(first.daily).toEqual({ limit: 2, used: 1, resetsAt: Date.UTC(2026, 10, 28) });
    expectAdmitted(core.admit(admitInput()));

    expect(core.admit(admitInput())).toEqual({
      outcome: "quota_exceeded",
      reason: "daily_requests",
      tier: "premium",
      limit: 2,
      resetsAt: Date.UTC(2026, 10, 28),
      retryAfterSeconds: 14 * 3600,
    });

    // Next UTC day (the entitlement cache has expired, so it is verified again).
    const nextDay = expectAdmitted(core.admit(admitInput({ now: T0 + 14 * HOUR, verified: ACTIVE })));
    expect(nextDay.daily.used).toBe(1);
  });

  it("follows the purchase, not the install", () => {
    expectAdmitted(core.admit(admitInput({ verified: ACTIVE })));
    expectAdmitted(core.admit(admitInput({ installId: OTHER_INSTALL_ID })));
    expect(core.admit(admitInput({ installId: OTHER_INSTALL_ID })).outcome).toBe("quota_exceeded");
  });

  it("gives the request back when no result was delivered", () => {
    const admission = expectAdmitted(core.admit(admitInput({ verified: ACTIVE })));
    const settled = core.settle({
      subject: admission.subject,
      tier: admission.tier,
      admittedAt: admission.admittedAt,
      reservedUnits: admission.reservedUnits,
      actualUnits: 0,
      countRequest: false,
    });
    expect(settled).toEqual({ dailyUsed: 0, monthlyUsed: 0 });
    expectAdmitted(core.admit(admitInput()));
    expectAdmitted(core.admit(admitInput()));
    expect(core.admit(admitInput()).outcome).toBe("quota_exceeded");
  });
});

describe("free trial", () => {
  const FREE: LimiterLimits = { ...LIMITS, freeDailyRequests: 1, freeGlobalDailyRequests: 2 };

  it("grants a per-install daily allowance to non-premium installs", () => {
    const admission = expectAdmitted(core.admit(admitInput({ purchaseKey: null, limits: FREE })));
    expect(admission.tier).toBe("free");
    expect(admission.subject).toBe(`i:${INSTALL_ID}`);
    expect(core.admit(admitInput({ purchaseKey: null, limits: FREE }))).toMatchObject({
      outcome: "quota_exceeded",
      reason: "daily_requests",
      tier: "free",
    });
  });

  it("caps the free tier globally so rotating install ids cannot drain the budget", () => {
    expectAdmitted(core.admit(admitInput({ purchaseKey: null, limits: FREE, installId: "install-a" })));
    expectAdmitted(core.admit(admitInput({ purchaseKey: null, limits: FREE, installId: "install-b" })));
    expect(core.admit(admitInput({ purchaseKey: null, limits: FREE, installId: "install-c" }))).toMatchObject({
      outcome: "quota_exceeded",
      reason: "free_pool_exhausted",
    });
  });

  it("lets an inactive purchase fall back to the free allowance", () => {
    const expired = { premium: false, state: "expired", expiryMs: null };
    const admission = expectAdmitted(core.admit(admitInput({ verified: expired, limits: FREE })));
    expect(admission.tier).toBe("free");
  });
});

describe("token budgets", () => {
  it("reserves the worst case, then settles to the real usage", () => {
    const admission = expectAdmitted(core.admit(admitInput({ verified: ACTIVE, reserveUnits: 4_000 })));
    expect(admission.monthly).toEqual({ limit: 10_000, used: 4_000, resetsAt: Date.UTC(2026, 11, 1) });
    const settled = core.settle({
      subject: admission.subject,
      tier: "premium",
      admittedAt: admission.admittedAt,
      reservedUnits: 4_000,
      actualUnits: 1_500,
      countRequest: true,
    });
    expect(settled).toEqual({ dailyUsed: 1, monthlyUsed: 1_500 });
  });

  it("enforces the monthly budget per subject and resets it on the first of the month", () => {
    const limits = { ...LIMITS, dailyRequests: 100 };
    expectAdmitted(core.admit(admitInput({ verified: ACTIVE, reserveUnits: 6_000, limits })));
    expect(core.admit(admitInput({ reserveUnits: 6_000, limits }))).toEqual({
      outcome: "quota_exceeded",
      reason: "monthly_tokens",
      tier: "premium",
      limit: 10_000,
      resetsAt: Date.UTC(2026, 11, 1),
      retryAfterSeconds: (Date.UTC(2026, 11, 1) - T0) / 1000,
    });
    // A smaller request still fits.
    expectAdmitted(core.admit(admitInput({ reserveUnits: 3_000, limits })));
    // December: a new month.
    const december = Date.UTC(2026, 11, 1, 0, 0, 1);
    const admission = expectAdmitted(core.admit(admitInput({ now: december, verified: ACTIVE, reserveUnits: 6_000, limits })));
    expect(admission.monthly.used).toBe(6_000);
  });

  it("trips the global kill-switch for everybody and recovers the next UTC day", () => {
    const limits = { ...LIMITS, dailyRequests: 100, monthlyTokenBudget: 1_000_000, globalDailyTokenBudget: 10_000 };
    expectAdmitted(core.admit(admitInput({ verified: ACTIVE, reserveUnits: 6_000, limits })));

    const otherPurchase = "b".repeat(64);
    const blocked = core.admit(admitInput({ purchaseKey: otherPurchase, reserveUnits: 6_000, limits }));
    expect(blocked).toEqual({
      outcome: "global_budget_exhausted",
      resetsAt: Date.UTC(2026, 10, 28),
      retryAfterSeconds: 14 * 3600,
    });

    const tomorrow = Date.UTC(2026, 10, 28, 0, 0, 1);
    expect(core.admit(admitInput({ now: tomorrow, purchaseKey: otherPurchase, reserveUnits: 6_000, limits })).outcome).toBe(
      "needs_verification",
    );
  });

  it("counts in-flight reservations against the global budget", () => {
    const limits = { ...LIMITS, dailyRequests: 100, monthlyTokenBudget: 1_000_000, globalDailyTokenBudget: 10_000 };
    const admission = expectAdmitted(core.admit(admitInput({ verified: ACTIVE, reserveUnits: 6_000, limits })));
    expect(core.admit(admitInput({ reserveUnits: 6_000, limits })).outcome).toBe("global_budget_exhausted");
    core.settle({
      subject: admission.subject,
      tier: "premium",
      admittedAt: admission.admittedAt,
      reservedUnits: 6_000,
      actualUnits: 1_000,
      countRequest: true,
    });
    expectAdmitted(core.admit(admitInput({ reserveUnits: 6_000, limits })));
  });

  it("acts as a manual kill-switch when the global budget is zero", () => {
    const limits = { ...LIMITS, globalDailyTokenBudget: 0 };
    expect(core.admit(admitInput({ verified: ACTIVE, limits })).outcome).toBe("global_budget_exhausted");
  });

  it("settles against the period of admission even across midnight", () => {
    const lateEvening = Date.UTC(2026, 10, 30, 23, 59, 50);
    const admission = expectAdmitted(core.admit(admitInput({ now: lateEvening, verified: ACTIVE, reserveUnits: 4_000 })));
    const settled = core.settle({
      subject: admission.subject,
      tier: "premium",
      admittedAt: admission.admittedAt,
      reservedUnits: 4_000,
      actualUnits: 2_000,
      countRequest: true,
    });
    expect(settled).toEqual({ dailyUsed: 1, monthlyUsed: 2_000 });
  });
});

describe("storage hygiene", () => {
  it("consumes nothing when a request is rejected", () => {
    const limits = { ...LIMITS, monthlyTokenBudget: 500 };
    expect(core.admit(admitInput({ verified: ACTIVE, limits })).outcome).toBe("quota_exceeded");
    // Daily counter untouched: with a sufficient budget the first request is number 1.
    const admission = expectAdmitted(core.admit(admitInput({ limits: LIMITS })));
    expect(admission.daily.used).toBe(1);
  });

  it("prunes expired rows", () => {
    expectAdmitted(core.admit(admitInput({ skipRateLimit: false, verified: ACTIVE })));
    expect(core.prune(T0)).toBeGreaterThan(0);
    expect(core.prune(T0 + 60 * DAY)).toBe(0);
  });
});
