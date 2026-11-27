import { z } from "zod";
import { TASK_NAMES, type AppConfig, type TaskName } from "../config";
import { BUDGET_WEIGHTS } from "../constants";
import { parseJsonObject } from "../http/body";
import { invalidRequest, payloadTooLarge } from "../http/errors";
import {
  OUTPUT_LANGUAGE_CODES,
  TARGET_LANGUAGE_CODES,
  type OutputLanguage,
  type TargetLanguage,
} from "./languages";

export interface AiTaskRequest {
  task: TaskName;
  outputLanguage: OutputLanguage;
  documentText: string;
  /** Present only for `qa`. */
  question?: string;
  /** Present only for `translate`. */
  targetLanguage?: TargetLanguage;
}

const requestSchema = z.strictObject({
  task: z.enum(TASK_NAMES),
  outputLanguage: z.enum(OUTPUT_LANGUAGE_CODES),
  documentText: z.string(),
  question: z.string().optional(),
  targetLanguage: z.enum(TARGET_LANGUAGE_CODES).optional(),
});

const SAFE_PATH = /^[A-Za-z0-9_.]{1,64}$/;

/** Validation issues as `{ path, code }` pairs: field names and issue codes only, never values. */
export function describeIssues(error: z.ZodError): Array<{ path: string; code: string }> {
  return error.issues.slice(0, 10).map((issue) => {
    const path = issue.path.map(String).join(".");
    return { path: SAFE_PATH.test(path) ? path : "body", code: String(issue.code) };
  });
}

/**
 * Parses and validates the body of `POST /v1/ai/tasks`.
 *
 * Long documents are handled deliberately: there is a hard, per-task cap on
 * `documentText` and the request is rejected with `payload_too_large` (limit
 * and actual size in `details`) instead of being silently truncated. The
 * client is expected to split long documents (see README).
 */
export function parseAiTaskRequest(bodyText: string, config: AppConfig): AiTaskRequest {
  const parsed = requestSchema.safeParse(parseJsonObject(bodyText));
  if (!parsed.success) {
    throw invalidRequest("validation_failed", "The request body does not match the expected schema.", {
      issues: describeIssues(parsed.error),
    });
  }
  const { task, outputLanguage, documentText, question, targetLanguage } = parsed.data;

  if (documentText.trim() === "") {
    throw invalidRequest("document_empty", "documentText must contain text.", {
      issues: [{ path: "documentText", code: "too_small" }],
    });
  }
  const maxDocumentChars = maxDocumentCharsFor(task, config);
  if (documentText.length > maxDocumentChars) {
    throw payloadTooLarge("documentText", "chars", maxDocumentChars, documentText.length);
  }

  const request: AiTaskRequest = { task, outputLanguage, documentText };

  if (task === "qa") {
    const trimmed = question?.trim() ?? "";
    if (trimmed === "") {
      throw invalidRequest("question_required", "question is required when task is 'qa'.", {
        issues: [{ path: "question", code: "required" }],
      });
    }
    if (trimmed.length > config.limits.maxQuestionChars) {
      throw payloadTooLarge("question", "chars", config.limits.maxQuestionChars, trimmed.length);
    }
    request.question = trimmed;
  } else if (question !== undefined) {
    throw invalidRequest("question_not_allowed", "question is only accepted when task is 'qa'.", {
      issues: [{ path: "question", code: "not_allowed" }],
    });
  }

  if (task === "translate") {
    if (targetLanguage === undefined) {
      throw invalidRequest("target_language_required", "targetLanguage is required when task is 'translate'.", {
        issues: [{ path: "targetLanguage", code: "required" }],
      });
    }
    request.targetLanguage = targetLanguage;
  } else if (targetLanguage !== undefined) {
    throw invalidRequest("target_language_not_allowed", "targetLanguage is only accepted when task is 'translate'.", {
      issues: [{ path: "targetLanguage", code: "not_allowed" }],
    });
  }

  return request;
}

/** Hard input cap, in UTF-16 code units (`String.length` in Dart and JavaScript). */
export function maxDocumentCharsFor(task: TaskName, config: AppConfig): number {
  // A translation is as long as its source, so its input cap follows the
  // output budget instead of the general document cap.
  return task === "translate"
    ? Math.min(config.limits.maxTranslateChars, config.limits.maxDocumentChars)
    : config.limits.maxDocumentChars;
}

/** Fixed prompt overhead (system prompt, schema instructions, wrappers), in tokens. */
const PROMPT_OVERHEAD_TOKENS = 1_500;

/**
 * Worst-case budget units of a request, reserved before the model is called.
 * Input is estimated from the body size (about 3 bytes per token is a
 * conservative ratio for European languages) and priced as a cache write;
 * output is assumed to use the whole `max_tokens`.
 */
export function estimateReserveUnits(requestBytes: number, maxOutputTokens: number): number {
  const inputTokens = Math.ceil(requestBytes / 3) + PROMPT_OVERHEAD_TOKENS;
  return Math.ceil(inputTokens * BUDGET_WEIGHTS.cacheWrite + maxOutputTokens * BUDGET_WEIGHTS.output);
}
