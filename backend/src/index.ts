import { handleRequest } from "./app";
import type { Env } from "./env";

// The limiter Durable Object class must be exported from the entry module.
export { LimiterDO } from "./limiter/durable-object";

export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    return handleRequest(request, env, ctx);
  },
} satisfies ExportedHandler<Env>;
