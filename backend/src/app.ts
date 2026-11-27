import { handleAiTask } from "./ai/handler";
import { loadConfig } from "./config";
import { ROUTES } from "./constants";
import type { Env } from "./env";
import { handleHealth } from "./health/handler";
import { ApiError, internalError, methodNotAllowed, notFound } from "./http/errors";
import type { BackgroundTasks, RequestContext } from "./http/request-context";
import { errorResponse } from "./http/responses";
import { RequestLog, safeErrorName } from "./logging/logger";
import { handlePurchaseVerify } from "./purchases/handler";
import { defaultDeps, type AppDeps } from "./runtime";

interface Route {
  method: "GET" | "POST";
  handle: (rc: RequestContext) => Response | Promise<Response>;
}

const ROUTE_TABLE: Readonly<Record<string, Route>> = {
  [ROUTES.health]: { method: "GET", handle: handleHealth },
  [ROUTES.aiTasks]: { method: "POST", handle: handleAiTask },
  [ROUTES.purchasesVerify]: { method: "POST", handle: handlePurchaseVerify },
};

const KNOWN_METHODS: ReadonlySet<string> = new Set(["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]);

/**
 * Entry point of the application, independent from the Workers entry module
 * so it can run under test with injected dependencies.
 *
 * Every request gets a request id, exactly one structured log line (ids,
 * sizes, status and latency only) and a JSON response. Errors never carry
 * request content: unexpected exceptions are reduced to `internal_error` and
 * only their class name is logged.
 */
export async function handleRequest(
  request: Request,
  env: Env,
  background: BackgroundTasks,
  deps: AppDeps = defaultDeps,
): Promise<Response> {
  const startedAt = Date.now();
  const requestId = crypto.randomUUID();
  const pathname = new URL(request.url).pathname;
  const route = Object.hasOwn(ROUTE_TABLE, pathname) ? ROUTE_TABLE[pathname] : undefined;
  const log = new RequestLog(
    requestId,
    KNOWN_METHODS.has(request.method) ? request.method : "OTHER",
    route === undefined ? "unmatched" : pathname,
  );

  let response: Response;
  try {
    if (route === undefined) throw notFound();
    // No CORS: OPTIONS (preflight) is answered like any other unsupported method.
    if (request.method !== route.method) throw methodNotAllowed(route.method);

    const { config, invalid } = loadConfig(env);
    for (const name of invalid) log.event("warn", "config_invalid", { name });

    response = await route.handle({ request, env, background, config, deps, log, requestId });
  } catch (error) {
    let apiError: ApiError;
    if (error instanceof ApiError) {
      apiError = error;
    } else {
      log.set({ errorName: safeErrorName(error) });
      apiError = internalError();
    }
    log.set({
      code: apiError.code,
      reason: apiError.reason,
      retryAfterSeconds: apiError.retryAfterSeconds,
      upstreamStatus: apiError.upstreamStatus,
    });
    response = errorResponse(apiError, requestId);
  }

  log.finish(response.status, Date.now() - startedAt);
  return response;
}
