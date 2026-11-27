import { describe, expect, it } from "vitest";
import { GoogleRequestError } from "../src/google/auth";
import {
  mapProductPurchase,
  mapSubscriptionPurchase,
  verifyPurchaseWithGoogle,
  type VerifyPurchaseInput,
} from "../src/google/play-purchases";
import { parseServiceAccount, type ServiceAccount } from "../src/google/service-account";
import { createRuntimeCaches, type AppDeps } from "../src/runtime";
import {
  DAY,
  FetchMock,
  GOOGLE_ACCESS_TOKEN,
  GOOGLE_OAUTH_HOST,
  googleTokenReply,
  jsonReply,
  PLAY_API_HOST,
  PURCHASE_TOKEN,
  serviceAccountJson,
  T0,
  TestClock,
} from "./helpers/harness";

const MONTHLY = "md_scanner_premium_monthly";
const LIFETIME = "md_scanner_premium_lifetime";
const FUTURE = new Date(T0 + 10 * DAY).toISOString();
const PAST = new Date(T0 - 2 * DAY).toISOString();

function subscription(state: string, extra: Record<string, unknown> = {}, item: Record<string, unknown> = {}): unknown {
  return {
    kind: "androidpublisher#subscriptionPurchaseV2",
    subscriptionState: state,
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    lineItems: [{ productId: MONTHLY, expiryTime: FUTURE, autoRenewingPlan: { autoRenewEnabled: true }, ...item }],
    ...extra,
  };
}

