import { DatabaseSync } from "node:sqlite";
import { handleRequest } from "../../src/app";
import type { Env } from "../../src/env";
import { LimiterCore, type SqlDriver, type SqlValue } from "../../src/limiter/core";
import type { LimiterApi } from "../../src/limiter/types";
import { createRuntimeCaches, type AppDeps, type FetchLike } from "../../src/runtime";

export const INSTALL_ID = "3f2b8c1e-7a4d-4e9b-9c0f-5d6a7b8c9d0e";
export const OTHER_INSTALL_ID = "9a1c2d3e-4f50-4a6b-8c7d-0e1f2a3b4c5d";
export const CLIENT_IP = "203.0.113.57";
export const API_KEY = "sk-ant-test-TOPSECRETKEY-000111222";
export const PURCHASE_TOKEN = "kfaoeidjmlpnchbgkhdfabcd.AO-J1OxPURCHASETOKEN_SECRET_0123456789";
export const SERVICE_ACCOUNT_EMAIL = "play-verifier@md-scanner-test.iam.gserviceaccount.com";
export const GOOGLE_ACCESS_TOKEN = "ya29.TEST-GOOGLE-ACCESS-TOKEN";

/** 2026-11-27T10:00:00Z */
export const T0 = Date.UTC(2026, 10, 27, 10, 0, 0);
export const MINUTE = 60_000;
export const HOUR = 3_600_000;
export const DAY = 86_400_000;

export class TestClock {
  constructor(public ms: number = T0) {}
  readonly now = (): number => this.ms;
  advance(ms: number): void {
    this.ms += ms;
  }
}

/** Real SQLite (in memory) behind the limiter, so the SQL is actually executed. */
export function createSqliteDriver(): SqlDriver {
  const db = new DatabaseSync(":memory:");
  return {
    exec(query: string, ...bindings: SqlValue[]) {
      return db.prepare(query).all(...bindings) as Record<string, unknown>[];
    },
    transaction<T>(fn: () => T): T {
      db.exec("BEGIN");
      try {
        const result = fn();
        db.exec("COMMIT");
        return result;
      } catch (error) {
        db.exec("ROLLBACK");
        throw error;
      }
    },
  };
}

export interface FakeLimiter {
  namespace: Env["LIMITER"];
  core: LimiterCore;
  calls: string[];
  /** When true, every limiter call fails, like an unreachable Durable Object. */
  broken: boolean;
}

/** Stands in for the Durable Object namespace; arguments cross a structured-clone boundary like RPC. */
export function createFakeLimiter(): FakeLimiter {
  const core = new LimiterCore(createSqliteDriver());
  const state: FakeLimiter = { namespace: undefined as unknown as Env["LIMITER"], core, calls: [], broken: false };
  const through = <I, O>(name: string, run: (input: I) => O) => {
    return async (input: I): Promise<O> => {
      state.calls.push(name);
      if (state.broken) throw new Error("Durable Object unavailable");
      return structuredClone(run(structuredClone(input)));
    };
  };
  const stub: LimiterApi = {
    rateLimit: through("rateLimit", (input) => core.rateLimit(input)),
    admit: through("admit", (input) => core.admit(input)),
    settle: through("settle", (input) => core.settle(input)),
    putEntitlement: through("putEntitlement", (input) => core.putEntitlement(input)),
  };
  state.namespace = {
    idFromName: (name: string) => ({ name }),
    get: () => stub,
  } as unknown as Env["LIMITER"];
  return state;
}

export interface RecordedCall {
  url: URL;
  method: string;
  headers: Headers;
  body: string;
}

type Responder = (call: RecordedCall, signal: AbortSignal | undefined) => Response | Promise<Response>;

/** Routes outbound requests by host. Any unexpected host fails the test: nothing reaches the network. */
export class FetchMock {
  readonly calls: RecordedCall[] = [];
  private readonly routes = new Map<string, Responder>();

  on(host: string, responder: Responder): this {
    this.routes.set(host, responder);
    return this;
  }

  callsTo(host: string): RecordedCall[] {
    return this.calls.filter((call) => call.url.host === host);
  }

  readonly fetch: FetchLike = async (input, init) => {
    const request = new Request(input as string, init);
    const call: RecordedCall = {
      url: new URL(request.url),
      method: request.method,
      headers: request.headers,
      body: request.body === null ? "" : await request.text(),
    };
    this.calls.push(call);
    const responder = this.routes.get(call.url.host);
    if (responder === undefined) throw new Error(`Unexpected outbound request to ${call.url.host}`);
    return responder(call, init?.signal ?? undefined);
  };
}

export const ANTHROPIC_HOST = "api.anthropic.com";
export const GOOGLE_OAUTH_HOST = "oauth2.googleapis.com";
export const PLAY_API_HOST = "androidpublisher.googleapis.com";
export const PLAY_INTEGRITY_HOST = "playintegrity.googleapis.com";

