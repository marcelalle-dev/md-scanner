/**
 * Privacy-preserving structured logger.
 *
 * The logger is an allow-list: only the field names below can be written, and
 * only as finite numbers or short machine tokens (identifiers, enum values,
 * route names). Free text is rejected by construction, so document text, user
 * questions, model output, purchase tokens, API keys, install ids and IP
 * addresses cannot reach the logs even if a caller passes them by mistake.
 */

export type LogLevel = "info" | "warn" | "error";

const NUMERIC_FIELDS = [
  "status",
  "latencyMs",
  "requestBytes",
  "documentChars",
  "questionChars",
  "inputTokens",
  "outputTokens",
  "budgetUnits",
  "upstreamStatus",
  "upstreamLatencyMs",
  "retryAfterSeconds",
] as const;

const TOKEN_FIELDS = [
  "requestId",
  "method",
  "route",
  "task",
  "code",
  "reason",
  "tier",
  "outputLanguage",
  "targetLanguage",
  "purchaseType",
  "purchaseState",
  "stopReason",
  "errorName",
  "name",
  "model",
] as const;

export type NumericField = (typeof NUMERIC_FIELDS)[number];
export type TokenField = (typeof TOKEN_FIELDS)[number];
export type LogFields = { [K in NumericField]?: number | undefined } & { [K in TokenField]?: string | undefined };

const NUMERIC_SET: ReadonlySet<string> = new Set(NUMERIC_FIELDS);
const TOKEN_SET: ReadonlySet<string> = new Set(TOKEN_FIELDS);

/** Identifiers, enum values and route names only: no spaces, no punctuation that free text needs. */
const SAFE_TOKEN = /^[A-Za-z0-9_.:\/-]{1,80}$/;

export function sanitizeLogFields(fields: Readonly<Record<string, unknown>>): Record<string, string | number> {
  const safe: Record<string, string | number> = {};
  for (const [key, value] of Object.entries(fields)) {
    if (NUMERIC_SET.has(key)) {
      if (typeof value === "number" && Number.isFinite(value)) safe[key] = Math.round(value);
    } else if (TOKEN_SET.has(key)) {
      if (typeof value === "string" && SAFE_TOKEN.test(value)) safe[key] = value;
    }
  }
  return safe;
}

function write(level: LogLevel, event: string, fields: Readonly<Record<string, unknown>>): void {
  const entry = { level, event: SAFE_TOKEN.test(event) ? event : "invalid_event", ...sanitizeLogFields(fields) };
  const line = JSON.stringify(entry);
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.log(line);
}

/** Collects the fields of one request and emits a single summary line at the end. */
export class RequestLog {
  private readonly fields: Record<string, unknown> = {};

  constructor(requestId: string, method: string, route: string) {
    this.fields["requestId"] = requestId;
    this.fields["method"] = method;
    this.fields["route"] = route;
  }

  set(fields: LogFields): void {
    Object.assign(this.fields, fields);
  }

  /** Writes an intermediate event (for example an upstream failure) tied to this request. */
  event(level: LogLevel, event: string, fields: LogFields = {}): void {
    write(level, event, { requestId: this.fields["requestId"], route: this.fields["route"], ...fields });
  }

  finish(status: number, latencyMs: number): void {
    const level: LogLevel = status >= 500 ? "error" : status >= 400 ? "warn" : "info";
    write(level, "request", { ...this.fields, status, latencyMs });
  }
}

/** Returns a loggable error class name (never the message, which may echo input). */
export function safeErrorName(error: unknown): string {
  if (error instanceof Error && SAFE_TOKEN.test(error.name)) return error.name;
  return "UnknownError";
}
