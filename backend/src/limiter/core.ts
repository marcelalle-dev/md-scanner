import { DAY_MS, nextUtcMidnight, nextUtcMonthStart, secondsUntil, utcDayKey, utcMonthKey } from "./time";
import type {
  AdmitInput,
  AdmitResult,
  CachedEntitlement,
  PutEntitlementInput,
  RateLimitInput,
  RateLimitResult,
  SettleInput,
  SettleResult,
  Tier,
} from "./types";

export type SqlValue = string | number | null;

/**
 * Minimal synchronous SQLite surface used by the limiter. In production it is
 * backed by the Durable Object SQLite storage, in tests by `node:sqlite`.
 */
export interface SqlDriver {
  exec(query: string, ...bindings: SqlValue[]): Record<string, unknown>[];
  /** Runs `fn` atomically: either every write is kept or none. */
  transaction<T>(fn: () => T): T;
}

const PRUNE_INTERVAL_MS = 30 * 60_000;

/**
 * All counters, quotas, budgets and the short-lived entitlement cache.
 *
 * Key layout of the `counters` table (period is part of the key, so a stale
 * row can never be read for a new period):
 *   rl:<bucket>:<ipKey>:<windowStart>   burst requests per client address
 *   dq:<subject>:<YYYY-MM-DD>           requests per subject and UTC day
 *   mt:<subject>:<YYYY-MM>              budget units per subject and UTC month
 *   gt:<YYYY-MM-DD>                     budget units for the whole service
 *   fg:<YYYY-MM-DD>                     free-tier requests for the whole service
 *
 * Budgets use reserve-then-settle accounting: the worst case of a request is
 * reserved before the model is called and corrected to the real usage
 * afterwards. In-flight requests are therefore always counted, and a request
 * that never settles stays counted at its worst case (fail-safe for cost).
 */
export class LimiterCore {
  private lastPruneAt = Number.NEGATIVE_INFINITY;

  constructor(private readonly sql: SqlDriver) {
    sql.exec("CREATE TABLE IF NOT EXISTS counters (k TEXT PRIMARY KEY, v INTEGER NOT NULL, exp INTEGER NOT NULL)");
    sql.exec(
      "CREATE TABLE IF NOT EXISTS entitlements (k TEXT PRIMARY KEY, premium INTEGER NOT NULL, state TEXT NOT NULL, expiry_ms INTEGER, fresh_until INTEGER NOT NULL)",
    );
  }

  rateLimit(input: RateLimitInput): RateLimitResult {
    return this.sql.transaction(() => {
      this.pruneIfDue(input.now);
      return this.hit(input);
    });
  }

  admit(input: AdmitInput): AdmitResult {
    return this.sql.transaction(() => this.admitInTransaction(input));
  }

  settle(input: SettleInput): SettleResult {
    return this.sql.transaction(() => {
      const day = utcDayKey(input.admittedAt);
      const dayReset = nextUtcMidnight(input.admittedAt);
      const monthReset = nextUtcMonthStart(input.admittedAt);
      const dailyKey = `dq:${input.subject}:${day}`;
      const monthlyKey = `mt:${input.subject}:${utcMonthKey(input.admittedAt)}`;

      const delta = toUnits(input.actualUnits) - toUnits(input.reservedUnits);
      if (delta !== 0) {
        this.add(monthlyKey, delta, monthReset + 7 * DAY_MS);
        this.add(`gt:${day}`, delta, dayReset + DAY_MS);
      }
      if (!input.countRequest) {
        this.add(dailyKey, -1, dayReset + DAY_MS);
        if (input.tier === "free") this.add(`fg:${day}`, -1, dayReset + DAY_MS);
      }
      return { dailyUsed: this.get(dailyKey), monthlyUsed: this.get(monthlyKey) };
    });
  }

  putEntitlement(input: PutEntitlementInput): void {
    this.sql.transaction(() => {
      this.storeEntitlement(
        input.purchaseKey,
        input.entitlement,
        input.now,
        input.positiveTtlSeconds,
        input.negativeTtlSeconds,
      );
    });
  }

