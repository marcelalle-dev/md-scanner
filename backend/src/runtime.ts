/**
 * Runtime dependencies injected into every handler. Production uses the
 * defaults below; tests inject a controllable clock, a mocked `fetch` and
 * fresh caches.
 */

export type FetchLike = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

export interface CachedAccessToken {
  token: string;
  /** Epoch milliseconds. */
  expiresAt: number;
}

/**
 * Per-isolate caches. They hold plain data only (never a pending promise),
 * so sharing them between requests is safe in the Workers runtime.
 */
export interface RuntimeCaches {
  /** Google OAuth access tokens, keyed by `client_email|scope`. */
  googleTokens: Map<string, CachedAccessToken>;
  /** Imported RSA signing keys, keyed by the PEM text. */
  signingKeys: Map<string, CryptoKey>;
}

export interface AppDeps {
  /** Business clock (quotas, token expiry). Epoch milliseconds. */
  now: () => number;
  fetch: FetchLike;
  caches: RuntimeCaches;
}

export function createRuntimeCaches(): RuntimeCaches {
  return { googleTokens: new Map(), signingKeys: new Map() };
}

export const defaultDeps: AppDeps = {
  now: () => Date.now(),
  // Wrapped so that `fetch` is always invoked with the global `this`.
  fetch: (input, init) => fetch(input, init),
  caches: createRuntimeCaches(),
};
