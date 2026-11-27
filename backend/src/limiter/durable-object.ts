import { DurableObject } from "cloudflare:workers";
import type { Env } from "../env";
import { LimiterCore, type SqlValue } from "./core";
import type {
  AdmitInput,
  AdmitResult,
  PutEntitlementInput,
  RateLimitInput,
  RateLimitResult,
  SettleInput,
  SettleResult,
} from "./types";

/**
 * Single SQLite-backed Durable Object (`idFromName("global")`) holding every
 * counter. One instance gives strongly consistent, atomic check-and-increment
 * semantics for the per-install quotas and for the global budget, and stays
 * well inside the Workers Free plan allowances (see README).
 *
 * Each RPC method is synchronous and runs inside one storage transaction, so
 * concurrent requests can never interleave between a check and its increment.
 */
export class LimiterDO extends DurableObject<Env> {
  private readonly core: LimiterCore;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    const storage = ctx.storage;
    this.core = new LimiterCore({
      exec: (query: string, ...bindings: SqlValue[]) =>
        storage.sql.exec<Record<string, SqlValue>>(query, ...bindings).toArray(),
      transaction: <T>(fn: () => T): T => storage.transactionSync(fn),
    });
  }

  rateLimit(input: RateLimitInput): RateLimitResult {
    return this.core.rateLimit(input);
  }

  admit(input: AdmitInput): AdmitResult {
    return this.core.admit(input);
  }

  settle(input: SettleInput): SettleResult {
    return this.core.settle(input);
  }

  putEntitlement(input: PutEntitlementInput): void {
    this.core.putEntitlement(input);
  }
}
