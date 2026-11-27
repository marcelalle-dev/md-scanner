/**
 * Machine-readable error codes of the public API. The mobile client branches
 * on `code` (and optionally on the finer `reason`); `message` is a fixed
 * English sentence for developers and never contains request content.
 */
export type ErrorCode =
  | "invalid_request"
  | "payload_too_large"
  | "unauthorized"
  | "premium_required"
  | "quota_exceeded"
  | "rate_limited"
  | "upstream_unavailable"
  | "internal_error"
  | "not_found"
  | "method_not_allowed";

/** Only numbers, booleans, null and short machine tokens: never free text from a request. */
export type ErrorDetailValue = string | number | boolean | null | ReadonlyArray<{ path: string; code: string }>;
export type ErrorDetails = Readonly<Record<string, ErrorDetailValue>>;

export interface ApiErrorOptions {
  reason?: string;
  retryAfterSeconds?: number;
  details?: ErrorDetails;
  headers?: Readonly<Record<string, string>>;
  /** HTTP status returned by an upstream provider, for logs only. */
  upstreamStatus?: number;
}

export class ApiError extends Error {
  readonly status: number;
  readonly code: ErrorCode;
  readonly reason: string | undefined;
  readonly retryAfterSeconds: number | undefined;
  readonly details: ErrorDetails | undefined;
  readonly headers: Readonly<Record<string, string>>;
  readonly upstreamStatus: number | undefined;

  constructor(status: number, code: ErrorCode, message: string, options: ApiErrorOptions = {}) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.reason = options.reason;
    this.retryAfterSeconds =
      options.retryAfterSeconds === undefined ? undefined : clampRetryAfter(options.retryAfterSeconds);
    this.details = options.details;
    this.headers = options.headers ?? {};
    this.upstreamStatus = options.upstreamStatus;
  }
}

const MAX_RETRY_AFTER_SECONDS = 32 * 24 * 3600;

function clampRetryAfter(seconds: number): number {
  if (!Number.isFinite(seconds)) return 1;
  return Math.min(MAX_RETRY_AFTER_SECONDS, Math.max(1, Math.ceil(seconds)));
}

export function invalidRequest(reason: string, message: string, details?: ErrorDetails, status = 400): ApiError {
  return new ApiError(status, "invalid_request", message, details ? { reason, details } : { reason });
}

export function payloadTooLarge(field: string, unit: "bytes" | "chars", limit: number, actual?: number): ApiError {
  const details: Record<string, ErrorDetailValue> = { field, unit, limit };
  if (actual !== undefined) details["actual"] = actual;
  return new ApiError(413, "payload_too_large", `The ${field} exceeds the maximum accepted size.`, {
    reason: `${field}_too_large`,
    details,
  });
}

export function unauthorized(reason: string, message: string): ApiError {
  return new ApiError(401, "unauthorized", message, { reason });
}

export function premiumRequired(purchaseState: string | null): ApiError {
  return new ApiError(403, "premium_required", "An active premium purchase is required to use the AI assistant.", {
    reason: purchaseState === null ? "no_purchase" : "purchase_not_active",
    details: { purchaseState },
  });
}

export function quotaExceeded(reason: string, retryAfterSeconds: number, details: ErrorDetails): ApiError {
  return new ApiError(429, "quota_exceeded", "The usage quota is exhausted for the current period.", {
    reason,
    retryAfterSeconds,
    details,
  });
}

export function rateLimited(retryAfterSeconds: number): ApiError {
  return new ApiError(429, "rate_limited", "Too many requests. Slow down and retry later.", {
    reason: "ip_burst",
    retryAfterSeconds,
  });
}

export function upstreamUnavailable(
  status: 502 | 503 | 504,
  reason: string,
  options: { retryAfterSeconds?: number; upstreamStatus?: number } = {},
): ApiError {
  return new ApiError(status, "upstream_unavailable", "The service is temporarily unable to process this request.", {
    reason,
    ...options,
  });
}

export function internalError(reason = "unexpected", status: 500 | 503 = 500, retryAfterSeconds?: number): ApiError {
  return new ApiError(
    status,
    "internal_error",
    "Unexpected server error.",
    retryAfterSeconds === undefined ? { reason } : { reason, retryAfterSeconds },
  );
}

export function notFound(): ApiError {
  return new ApiError(404, "not_found", "Unknown endpoint.", { reason: "unknown_route" });
}

export function methodNotAllowed(allow: string): ApiError {
  return new ApiError(405, "method_not_allowed", "HTTP method not allowed for this endpoint.", {
    reason: "method_not_allowed",
    headers: { Allow: allow },
  });
}
