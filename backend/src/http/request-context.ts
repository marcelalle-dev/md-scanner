import type { AppConfig } from "../config";
import type { Env } from "../env";
import type { RequestLog } from "../logging/logger";
import type { AppDeps } from "../runtime";

/** The part of the Workers `ExecutionContext` that handlers rely on. */
export interface BackgroundTasks {
  waitUntil(promise: Promise<unknown>): void;
}

export interface RequestContext {
  request: Request;
  env: Env;
  background: BackgroundTasks;
  config: AppConfig;
  deps: AppDeps;
  log: RequestLog;
  requestId: string;
}