export function jsonReply(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

export interface FakeUsage {
  input_tokens?: number;
  output_tokens?: number;
  cache_creation_input_tokens?: number;
  cache_read_input_tokens?: number;
  iterations?: unknown[] | null;
}

/** A Messages API response whose text block carries `payload` (JSON-encoded unless it is a string). */
export function anthropicMessage(
  payload: unknown,
  options: { stopReason?: string; usage?: FakeUsage; withThinking?: boolean } = {},
): Response {
  const text = typeof payload === "string" ? payload : JSON.stringify(payload);
  const content: unknown[] = [];
  if (options.withThinking !== false) content.push({ type: "thinking", thinking: "", signature: "sig_test" });
  if (options.stopReason !== "refusal") content.push({ type: "text", text });
  return jsonReply(
    200,
    {
      id: "msg_test_1",
      type: "message",
      role: "assistant",
      model: "claude-opus-5-5",
      content,
      stop_reason: options.stopReason ?? "end_turn",
      stop_sequence: null,
      usage: {
        input_tokens: 1000,
        output_tokens: 200,
        cache_creation_input_tokens: 0,
        cache_read_input_tokens: 0,
        iterations: null,
        ...options.usage,
      },
    },
    { "request-id": "req_test_1" },
  );
}

export function anthropicError(status: number, type: string, headers: Record<string, string> = {}, message = "error"): Response {
  return jsonReply(status, { type: "error", error: { type, message } }, { "request-id": "req_test_err", ...headers });
}

export function googleTokenReply(expiresIn = 3600): Response {
  return jsonReply(200, { access_token: GOOGLE_ACCESS_TOKEN, expires_in: expiresIn, token_type: "Bearer" });
}

let keyMaterial: Promise<{ privateKeyPem: string; publicKey: CryptoKey }> | undefined;

/** RSA key generated for the test run; nothing here is a real credential. */
export function testKey(): Promise<{ privateKeyPem: string; publicKey: CryptoKey }> {
  keyMaterial ??= (async () => {
    const pair = (await crypto.subtle.generateKey(
      { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
      true,
      ["sign", "verify"],
    )) as CryptoKeyPair;
    const pkcs8 = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
    const base64 = Buffer.from(pkcs8).toString("base64");
    const lines = base64.match(/.{1,64}/g) ?? [];
    const privateKeyPem = `-----BEGIN PRIVATE KEY-----\n${lines.join("\n")}\n-----END PRIVATE KEY-----\n`;
    return { privateKeyPem, publicKey: pair.publicKey };
  })();
  return keyMaterial;
}

export async function serviceAccountJson(): Promise<string> {
  const { privateKeyPem } = await testKey();
  return JSON.stringify({
    type: "service_account",
    project_id: "md-scanner-test",
    private_key_id: "test-key-id-1",
    private_key: privateKeyPem,
    client_email: SERVICE_ACCOUNT_EMAIL,
    token_uri: "https://oauth2.googleapis.com/token",
  });
}

export interface TestRequestOptions {
  headers?: Record<string, string>;
  /** JSON-encoded when it is not a string. */
  body?: unknown;
  ip?: string | null;
  installId?: string | null;
}

export interface TestApp {
  env: Env;
  clock: TestClock;
  fetchMock: FetchMock;
  limiter: FakeLimiter;
  deps: AppDeps;
  background: { pending: Promise<unknown>[]; waitUntil(promise: Promise<unknown>): void };
  request(method: string, path: string, options?: TestRequestOptions): Promise<Response>;
  flush(): Promise<void>;
}

export async function createTestApp(vars: Partial<Record<keyof Env, string | undefined>> = {}): Promise<TestApp> {
  const clock = new TestClock();
  const fetchMock = new FetchMock();
  const limiter = createFakeLimiter();
  const env = {
    LIMITER: limiter.namespace,
    ANTHROPIC_API_KEY: API_KEY,
    GOOGLE_SERVICE_ACCOUNT_JSON: await serviceAccountJson(),
    ANTHROPIC_MAX_RETRIES: "0",
    ...vars,
  } as Env;
  const deps: AppDeps = { now: clock.now, fetch: fetchMock.fetch, caches: createRuntimeCaches() };
  const pending: Promise<unknown>[] = [];
  const background = {
    pending,
    waitUntil(promise: Promise<unknown>): void {
      pending.push(promise);
    },
  };

  return {
    env,
    clock,
    fetchMock,
    limiter,
    deps,
    background,
    async request(method, path, options = {}) {
      const headers = new Headers(options.headers);
      if (options.installId !== null && !headers.has("x-install-id")) {
        headers.set("x-install-id", options.installId ?? INSTALL_ID);
      }
      if (options.ip !== null) headers.set("cf-connecting-ip", options.ip ?? CLIENT_IP);
      const init: RequestInit = { method, headers };
      if (options.body !== undefined) {
        if (!headers.has("content-type")) headers.set("content-type", "application/json");
        init.body = typeof options.body === "string" ? options.body : JSON.stringify(options.body);
      }
      return handleRequest(new Request(`https://api.example.test${path}`, init), env, background, deps);
    },
    async flush() {
      await Promise.all(pending.splice(0));
    },
  };
}

export const PREMIUM_HEADERS: Readonly<Record<string, string>> = {
  authorization: `Bearer ${PURCHASE_TOKEN}`,
  "x-product-id": "md_scanner_premium_yearly",
};

export function activeSubscription(clock: TestClock, productId = "md_scanner_premium_yearly"): unknown {
  return {
    kind: "androidpublisher#subscriptionPurchaseV2",
    subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    lineItems: [
      {
        productId,
        expiryTime: new Date(clock.ms + 30 * DAY).toISOString(),
        autoRenewingPlan: { autoRenewEnabled: true },
      },
    ],
  };
}

/** Registers Google mocks that answer with an active subscription. */
export function mockGooglePlay(app: TestApp, purchase?: unknown | (() => Response)): void {
  app.fetchMock.on(GOOGLE_OAUTH_HOST, () => googleTokenReply());
  app.fetchMock.on(PLAY_API_HOST, () =>
    typeof purchase === "function" ? (purchase as () => Response)() : jsonReply(200, purchase ?? activeSubscription(app.clock)),
  );
}

export async function readJson(response: Response): Promise<Record<string, any>> {
  return (await response.json()) as Record<string, any>;
}

export const SUMMARY_RESULT = {
  title: "Quarterly report",
  summary: "MODEL_OUTPUT_SUMMARY_SENTINEL describing the report.",
  keyPoints: ["First point.", "Second point."],
};
