import type { Env } from "../env";
import { internalError } from "../http/errors";
import type {
  AdmitInput,
  AdmitResult,
  LimiterApi,
  PutEntitlementInput,
  RateLimitInput,
  RateLimitResult,
  SettleInput,
  SettleResult,
} from "./types";

const LIMITER_INSTANCE_NAME = "global";

/**
 * Typed access to the limiter Durable Object.
 *
 * Fail-closed: if the limiter cannot be reached (for example because a
 * platform allowance is exhausted), admission calls throw a 503 instead of
 * letting requests through unmetered.
 */
export function getLimiter(env: Env): LimiterApi {
  const stub = env.LIMITER.get(env.LIMITER.idFromName(LIMITER_INSTANCE_NAME));
  return {
    rateLimit: (input: RateLimitInput) => guard<RateLimitResult>(() => stub.rateLimit(input)),
    admit: (input: AdmitInput) => guard<AdmitResult>(() => stub.admit(input)),
    settle: async (input: SettleInput): Promise<SettleResult> => await stub.settle(input),
    putEntitlement: async (input: PutEntitlementInput): Promise<void> => {
      await stub.putEntitlement(input);
    },
  };
}

async function guard<T>(call: () => PromiseLike<T>): Promise<T> {
  try {
    return await call();
  } catch {
    throw internalError("limiter_unavailable", 503, 60);
  }
}