  /** Deletes expired rows. Returns the number of rows left, for tests and diagnostics. */
  prune(now: number): number {
    return this.sql.transaction(() => {
      this.deleteExpired(now);
      const counters = this.sql.exec("SELECT COUNT(*) AS n FROM counters")[0]?.["n"];
      const entitlements = this.sql.exec("SELECT COUNT(*) AS n FROM entitlements")[0]?.["n"];
      return Number(counters ?? 0) + Number(entitlements ?? 0);
    });
  }

  private admitInTransaction(input: AdmitInput): AdmitResult {
    const { now, limits } = input;
    this.pruneIfDue(now);

    if (!input.skipRateLimit) {
      const burst = this.hit({
        now,
        bucket: "ai",
        ipKey: input.ipKey,
        limit: limits.rateLimitMax,
        windowSeconds: limits.rateLimitWindowSeconds,
      });
      if (!burst.allowed) return { outcome: "rate_limited", retryAfterSeconds: burst.retryAfterSeconds };
    }

    const day = utcDayKey(now);
    const dayReset = nextUtcMidnight(now);
    const monthReset = nextUtcMonthStart(now);
    const reserve = toUnits(input.reserveUnits);

    // Global kill-switch first: when it is tripped nothing else is consulted
    // (in particular no purchase verification is requested from Google).
    const globalKey = `gt:${day}`;
    if (this.get(globalKey) + reserve > limits.globalDailyTokenBudget) {
      return { outcome: "global_budget_exhausted", resetsAt: dayReset, retryAfterSeconds: secondsUntil(now, dayReset) };
    }

    let tier: Tier = "free";
    let subject = `i:${input.installId}`;
    let purchaseState: string | null = null;
    if (input.purchaseKey !== null) {
      let entitlement: CachedEntitlement | null;
      if (input.verified !== undefined) {
        entitlement = input.verified;
        this.storeEntitlement(
          input.purchaseKey,
          entitlement,
          now,
          limits.entitlementCacheSeconds,
          limits.entitlementNegativeCacheSeconds,
        );
      } else {
        entitlement = this.loadEntitlement(input.purchaseKey, now);
        if (entitlement === null) return { outcome: "needs_verification" };
      }
      if (entitlement.premium) {
        // Quotas follow the purchase, not the install: reinstalling or sharing
        // a purchase token across installs does not multiply the allowance.
        tier = "premium";
        subject = `p:${input.purchaseKey}`;
      } else {
        purchaseState = entitlement.state;
      }
    }

    if (tier === "free" && limits.freeDailyRequests <= 0) {
      return { outcome: "premium_required", purchaseState };
    }

    const dailyLimit = tier === "premium" ? limits.dailyRequests : limits.freeDailyRequests;
    const dailyKey = `dq:${subject}:${day}`;
    const dailyUsed = this.get(dailyKey);
    if (dailyUsed >= dailyLimit) {
      return {
        outcome: "quota_exceeded",
        reason: "daily_requests",
        tier,
        limit: dailyLimit,
        resetsAt: dayReset,
        retryAfterSeconds: secondsUntil(now, dayReset),
      };
    }

    const freePoolKey = `fg:${day}`;
    if (tier === "free" && this.get(freePoolKey) >= limits.freeGlobalDailyRequests) {
      return {
        outcome: "quota_exceeded",
        reason: "free_pool_exhausted",
        tier,
        limit: limits.freeGlobalDailyRequests,
        resetsAt: dayReset,
        retryAfterSeconds: secondsUntil(now, dayReset),
      };
    }

    const monthlyKey = `mt:${subject}:${utcMonthKey(now)}`;
    const monthlyUsed = this.get(monthlyKey);
    if (monthlyUsed + reserve > limits.monthlyTokenBudget) {
      return {
        outcome: "quota_exceeded",
        reason: "monthly_tokens",
        tier,
        limit: limits.monthlyTokenBudget,
        resetsAt: monthReset,
        retryAfterSeconds: secondsUntil(now, monthReset),
      };
    }

    this.add(dailyKey, 1, dayReset + DAY_MS);
    this.add(monthlyKey, reserve, monthReset + 7 * DAY_MS);
    this.add(globalKey, reserve, dayReset + DAY_MS);
    if (tier === "free") this.add(freePoolKey, 1, dayReset + DAY_MS);

    return {
      outcome: "admitted",
      tier,
      subject,
      admittedAt: now,
      reservedUnits: reserve,
      daily: { limit: dailyLimit, used: dailyUsed + 1, resetsAt: dayReset },
      monthly: { limit: limits.monthlyTokenBudget, used: monthlyUsed + reserve, resetsAt: monthReset },
    };
  }

