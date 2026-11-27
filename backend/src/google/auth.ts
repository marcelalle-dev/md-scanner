import type { AppDeps } from "../runtime";
import { createServiceAccountAssertion, GOOGLE_TOKEN_URL } from "./jwt";
import type { ServiceAccount } from "./service-account";

export const SCOPE_ANDROID_PUBLISHER = "https://www.googleapis.com/auth/androidpublisher";
export const SCOPE_PLAY_INTEGRITY = "https://www.googleapis.com/auth/playintegrity";

/** Refresh a cached token this long before it actually expires. */
const EXPIRY_SAFETY_MARGIN_MS = 60_000;

/**
 * Failure while talking to Google. It carries only a coarse category and the
 * HTTP status: never a response body, a credential or the account identity.
 */
export class GoogleRequestError extends Error {
  constructor(
    readonly kind: "credentials" | "unavailable",
    readonly status?: number,
  ) {
    super(`google_${kind}`);
    this.name = "GoogleRequestError";
  }
}

export interface GoogleCallOptions {
  deps: AppDeps;
  timeoutMs: number;
}

function cacheKey(account: ServiceAccount, scope: string): string {
  return `${account.clientEmail}|${scope}`;
}

/**
 * Returns an OAuth 2.0 access token for the service account, using the JWT
 * bearer grant. Tokens are cached in memory until shortly before they expire.
 */
export async function getAccessToken(
  account: ServiceAccount,
  scope: string,
  options: GoogleCallOptions,
): Promise<string> {
  const { deps } = options;
  const key = cacheKey(account, scope);
  const now = deps.now();
  const cached = deps.caches.googleTokens.get(key);
  if (cached !== undefined && cached.expiresAt - EXPIRY_SAFETY_MARGIN_MS > now) return cached.token;

  let assertion: string;
  try {
    assertion = await createServiceAccountAssertion(account, scope, now, deps.caches);
  } catch {
    // Unusable private key: a configuration problem, reported without detail.
    throw new GoogleRequestError("credentials");
  }

  let response: Response;
  try {
    response = await deps.fetch(GOOGLE_TOKEN_URL, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }).toString(),
      signal: AbortSignal.timeout(options.timeoutMs),
    });
  } catch {
    throw new GoogleRequestError("unavailable");
  }

  if (!response.ok) {
    await response.body?.cancel().catch(() => undefined);
    // 400/401/403 from the token endpoint mean the key or account is rejected.
    const kind = response.status >= 500 || response.status === 429 ? "unavailable" : "credentials";
    throw new GoogleRequestError(kind, response.status);
  }

  let payload: unknown;
  try {
    payload = await response.json();
  } catch {
    throw new GoogleRequestError("unavailable", response.status);
  }
  const record = (typeof payload === "object" && payload !== null ? payload : {}) as Record<string, unknown>;
  const token = record["access_token"];
  const expiresIn = record["expires_in"];
  if (typeof token !== "string" || token === "") throw new GoogleRequestError("unavailable", response.status);

  const lifetimeSeconds = typeof expiresIn === "number" && Number.isFinite(expiresIn) && expiresIn > 0 ? expiresIn : 300;
  deps.caches.googleTokens.set(key, { token, expiresAt: now + lifetimeSeconds * 1000 });
  return token;
}

/** Forgets a cached token, for example after Google answered 401 with it. */
export function invalidateAccessToken(account: ServiceAccount, scope: string, deps: AppDeps): void {
  deps.caches.googleTokens.delete(cacheKey(account, scope));
}
