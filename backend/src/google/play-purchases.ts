import type { PurchaseType } from "../purchases/products";
import {
  getAccessToken,
  GoogleRequestError,
  invalidateAccessToken,
  SCOPE_ANDROID_PUBLISHER,
  type GoogleCallOptions,
} from "./auth";
import type { ServiceAccount } from "./service-account";

const ANDROID_PUBLISHER_BASE = "https://androidpublisher.googleapis.com/androidpublisher/v3";

/**
 * Normalised purchase state returned by the API.
 *
 * Subscriptions (purchases.subscriptionsv2):
 *   active                      SUBSCRIPTION_STATE_ACTIVE
 *   canceled                    SUBSCRIPTION_STATE_CANCELED (auto-renew off, access kept until expiry)
 *   grace_period                SUBSCRIPTION_STATE_IN_GRACE_PERIOD (payment issue, access kept)
 *   on_hold                     SUBSCRIPTION_STATE_ON_HOLD (payment issue, access suspended)
 *   paused                      SUBSCRIPTION_STATE_PAUSED
 *   expired                     SUBSCRIPTION_STATE_EXPIRED (also what Google reports once a
 *                               subscription has been revoked or refunded with revocation)
 *   pending                     SUBSCRIPTION_STATE_PENDING (first payment not completed)
 *   pending_purchase_canceled   SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED
 * One-time products (purchases.products):
 *   active                      purchaseState 0 (purchased)
 *   revoked                     purchaseState 1 (canceled, refunded or revoked)
 *   pending                     purchaseState 2
 * Both:
 *   not_found                   the token is unknown to Google Play (HTTP 400 / 404)
 *   expired                     the token is no longer retained by Google Play (HTTP 410)
 *   product_mismatch            the token belongs to another product
 *   unknown                     unspecified or unrecognised state
 */
export type PurchaseState =
  | "active"
  | "canceled"
  | "grace_period"
  | "on_hold"
  | "paused"
  | "expired"
  | "pending"
  | "pending_purchase_canceled"
  | "revoked"
  | "not_found"
  | "product_mismatch"
  | "unknown";

export type CancelReason = "user" | "system" | "developer" | "replaced";

export interface PurchaseVerification {
  /** True when the purchase grants premium access right now. */
  valid: boolean;
  state: PurchaseState;
  /** Subscriptions only. */
  expiryTimeMillis?: number;
  /** Subscriptions only. */
  autoRenewing?: boolean;
  acknowledged?: boolean;
  /** Subscriptions in state `canceled` or `expired`, when Google reports it. */
  cancelReason?: CancelReason;
}

