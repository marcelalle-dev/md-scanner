import { ALLOWED_PACKAGE_NAME } from "../constants";
import { translateGoogleError } from "../google/errors";
import { verifyPurchaseWithGoogle, type PurchaseVerification } from "../google/play-purchases";
import { parseServiceAccount } from "../google/service-account";
import { upstreamUnavailable } from "../http/errors";
import type { RequestContext } from "../http/request-context";
import type { CachedEntitlement } from "../limiter/types";
import { sha256Hex } from "../util/encoding";
import { purchaseTypeOf, type ProductId } from "./products";

/**
 * Key under which a purchase is known to the limiter (quota subject and
 * entitlement cache). Only this digest is stored, never the purchase token.
 */
export function purchaseKeyFor(productId: ProductId, purchaseToken: string): Promise<string> {
  return sha256Hex(`purchase:${productId}:${purchaseToken}`);
}

export function toCachedEntitlement(verification: PurchaseVerification, nowMs: number): CachedEntitlement {
  const expiry = verification.expiryTimeMillis;
  return {
    premium: verification.valid,
    state: verification.state,
    expiryMs: verification.valid && expiry !== undefined && expiry > nowMs ? expiry : null,
  };
}

/** Server-side verification of a purchase with Google Play. Fails closed. */
export async function verifyEntitlement(
  rc: RequestContext,
  productId: ProductId,
  purchaseToken: string,
): Promise<PurchaseVerification> {
  const account = parseServiceAccount(rc.env.GOOGLE_SERVICE_ACCOUNT_JSON);
  if (account === null) throw upstreamUnavailable(503, "purchase_verification_not_configured");

  const purchaseType = purchaseTypeOf(productId);
  try {
    const verification = await verifyPurchaseWithGoogle(
      account,
      { packageName: ALLOWED_PACKAGE_NAME, productId, purchaseType, purchaseToken },
      { deps: rc.deps, timeoutMs: rc.config.google.timeoutMs },
    );
    rc.log.set({ purchaseType, purchaseState: verification.state });
    return verification;
  } catch (error) {
    throw translateGoogleError(error, rc.log, "purchase");
  }
}