describe("subscription state mapping (purchases.subscriptionsv2)", () => {
  it("active: entitled, auto-renewing, with expiry", () => {
    expect(mapSubscriptionPurchase(subscription("SUBSCRIPTION_STATE_ACTIVE"), MONTHLY, T0)).toEqual({
      valid: true,
      state: "active",
      expiryTimeMillis: T0 + 10 * DAY,
      autoRenewing: true,
      acknowledged: true,
    });
  });

  it("canceled: still entitled until the paid period ends, with the cancel reason", () => {
    const body = subscription(
      "SUBSCRIPTION_STATE_CANCELED",
      { canceledStateContext: { userInitiatedCancellation: { cancelTime: PAST } } },
      { autoRenewingPlan: { autoRenewEnabled: false } },
    );
    expect(mapSubscriptionPurchase(body, MONTHLY, T0)).toEqual({
      valid: true,
      state: "canceled",
      expiryTimeMillis: T0 + 10 * DAY,
      autoRenewing: false,
      acknowledged: true,
      cancelReason: "user",
    });
    // Once the paid period is over the same resource no longer entitles.
    expect(mapSubscriptionPurchase(body, MONTHLY, T0 + 11 * DAY).valid).toBe(false);
  });

  it("grace period: entitled while Google retries the payment", () => {
    const result = mapSubscriptionPurchase(subscription("SUBSCRIPTION_STATE_IN_GRACE_PERIOD"), MONTHLY, T0);
    expect(result).toMatchObject({ valid: true, state: "grace_period" });
  });

  it.each([
    ["SUBSCRIPTION_STATE_ON_HOLD", "on_hold"],
    ["SUBSCRIPTION_STATE_PAUSED", "paused"],
    ["SUBSCRIPTION_STATE_PENDING", "pending"],
    ["SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED", "pending_purchase_canceled"],
    ["SUBSCRIPTION_STATE_UNSPECIFIED", "unknown"],
    ["SOME_FUTURE_STATE", "unknown"],
  ])("%s is not entitled (%s)", (googleState, state) => {
    expect(mapSubscriptionPurchase(subscription(googleState), MONTHLY, T0)).toMatchObject({ valid: false, state });
  });

  it("expired, including a subscription revoked or refunded by the developer", () => {
    const body = subscription(
      "SUBSCRIPTION_STATE_EXPIRED",
      { canceledStateContext: { developerInitiatedCancellation: {} } },
      { expiryTime: PAST, autoRenewingPlan: { autoRenewEnabled: false } },
    );
    expect(mapSubscriptionPurchase(body, MONTHLY, T0)).toEqual({
      valid: false,
      state: "expired",
      expiryTimeMillis: T0 - 2 * DAY,
      autoRenewing: false,
      acknowledged: true,
      cancelReason: "developer",
    });
  });

  it("reports system and replacement cancellations", () => {
    const system = subscription("SUBSCRIPTION_STATE_EXPIRED", { canceledStateContext: { systemInitiatedCancellation: {} } });
    const replaced = subscription("SUBSCRIPTION_STATE_EXPIRED", { canceledStateContext: { replacementCancellation: {} } });
    expect(mapSubscriptionPurchase(system, MONTHLY, T0).cancelReason).toBe("system");
    expect(mapSubscriptionPurchase(replaced, MONTHLY, T0).cancelReason).toBe("replaced");
  });

  it("never entitles an active state whose expiry is already in the past", () => {
    const body = subscription("SUBSCRIPTION_STATE_ACTIVE", {}, { expiryTime: PAST });
    expect(mapSubscriptionPurchase(body, MONTHLY, T0).valid).toBe(false);
  });

  it("rejects a token that belongs to another product", () => {
    const body = subscription("SUBSCRIPTION_STATE_ACTIVE", {}, { productId: "another_product" });
    expect(mapSubscriptionPurchase(body, MONTHLY, T0)).toEqual({ valid: false, state: "product_mismatch", acknowledged: true });
  });

  it("reports an unacknowledged purchase", () => {
    const body = subscription("SUBSCRIPTION_STATE_ACTIVE", { acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING" });
    expect(mapSubscriptionPurchase(body, MONTHLY, T0).acknowledged).toBe(false);
  });

  it("treats malformed resources as unknown", () => {
    expect(mapSubscriptionPurchase(null, MONTHLY, T0)).toEqual({ valid: false, state: "unknown" });
    expect(mapSubscriptionPurchase("nope", MONTHLY, T0)).toEqual({ valid: false, state: "unknown" });
    expect(mapSubscriptionPurchase({}, MONTHLY, T0).state).toBe("product_mismatch");
  });
});

describe("one-time product state mapping (purchases.products)", () => {
  it.each([
    [0, true, "active"],
    [1, false, "revoked"],
    [2, false, "pending"],
    [7, false, "unknown"],
  ])("purchaseState %i -> valid=%s, state=%s", (purchaseState, valid, state) => {
    expect(mapProductPurchase({ purchaseState, acknowledgementState: 1 }, LIFETIME)).toEqual({
      valid,
      state,
      acknowledged: true,
    });
  });

  it("rejects a token that belongs to another product and reports acknowledgement", () => {
    expect(mapProductPurchase({ purchaseState: 0, acknowledgementState: 0, productId: "other" }, LIFETIME)).toEqual({
      valid: false,
      state: "product_mismatch",
      acknowledged: false,
    });
  });
});

describe("Google Play Developer API calls", () => {
  async function setup(): Promise<{ account: ServiceAccount; deps: AppDeps; fetchMock: FetchMock; clock: TestClock }> {
    const account = parseServiceAccount(await serviceAccountJson());
    if (account === null) throw new Error("test service account should parse");
    const clock = new TestClock();
    const fetchMock = new FetchMock().on(GOOGLE_OAUTH_HOST, () => googleTokenReply());
    return { account, deps: { now: clock.now, fetch: fetchMock.fetch, caches: createRuntimeCaches() }, fetchMock, clock };
  }

  const subscriptionInput: VerifyPurchaseInput = {
    packageName: "dev.marcelalle.mdscanner",
    productId: MONTHLY,
    purchaseType: "subscription",
    purchaseToken: PURCHASE_TOKEN,
  };

  it("uses subscriptionsv2 for subscriptions, with the bearer access token", async () => {
    const { account, deps, fetchMock } = await setup();
    fetchMock.on(PLAY_API_HOST, () => jsonReply(200, subscription("SUBSCRIPTION_STATE_ACTIVE")));

    const result = await verifyPurchaseWithGoogle(account, subscriptionInput, { deps, timeoutMs: 5000 });
    expect(result).toMatchObject({ valid: true, state: "active" });

    const [call] = fetchMock.callsTo(PLAY_API_HOST);
    expect(call?.method).toBe("GET");
    expect(call?.url.pathname).toBe(
      `/androidpublisher/v3/applications/dev.marcelalle.mdscanner/purchases/subscriptionsv2/tokens/${PURCHASE_TOKEN}`,
    );
    expect(call?.headers.get("authorization")).toBe(`Bearer ${GOOGLE_ACCESS_TOKEN}`);
  });

  it("uses purchases.products for the one-time product and URL-encodes the token", async () => {
    const { account, deps, fetchMock } = await setup();
    fetchMock.on(PLAY_API_HOST, () => jsonReply(200, { purchaseState: 0, acknowledgementState: 1 }));

    const result = await verifyPurchaseWithGoogle(
      account,
      { ...subscriptionInput, productId: LIFETIME, purchaseType: "product", purchaseToken: "tok/with+odd=chars" },
      { deps, timeoutMs: 5000 },
    );
    expect(result).toEqual({ valid: true, state: "active", acknowledged: true });
    expect(fetchMock.callsTo(PLAY_API_HOST)[0]?.url.pathname).toBe(
      `/androidpublisher/v3/applications/dev.marcelalle.mdscanner/purchases/products/${LIFETIME}/tokens/tok%2Fwith%2Bodd%3Dchars`,
    );
  });

  it.each([
    [400, "not_found"],
    [404, "not_found"],
    [410, "expired"],
  ])("maps HTTP %i to a non-entitled result (%s)", async (status, state) => {
    const { account, deps, fetchMock } = await setup();
    fetchMock.on(PLAY_API_HOST, () => jsonReply(status, { error: { code: status } }));
    await expect(verifyPurchaseWithGoogle(account, subscriptionInput, { deps, timeoutMs: 5000 })).resolves.toEqual({
      valid: false,
      state,
    });
  });

  it("refreshes the access token once on 401, then reports a credentials problem", async () => {
    const { account, deps, fetchMock } = await setup();
    let playCalls = 0;
    fetchMock.on(PLAY_API_HOST, () => {
      playCalls += 1;
      return playCalls === 1 ? jsonReply(401, {}) : jsonReply(200, subscription("SUBSCRIPTION_STATE_ACTIVE"));
    });
    await expect(verifyPurchaseWithGoogle(account, subscriptionInput, { deps, timeoutMs: 5000 })).resolves.toMatchObject({
      valid: true,
    });
    expect(fetchMock.callsTo(GOOGLE_OAUTH_HOST)).toHaveLength(2);

    fetchMock.on(PLAY_API_HOST, () => jsonReply(401, {}));
    const error = await verifyPurchaseWithGoogle(account, subscriptionInput, { deps, timeoutMs: 5000 }).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(GoogleRequestError);
    expect(error).toMatchObject({ kind: "credentials", status: 401 });
  });

  it.each([
    [403, "credentials"],
    [429, "unavailable"],
    [500, "unavailable"],
    [503, "unavailable"],
  ])("throws for HTTP %i (%s): Google gave no usable answer", async (status, kind) => {
    const { account, deps, fetchMock } = await setup();
    fetchMock.on(PLAY_API_HOST, () => jsonReply(status, { error: { message: "details that must not leak" } }));
    await expect(verifyPurchaseWithGoogle(account, subscriptionInput, { deps, timeoutMs: 5000 })).rejects.toMatchObject({
      kind,
      status,
    });
  });

  it("throws when Google cannot be reached", async () => {
    const { account, deps, fetchMock } = await setup();
    fetchMock.on(PLAY_API_HOST, () => {
      throw new TypeError("fetch failed");
    });
    await expect(verifyPurchaseWithGoogle(account, subscriptionInput, { deps, timeoutMs: 5000 })).rejects.toMatchObject({
      kind: "unavailable",
    });
  });
});
