import { concatBytes } from "../util/encoding";
import { invalidRequest, payloadTooLarge } from "./errors";

export interface RawBody {
  bytes: Uint8Array;
  text: string;
}

export function requireJsonContentType(request: Request): void {
  const contentType = request.headers.get("content-type") ?? "";
  const mediaType = contentType.split(";", 1)[0]?.trim().toLowerCase();
  if (mediaType !== "application/json") {
    throw invalidRequest("unsupported_media_type", "Content-Type must be application/json.", undefined, 415);
  }
}

/**
 * Reads the request body with a hard byte cap. The declared Content-Length is
 * checked first, then the stream is counted while reading so that a chunked
 * or mislabelled upload cannot exceed the cap either.
 */
export async function readBody(request: Request, maxBytes: number): Promise<RawBody> {
  const declared = request.headers.get("content-length");
  if (declared !== null && /^\d+$/.test(declared) && Number(declared) > maxBytes) {
    throw payloadTooLarge("body", "bytes", maxBytes);
  }

  const stream = request.body;
  if (stream === null) throw invalidRequest("empty_body", "A JSON request body is required.");

  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel().catch(() => undefined);
      throw payloadTooLarge("body", "bytes", maxBytes);
    }
    chunks.push(value);
  }
  if (total === 0) throw invalidRequest("empty_body", "A JSON request body is required.");

  const bytes = concatBytes(...chunks);
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes);
  } catch {
    throw invalidRequest("invalid_encoding", "The request body must be valid UTF-8.");
  }
  return { bytes, text };
}

/** Parses JSON without ever surfacing the parser message (it can echo input). */
export function parseJsonObject(text: string): Record<string, unknown> {
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw invalidRequest("malformed_json", "The request body is not valid JSON.");
  }
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw invalidRequest("malformed_json", "The request body must be a JSON object.");
  }
  return value as Record<string, unknown>;
}
