import { z } from "zod";
import { describeIssues } from "../ai/request";
import { ALLOWED_PACKAGE_NAME, PURCHASE_BODY_MAX_BYTES } from "../constants";
import type { PurchaseVerification } from "../google/play-purchases";
import { parseJsonObject, readBody, requireJsonContentType } from "../http/body";
import { invalidRequest, rateLimited } from "../http/errors";
import { clientIpKey, isPurchaseTokenShape, parseInstallId } from "../http/identity";
import { enforcePlayIntegrity } from "../http/integrity-guard";
import type { RequestContext } from "../http/request-context";
import { jsonResponse } from "../http/responses";
import { getLimiter } from "../limiter/client";
import { safeErrorName } from "../logging/logger";
import { purchaseKeyFor, toCachedEntitlement, verifyEntitlement } from "./entitlement";
import { isProductId, purchaseTypeOf } from "./products";

const requestSchema = z.strictObject({
  packageName: z.string(),
  productId: z.string(),
  purchaseToken: z.string(),
  type: z.enum(["subscription", "product"]),
});

/**
 * POST /v1/purchases/verify
 *
 * Verifies a Google Play purchase server-side and returns its normalised
 * state. The package name and the product id are checked against closed
 * lists before anything is sent to Google. Verification is read-only: the app
 * remains responsible for acknowledging the purchase.
 */
export async function handlePurchaseVerify(rc: RequestContext): Promise<Response> {
  const { request, env, config, deps, log } = rc;

  requireJsonContentType(request);
  const installId = parseInstallId(request);
  const body = await readBody(request, PURCHASE_BODY_MAX_BYTES);
  log.set({ requestBytes: body.bytes.byteLength });

  const parsed = requestSchema.safeParse(parseJsonObject(body.text));
  if (!parsed.success) {
    throw invalidRequest("validation_failed", "The request body does not match the expected schema.", {
      issues: describeIssues(parsed.error),
    });
  }
  const { packageName, productId, purchaseToken, type } = parsed.data;

  if (packageName !== ALLOWED_PACKAGE_NAME) {
    throw invalidRequest("package_not_allowed", "This package name is not served by this backend.", {
      issues: [{ path: "packageName", code: "not_allowed" }],
    });
  }
  if (!isProductId(productId)) {
    throw invalidRequest("product_not_allowed", "Unknown product id.", {
      issues: [{ path: "productId", code: "not_allowed" }],
    });
  }
  if (purchaseTypeOf(productId) !== type) {
    throw invalidRequest("purchase_type_mismatch", "The purchase type does not match the product.", {
      issues: [{ path: "type", code: "mismatch" }],
    });
  }
  if (!isPurchaseTokenShape(purchaseToken)) {
    throw invalidRequest("purchase_token_malformed", "purchaseToken is malformed.", {
      issues: [{ path: "purchaseToken", code: "invalid_format" }],
    });
  }
  log.set({ purchaseType: type });

  const limiter = getLimiter(env);
  const now = deps.now();
  const burst = await limiter.rateLimit({
    now,
    bucket: "verify",
    ipKey: await clientIpKey(request),
    limit: config.rateLimit.verifyMax,
    windowSeconds: config.rateLimit.windowSeconds,
  });
  if (!burst.allowed) throw rateLimited(burst.retryAfterSeconds);

  await enforcePlayIntegrity(rc, installId, body.bytes);

  const verification = await verifyEntitlement(rc, productId, purchaseToken);

  // Refresh the entitlement cache used by the AI endpoint, without delaying the response.
  rc.background.waitUntil(
    purchaseKeyFor(productId, purchaseToken)
      .then((purchaseKey) =>
        limiter.putEntitlement({
          now,
          purchaseKey,
          entitlement: toCachedEntitlement(verification, now),
          positiveTtlSeconds: config.google.entitlementCacheSeconds,
          negativeTtlSeconds: config.google.entitlementNegativeCacheSeconds,
        }),
      )
      .catch((error: unknown) => {
        log.event("warn", "entitlement_cache_failed", { errorName: safeErrorName(error) });
      }),
  );

  return jsonResponse(200, toResponseBody(verification), rc.requestId);
}

function toResponseBody(verification: PurchaseVerification): PurchaseVerification {
  const body: PurchaseVerification = { valid: verification.valid, state: verification.state };
  if (verification.expiryTimeMillis !== undefined) body.expiryTimeMillis = verification.expiryTimeMillis;
  if (verification.autoRenewing !== undefined) body.autoRenewing = verification.autoRenewing;
  if (verification.acknowledged !== undefined) body.acknowledged = verification.acknowledged;
  if (verification.cancelReason !== undefined) body.cancelReason = verification.cancelReason;
  return body;
}
