import { base64ToBytes } from "../util/encoding";

export interface ServiceAccount {
  clientEmail: string;
  privateKeyPem: string;
  privateKeyId: string | null;
}

let lastRaw: string | undefined;
let lastParsed: ServiceAccount | null = null;

/**
 * Parses the `GOOGLE_SERVICE_ACCOUNT_JSON` secret (the JSON key file of a
 * Google Cloud service account, raw or base64-encoded).
 *
 * Returns null when the secret is missing or unusable. It never throws and
 * never reports why, so no part of the key can leak through an error.
 */
export function parseServiceAccount(raw: string | undefined): ServiceAccount | null {
  if (raw === undefined || raw.trim() === "") return null;
  if (raw === lastRaw) return lastParsed;
  lastRaw = raw;
  lastParsed = parseUncached(raw.trim());
  return lastParsed;
}

function parseUncached(text: string): ServiceAccount | null {
  try {
    const json = text.startsWith("{") ? text : new TextDecoder().decode(base64ToBytes(text));
    const value: unknown = JSON.parse(json);
    if (typeof value !== "object" || value === null) return null;
    const record = value as Record<string, unknown>;
    const clientEmail = record["client_email"];
    const privateKey = record["private_key"];
    const privateKeyId = record["private_key_id"];
    if (typeof clientEmail !== "string" || !/^[^@\s]+@[^@\s]+$/.test(clientEmail)) return null;
    if (typeof privateKey !== "string" || !privateKey.includes("-----BEGIN PRIVATE KEY-----")) return null;
    return {
      clientEmail,
      privateKeyPem: privateKey,
      privateKeyId: typeof privateKeyId === "string" && privateKeyId !== "" ? privateKeyId : null,
    };
  } catch {
    return null;
  }
}
