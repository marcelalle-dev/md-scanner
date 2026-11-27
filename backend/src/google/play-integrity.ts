import {
  getAccessToken,
  GoogleRequestError,
  invalidateAccessToken,
  SCOPE_PLAY_INTEGRITY,
  type GoogleCallOptions,
} from "./auth";
import type { ServiceAccount } from "./service-account";

/**
 * Optional app attestation with the Play Integrity API (standard requests).
 * Disabled unless `PLAY_INTEGRITY_MODE=enforce`.
 *
 * The integrity token is decrypted and verified by Google's servers
 * (`decodeIntegrityToken`); this module only applies the acceptance policy to
 * the verdict that Google returns. Nothing is verified locally and nothing is
 * accepted without Google's answer.
 */

export type IntegrityFailure =
  | "token_rejected"
  | "package_mismatch"
  | "request_hash_mismatch"
  | "stale"
  | "app_not_recognized"
  | "device_not_trusted";

export type IntegrityResult = { ok: true } | { ok: false; failure: IntegrityFailure };

export interface IntegrityCheckInput {
  packageName: string;
  integrityToken: string;
  /** Hash the app must have passed as `requestHash` for this exact request. */
  expectedRequestHash: string;
  maxAgeSeconds: number;
}

/** Tolerated clock difference when the token timestamp is slightly in the future. */
const FUTURE_SKEW_MS = 60_000;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Acceptance policy applied to the decoded verdict:
 *  - the token was issued for this app package and for this exact request,
 *  - it is recent,
 *  - the binary is the one distributed by Google Play (`PLAY_RECOGNIZED`),
 *  - the device passes `MEETS_DEVICE_INTEGRITY`.
 * A token that Google has already decoded several times comes back with
 * cleared verdicts and is therefore rejected (replay protection).
 */
export function evaluateIntegrityPayload(payload: unknown, input: IntegrityCheckInput, nowMs: number): IntegrityResult {
  const external = isRecord(payload) ? payload["tokenPayloadExternal"] : undefined;
  if (!isRecord(external)) return { ok: false, failure: "token_rejected" };

  const requestDetails = external["requestDetails"];
  if (!isRecord(requestDetails)) return { ok: false, failure: "token_rejected" };
  if (requestDetails["requestPackageName"] !== input.packageName) return { ok: false, failure: "package_mismatch" };
  if (requestDetails["requestHash"] !== input.expectedRequestHash) {
    return { ok: false, failure: "request_hash_mismatch" };
  }

  const timestamp = Number(requestDetails["timestampMillis"]);
  if (!Number.isFinite(timestamp)) return { ok: false, failure: "stale" };
  if (nowMs - timestamp > input.maxAgeSeconds * 1000 || timestamp - nowMs > FUTURE_SKEW_MS) {
    return { ok: false, failure: "stale" };
  }

  const appIntegrity = external["appIntegrity"];
  if (!isRecord(appIntegrity) || appIntegrity["appRecognitionVerdict"] !== "PLAY_RECOGNIZED") {
    return { ok: false, failure: "app_not_recognized" };
  }

  const deviceIntegrity = external["deviceIntegrity"];
  const verdicts = isRecord(deviceIntegrity) ? deviceIntegrity["deviceRecognitionVerdict"] : undefined;
  if (!Array.isArray(verdicts) || !verdicts.includes("MEETS_DEVICE_INTEGRITY")) {
    return { ok: false, failure: "device_not_trusted" };
  }
  return { ok: true };
}

/** Asks Google to decode the integrity token, then applies the policy above. */
export async function verifyIntegrityToken(
  account: ServiceAccount,
  input: IntegrityCheckInput,
  options: GoogleCallOptions,
): Promise<IntegrityResult> {
  const url = `https://playintegrity.googleapis.com/v1/${encodeURIComponent(input.packageName)}:decodeIntegrityToken`;

  for (let attempt = 0; ; attempt += 1) {
    const accessToken = await getAccessToken(account, SCOPE_PLAY_INTEGRITY, options);

    let response: Response;
    try {
      response = await options.deps.fetch(url, {
        method: "POST",
        headers: {
          authorization: `Bearer ${accessToken}`,
          "content-type": "application/json",
          accept: "application/json",
        },
        body: JSON.stringify({ integrity_token: input.integrityToken }),
        signal: AbortSignal.timeout(options.timeoutMs),
      });
    } catch {
      throw new GoogleRequestError("unavailable");
    }

    if (response.ok) {
      let payload: unknown;
      try {
        payload = await response.json();
      } catch {
        throw new GoogleRequestError("unavailable", response.status);
      }
      return evaluateIntegrityPayload(payload, input, options.deps.now());
    }

    await response.body?.cancel().catch(() => undefined);
    switch (response.status) {
      case 400:
        return { ok: false, failure: "token_rejected" };
      case 401:
        invalidateAccessToken(account, SCOPE_PLAY_INTEGRITY, options.deps);
        if (attempt === 0) continue;
        throw new GoogleRequestError("credentials", 401);
      case 403:
        throw new GoogleRequestError("credentials", 403);
      default:
        throw new GoogleRequestError("unavailable", response.status);
    }
  }
}