const SUBSCRIPTION_STATES: Readonly<Record<string, PurchaseState>> = {
  SUBSCRIPTION_STATE_ACTIVE: "active",
  SUBSCRIPTION_STATE_CANCELED: "canceled",
  SUBSCRIPTION_STATE_IN_GRACE_PERIOD: "grace_period",
  SUBSCRIPTION_STATE_ON_HOLD: "on_hold",
  SUBSCRIPTION_STATE_PAUSED: "paused",
  SUBSCRIPTION_STATE_EXPIRED: "expired",
  SUBSCRIPTION_STATE_PENDING: "pending",
  SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED: "pending_purchase_canceled",
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function cancelReasonOf(context: unknown): CancelReason | undefined {
  if (!isRecord(context)) return undefined;
  if (isRecord(context["userInitiatedCancellation"])) return "user";
  if (isRecord(context["systemInitiatedCancellation"])) return "system";
  if (isRecord(context["developerInitiatedCancellation"])) return "developer";
  if (isRecord(context["replacementCancellation"])) return "replaced";
  return undefined;
}

/** Maps a `SubscriptionPurchaseV2` resource to the normalised verification result. */
export function mapSubscriptionPurchase(body: unknown, productId: string, nowMs: number): PurchaseVerification {
  if (!isRecord(body)) return { valid: false, state: "unknown" };

  const acknowledged = body["acknowledgementState"] === "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED";
  const lineItems = Array.isArray(body["lineItems"]) ? body["lineItems"].filter(isRecord) : [];
  const item = lineItems.find((candidate) => candidate["productId"] === productId);
  if (item === undefined) return { valid: false, state: "product_mismatch", acknowledged };

  const state = SUBSCRIPTION_STATES[String(body["subscriptionState"])] ?? "unknown";
  const parsedExpiry = typeof item["expiryTime"] === "string" ? Date.parse(item["expiryTime"]) : Number.NaN;
  const expiryTimeMillis = Number.isFinite(parsedExpiry) ? parsedExpiry : undefined;
  const plan = item["autoRenewingPlan"];
  const autoRenewing = isRecord(plan) && plan["autoRenewEnabled"] === true;

  let valid: boolean;
  switch (state) {
    case "active":
    case "canceled":
      // Entitled until the paid period ends.
      valid = expiryTimeMillis === undefined || expiryTimeMillis > nowMs;
      break;
    case "grace_period":
      // Google asks to keep access while it retries the payment.
      valid = true;
      break;
    default:
      valid = false;
  }

  const result: PurchaseVerification = { valid, state, autoRenewing, acknowledged };
  if (expiryTimeMillis !== undefined) result.expiryTimeMillis = expiryTimeMillis;
  if (state === "canceled" || state === "expired") {
    const reason = cancelReasonOf(body["canceledStateContext"]);
    if (reason !== undefined) result.cancelReason = reason;
  }
  return result;
}

/** Maps a `ProductPurchase` resource (one-time product) to the normalised result. */
export function mapProductPurchase(body: unknown, productId: string): PurchaseVerification {
  if (!isRecord(body)) return { valid: false, state: "unknown" };
  const acknowledged = body["acknowledgementState"] === 1;
  if (typeof body["productId"] === "string" && body["productId"] !== productId) {
    return { valid: false, state: "product_mismatch", acknowledged };
  }
  switch (body["purchaseState"]) {
    case 0:
      return { valid: true, state: "active", acknowledged };
    case 1:
      return { valid: false, state: "revoked", acknowledged };
    case 2:
      return { valid: false, state: "pending", acknowledged };
    default:
      return { valid: false, state: "unknown", acknowledged };
  }
}

export interface VerifyPurchaseInput {
  packageName: string;
  productId: string;
  purchaseType: PurchaseType;
  purchaseToken: string;
}

function purchaseUrl(input: VerifyPurchaseInput): string {
  const application = `${ANDROID_PUBLISHER_BASE}/applications/${encodeURIComponent(input.packageName)}`;
  const token = encodeURIComponent(input.purchaseToken);
  return input.purchaseType === "subscription"
    ? `${application}/purchases/subscriptionsv2/tokens/${token}`
    : `${application}/purchases/products/${encodeURIComponent(input.productId)}/tokens/${token}`;
}

/**
 * Verifies a purchase with the Google Play Developer API (androidpublisher v3):
 * `purchases.subscriptionsv2.get` for subscriptions and `purchases.products.get`
 * for one-time products.
 *
 * Throws `GoogleRequestError` when Google cannot give an answer (credentials
 * rejected, outage, timeout). A token that Google does not know is a normal
 * result (`valid: false`), not an error.
 */
export async function verifyPurchaseWithGoogle(
  account: ServiceAccount,
  input: VerifyPurchaseInput,
  options: GoogleCallOptions,
): Promise<PurchaseVerification> {
  const url = purchaseUrl(input);

  for (let attempt = 0; ; attempt += 1) {
    const accessToken = await getAccessToken(account, SCOPE_ANDROID_PUBLISHER, options);

    let response: Response;
    try {
      response = await options.deps.fetch(url, {
        method: "GET",
        headers: { authorization: `Bearer ${accessToken}`, accept: "application/json" },
        signal: AbortSignal.timeout(options.timeoutMs),
      });
    } catch {
      throw new GoogleRequestError("unavailable");
    }

    if (response.ok) {
      let body: unknown;
      try {
        body = await response.json();
      } catch {
        throw new GoogleRequestError("unavailable", response.status);
      }
      return input.purchaseType === "subscription"
        ? mapSubscriptionPurchase(body, input.productId, options.deps.now())
        : mapProductPurchase(body, input.productId);
    }

    await response.body?.cancel().catch(() => undefined);
    switch (response.status) {
      case 400:
      case 404:
        return { valid: false, state: "not_found" };
      case 410:
        return { valid: false, state: "expired" };
      case 401:
        // The cached access token may have been revoked: retry once with a new one.
        invalidateAccessToken(account, SCOPE_ANDROID_PUBLISHER, options.deps);
        if (attempt === 0) continue;
        throw new GoogleRequestError("credentials", 401);
      case 403:
        throw new GoogleRequestError("credentials", 403);
      default:
        throw new GoogleRequestError("unavailable", response.status);
    }
  }
}
