import { isProductId, type ProductId } from "../purchases/products";
import { sha256Hex } from "../util/encoding";
import { invalidRequest, unauthorized } from "./errors";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

/** Google Play purchase tokens are opaque URL-safe strings; accept a conservative superset. */
const PURCHASE_TOKEN_PATTERN = /^[A-Za-z0-9._~+\/=:-]{8,4096}$/;

export function isPurchaseTokenShape(token: string): boolean {
  return PURCHASE_TOKEN_PATTERN.test(token);
}

/** Every install identifies itself with a random UUID generated on first launch. */
export function parseInstallId(request: Request): string {
  const header = request.headers.get("x-install-id");
  if (header === null || header.trim() === "") {
    throw unauthorized("install_id_missing", "The X-Install-Id header is required.");
  }
  const value = header.trim().toLowerCase();
  if (!UUID_PATTERN.test(value)) {
    throw unauthorized("install_id_invalid", "The X-Install-Id header must be a UUID.");
  }
  return value;
}

export interface PurchaseCredentials {
  productId: ProductId;
  purchaseToken: string;
}

/**
 * Premium credentials are optional on the AI endpoint:
 *   Authorization: Bearer <Google Play purchase token>
 *   X-Product-Id:  <product id>
 * Either both headers are present or neither.
 */
export function parsePurchaseCredentials(request: Request): PurchaseCredentials | null {
  const authorization = request.headers.get("authorization");
  const productHeader = request.headers.get("x-product-id");
  if (authorization === null && productHeader === null) return null;
  if (authorization === null || productHeader === null) {
    throw invalidRequest(
      "purchase_headers_incomplete",
      "Authorization (Bearer purchase token) and X-Product-Id must be sent together.",
    );
  }

  const match = /^Bearer[ ]+(\S+)$/i.exec(authorization.trim());
  const token = match?.[1];
  if (token === undefined || !isPurchaseTokenShape(token)) {
    throw unauthorized("purchase_token_malformed", "The Authorization header must be 'Bearer <purchase token>'.");
  }

  const productId = productHeader.trim();
  if (!isProductId(productId)) {
    throw invalidRequest("product_not_allowed", "Unknown product id.");
  }
  return { productId, purchaseToken: token };
}

/**
 * Normalises the client address used for burst limiting: IPv4 as is, IPv6
 * reduced to its /64 prefix (a single subscriber usually controls a whole /64).
 */
export function normalizeClientIp(raw: string | null): string {
  if (raw === null) return "unknown";
  const ip = raw.trim().toLowerCase();
  if (ip === "" || ip.length > 45) return "unknown";
  if (!ip.includes(":")) return ip;

  const mapped = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/.exec(ip);
  if (mapped?.[1] !== undefined) return mapped[1];

  const halves = ip.split("::");
  if (halves.length > 2) return ip;
  const head = halves[0] ? halves[0].split(":") : [];
  const tail = halves.length === 2 && halves[1] ? halves[1].split(":") : [];
  const missing = halves.length === 2 ? 8 - head.length - tail.length : 0;
  if (missing < 0) return ip;
  const groups = [...head, ...new Array<string>(missing).fill("0"), ...tail];
  if (groups.length !== 8 || groups.some((group) => !/^[0-9a-f]{1,4}$/.test(group))) return ip;
  return `${groups
    .slice(0, 4)
    .map((group) => group.replace(/^0+(?=.)/, ""))
    .join(":")}::/64`;
}

/**
 * Key stored by the limiter for burst limiting. The address itself is never
 * stored or logged: only a truncated SHA-256 digest, kept for a few minutes.
 */
export async function clientIpKey(request: Request): Promise<string> {
  const normalized = normalizeClientIp(request.headers.get("cf-connecting-ip"));
  return (await sha256Hex(`ip:${normalized}`)).slice(0, 32);
}
