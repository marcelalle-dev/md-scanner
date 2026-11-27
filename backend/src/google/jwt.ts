import type { RuntimeCaches } from "../runtime";
import { base64ToBytes, bytesToBase64Url, stringToBase64Url, utf8Bytes } from "../util/encoding";
import type { ServiceAccount } from "./service-account";

export const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";

/** Lifetime requested for the assertion; Google caps access tokens at one hour. */
const ASSERTION_LIFETIME_SECONDS = 3600;

const RS256 = { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" } as const;

/** Converts a PKCS#8 PEM private key (the format of Google key files) to DER bytes. */
export function pemToDer(pem: string): Uint8Array {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  return base64ToBytes(base64);
}

export async function importSigningKey(pem: string, caches: RuntimeCaches): Promise<CryptoKey> {
  const cached = caches.signingKeys.get(pem);
  if (cached !== undefined) return cached;
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(pem), RS256, false, ["sign"]);
  caches.signingKeys.set(pem, key);
  return key;
}

/** Signs a compact JWS with RS256 (RSASSA-PKCS1-v1_5 + SHA-256) using WebCrypto. */
export async function signJwtRs256(
  header: Readonly<Record<string, unknown>>,
  claims: Readonly<Record<string, unknown>>,
  key: CryptoKey,
): Promise<string> {
  const signingInput = `${stringToBase64Url(JSON.stringify(header))}.${stringToBase64Url(JSON.stringify(claims))}`;
  const signature = await crypto.subtle.sign(RS256.name, key, utf8Bytes(signingInput));
  return `${signingInput}.${bytesToBase64Url(new Uint8Array(signature))}`;
}

/**
 * Builds the signed assertion of the OAuth 2.0 JWT bearer flow for service
 * accounts (RFC 7523): `iss` = service account, `aud` = Google token endpoint.
 */
export async function createServiceAccountAssertion(
  account: ServiceAccount,
  scope: string,
  nowMs: number,
  caches: RuntimeCaches,
): Promise<string> {
  const issuedAt = Math.floor(nowMs / 1000);
  const header: Record<string, unknown> = { alg: "RS256", typ: "JWT" };
  if (account.privateKeyId !== null) header["kid"] = account.privateKeyId;
  const claims = {
    iss: account.clientEmail,
    scope,
    aud: GOOGLE_TOKEN_URL,
    iat: issuedAt,
    exp: issuedAt + ASSERTION_LIFETIME_SECONDS,
  };
  const key = await importSigningKey(account.privateKeyPem, caches);
  return signJwtRs256(header, claims, key);
}
