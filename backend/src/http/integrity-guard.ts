import { ALLOWED_PACKAGE_NAME } from "../constants";
import { translateGoogleError } from "../google/errors";
import { verifyIntegrityToken, type IntegrityResult } from "../google/play-integrity";
import { parseServiceAccount } from "../google/service-account";
import { concatBytes, sha256Hex, utf8Bytes } from "../util/encoding";
import { unauthorized, upstreamUnavailable } from "./errors";
import type { RequestContext } from "./request-context";

const INTEGRITY_TOKEN_PATTERN = /^[A-Za-z0-9._~+\/=-]{16,16384}$/;

/**
 * Value the app must pass as `requestHash` when it requests a standard Play
 * Integrity token: lowercase hex SHA-256 of `installId + "\n" + raw body`.
 * It binds the token to this install and to this exact request body.
 */
export function integrityRequestHash(installId: string, bodyBytes: Uint8Array): Promise<string> {
  return sha256Hex(concatBytes(utf8Bytes(`${installId}\n`), bodyBytes));
}

/**
 * Optional attestation step, active only when `PLAY_INTEGRITY_MODE=enforce`.
 * When active, a request without a valid verdict from Google is rejected.
 */
export async function enforcePlayIntegrity(rc: RequestContext, installId: string, bodyBytes: Uint8Array): Promise<void> {
  if (rc.config.integrity.mode !== "enforce") return;

  const token = rc.request.headers.get("x-play-integrity-token")?.trim() ?? "";
  if (token === "") {
    throw unauthorized("integrity_token_missing", "The X-Play-Integrity-Token header is required.");
  }
  if (!INTEGRITY_TOKEN_PATTERN.test(token)) {
    throw unauthorized("integrity_token_malformed", "The X-Play-Integrity-Token header is malformed.");
  }

  const account = parseServiceAccount(rc.env.GOOGLE_SERVICE_ACCOUNT_JSON);
  if (account === null) throw upstreamUnavailable(503, "integrity_not_configured");

  let result: IntegrityResult;
  try {
    result = await verifyIntegrityToken(
      account,
      {
        packageName: ALLOWED_PACKAGE_NAME,
        integrityToken: token,
        expectedRequestHash: await integrityRequestHash(installId, bodyBytes),
        maxAgeSeconds: rc.config.integrity.maxAgeSeconds,
      },
      { deps: rc.deps, timeoutMs: rc.config.google.timeoutMs },
    );
  } catch (error) {
    throw translateGoogleError(error, rc.log, "integrity");
  }
  if (!result.ok) {
    throw unauthorized(`integrity_${result.failure}`, "The app integrity check failed.");
  }
}
