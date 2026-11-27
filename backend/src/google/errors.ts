import { ApiError, upstreamUnavailable } from "../http/errors";
import type { RequestLog } from "../logging/logger";
import { GoogleRequestError } from "./auth";

/**
 * Converts a Google failure into the public error. The client only learns
 * that verification is temporarily unavailable; the cause (rejected
 * credentials, missing permission, outage) goes to the logs as a status code.
 * Unknown errors are returned unchanged so the top-level handler reports them
 * as `internal_error`.
 */
export function translateGoogleError(error: unknown, log: RequestLog, provider: "purchase" | "integrity"): unknown {
  if (error instanceof ApiError) return error;
  if (!(error instanceof GoogleRequestError)) return error;
  const reason = `${provider}_provider_${error.kind === "credentials" ? "auth" : "unavailable"}`;
  log.event("error", "google_request_failed", { reason, upstreamStatus: error.status });
  return upstreamUnavailable(
    503,
    reason,
    error.status === undefined ? { retryAfterSeconds: 30 } : { retryAfterSeconds: 30, upstreamStatus: error.status },
  );
}
