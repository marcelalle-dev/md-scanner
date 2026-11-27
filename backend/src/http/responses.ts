import type { ApiError } from "./errors";

/**
 * Headers applied to every response.
 * CORS is closed on purpose: the only client is a native mobile app, so no
 * `Access-Control-*` header is ever emitted and browsers cannot read the API.
 */
const BASE_HEADERS: Readonly<Record<string, string>> = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
  "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
};

export function jsonResponse(
  status: number,
  body: unknown,
  requestId: string,
  extraHeaders: Readonly<Record<string, string>> = {},
): Response {
  const headers = new Headers(BASE_HEADERS);
  headers.set("X-Request-Id", requestId);
  for (const [name, value] of Object.entries(extraHeaders)) headers.set(name, value);
  return new Response(JSON.stringify(body), { status, headers });
}

export interface ErrorBody {
  error: {
    code: string;
    message: string;
    requestId: string;
    reason?: string;
    retryAfterSeconds?: number;
    details?: unknown;
  };
}

export function errorResponse(error: ApiError, requestId: string): Response {
  const body: ErrorBody = {
    error: { code: error.code, message: error.message, requestId },
  };
  if (error.reason !== undefined) body.error.reason = error.reason;
  if (error.retryAfterSeconds !== undefined) body.error.retryAfterSeconds = error.retryAfterSeconds;
  if (error.details !== undefined) body.error.details = error.details;

  const headers: Record<string, string> = { ...error.headers };
  if (error.retryAfterSeconds !== undefined) headers["Retry-After"] = String(error.retryAfterSeconds);
  return jsonResponse(error.status, body, requestId, headers);
}