  /** Fixed-window counter. A rejected request is not counted. */
  private hit(input: RateLimitInput): RateLimitResult {
    const windowMs = Math.max(1, input.windowSeconds) * 1000;
    const windowStart = Math.floor(input.now / windowMs) * windowMs;
    const windowEnd = windowStart + windowMs;
    const key = `rl:${input.bucket}:${input.ipKey}:${windowStart}`;
    const used = this.get(key);
    const retryAfterSeconds = secondsUntil(input.now, windowEnd);
    if (used >= input.limit) {
      return { allowed: false, limit: input.limit, remaining: 0, retryAfterSeconds };
    }
    this.add(key, 1, windowEnd + windowMs);
    return { allowed: true, limit: input.limit, remaining: input.limit - used - 1, retryAfterSeconds };
  }

  private loadEntitlement(purchaseKey: string, now: number): CachedEntitlement | null {
    const row = this.sql.exec(
      "SELECT premium, state, expiry_ms, fresh_until FROM entitlements WHERE k = ?",
      purchaseKey,
    )[0];
    if (row === undefined) return null;
    const freshUntil = Number(row["fresh_until"]);
    if (!(freshUntil > now)) return null;
    const premium = Number(row["premium"]) === 1;
    const expiryMs = row["expiry_ms"] === null || row["expiry_ms"] === undefined ? null : Number(row["expiry_ms"]);
    // A cached subscription is never trusted past its own expiry: it must be
    // verified again (it may have been renewed, or it may have lapsed).
    if (premium && expiryMs !== null && expiryMs <= now) return null;
    return { premium, state: String(row["state"]), expiryMs };
  }

  private storeEntitlement(
    purchaseKey: string,
    entitlement: CachedEntitlement,
    now: number,
    positiveTtlSeconds: number,
    negativeTtlSeconds: number,
  ): void {
    const ttlMs = (entitlement.premium ? positiveTtlSeconds : negativeTtlSeconds) * 1000;
    let freshUntil = now + ttlMs;
    if (entitlement.premium && entitlement.expiryMs !== null) freshUntil = Math.min(freshUntil, entitlement.expiryMs);
    this.sql.exec(
      "INSERT INTO entitlements (k, premium, state, expiry_ms, fresh_until) VALUES (?, ?, ?, ?, ?) " +
        "ON CONFLICT(k) DO UPDATE SET premium = excluded.premium, state = excluded.state, " +
        "expiry_ms = excluded.expiry_ms, fresh_until = excluded.fresh_until",
      purchaseKey,
      entitlement.premium ? 1 : 0,
      entitlement.state.slice(0, 64),
      entitlement.expiryMs,
      freshUntil,
    );
  }

  private get(key: string): number {
    const value = this.sql.exec("SELECT v FROM counters WHERE k = ?", key)[0]?.["v"];
    return typeof value === "number" || typeof value === "bigint" ? Number(value) : 0;
  }

  /** Adds `delta` (possibly negative) to a counter, never going below zero. */
  private add(key: string, delta: number, expiresAt: number): void {
    this.sql.exec(
      "INSERT INTO counters (k, v, exp) VALUES (?, MAX(0, ?), ?) ON CONFLICT(k) DO UPDATE SET v = MAX(0, v + ?)",
      key,
      delta,
      expiresAt,
      delta,
    );
  }

  private pruneIfDue(now: number): void {
    if (now - this.lastPruneAt < PRUNE_INTERVAL_MS) return;
    this.lastPruneAt = now;
    this.deleteExpired(now);
  }

  private deleteExpired(now: number): void {
    this.sql.exec("DELETE FROM counters WHERE exp <= ?", now);
    this.sql.exec("DELETE FROM entitlements WHERE fresh_until <= ?", now);
  }
}

function toUnits(value: number): number {
  return Number.isFinite(value) ? Math.max(0, Math.ceil(value)) : 0;
}
