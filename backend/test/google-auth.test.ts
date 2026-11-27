import { describe, expect, it } from "vitest";
import { getAccessToken, GoogleRequestError, SCOPE_ANDROID_PUBLISHER, SCOPE_PLAY_INTEGRITY } from "../src/google/auth";
import { createServiceAccountAssertion, GOOGLE_TOKEN_URL } from "../src/google/jwt";
import { parseServiceAccount, type ServiceAccount } from "../src/google/service-account";
import { createRuntimeCaches, type AppDeps } from "../src/runtime";
import {
  FetchMock,
  GOOGLE_ACCESS_TOKEN,
  GOOGLE_OAUTH_HOST,
  googleTokenReply,
  jsonReply,
  MINUTE,
  SERVICE_ACCOUNT_EMAIL,
  serviceAccountJson,
  T0,
  TestClock,
  testKey,
} from "./helpers/harness";

function decodeSegment(segment: string): Record<string, unknown> {
  return JSON.parse(Buffer.from(segment, "base64url").toString("utf8")) as Record<string, unknown>;
}

async function account(): Promise<ServiceAccount> {
  const parsed = parseServiceAccount(await serviceAccountJson());
  if (parsed === null) throw new Error("test service account should parse");
  return parsed;
}

function setup(): { deps: AppDeps; clock: TestClock; fetchMock: FetchMock } {
  const clock = new TestClock();
  const fetchMock = new FetchMock();
  return { deps: { now: clock.now, fetch: fetchMock.fetch, caches: createRuntimeCaches() }, clock, fetchMock };
}

describe("service account parsing", () => {
  it("reads the JSON key file, raw or base64-encoded", async () => {
    const json = await serviceAccountJson();
    expect(parseServiceAccount(json)).toMatchObject({ clientEmail: SERVICE_ACCOUNT_EMAIL, privateKeyId: "test-key-id-1" });
    expect(parseServiceAccount(Buffer.from(json).toString("base64"))?.clientEmail).toBe(SERVICE_ACCOUNT_EMAIL);
  });

  it("returns null, without throwing, for anything unusable", () => {
    expect(parseServiceAccount(undefined)).toBeNull();
    expect(parseServiceAccount("   ")).toBeNull();
    expect(parseServiceAccount("{not json")).toBeNull();
    expect(parseServiceAccount("%%%not-base64%%%")).toBeNull();
    expect(parseServiceAccount(JSON.stringify({ client_email: "a@b.c" }))).toBeNull();
    expect(parseServiceAccount(JSON.stringify({ client_email: "a@b.c", private_key: "not a pem" }))).toBeNull();
  });
});

describe("RS256 JWT signing (WebCrypto)", () => {
  it("produces an assertion that verifies against the public key generated in the test", async () => {
    const { publicKey } = await testKey();
    const jwt = await createServiceAccountAssertion(await account(), SCOPE_ANDROID_PUBLISHER, T0, createRuntimeCaches());

    const [headerPart, claimsPart, signaturePart] = jwt.split(".");
    expect(headerPart && claimsPart && signaturePart).toBeTruthy();

    const valid = await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      publicKey,
      Buffer.from(signaturePart as string, "base64url"),
      new TextEncoder().encode(`${headerPart}.${claimsPart}`),
    );
    expect(valid).toBe(true);

    expect(decodeSegment(headerPart as string)).toEqual({ alg: "RS256", typ: "JWT", kid: "test-key-id-1" });
    expect(decodeSegment(claimsPart as string)).toEqual({
      iss: SERVICE_ACCOUNT_EMAIL,
      scope: SCOPE_ANDROID_PUBLISHER,
      aud: GOOGLE_TOKEN_URL,
      iat: T0 / 1000,
      exp: T0 / 1000 + 3600,
    });
  });

  it("is rejected by the verifier when the payload is tampered with", async () => {
    const { publicKey } = await testKey();
    const jwt = await createServiceAccountAssertion(await account(), SCOPE_ANDROID_PUBLISHER, T0, createRuntimeCaches());
    const [headerPart, , signaturePart] = jwt.split(".");
    const forgedClaims = Buffer.from(JSON.stringify({ iss: "attacker@example.com" })).toString("base64url");
    const valid = await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      publicKey,
      Buffer.from(signaturePart as string, "base64url"),
      new TextEncoder().encode(`${headerPart}.${forgedClaims}`),
    );
    expect(valid).toBe(false);
  });
});

describe("OAuth access token", () => {
  it("exchanges the signed assertion with the JWT bearer grant", async () => {
    const { deps, fetchMock } = setup();
    fetchMock.on(GOOGLE_OAUTH_HOST, () => googleTokenReply());

    const token = await getAccessToken(await account(), SCOPE_ANDROID_PUBLISHER, { deps, timeoutMs: 5000 });
    expect(token).toBe(GOOGLE_ACCESS_TOKEN);

    const [call] = fetchMock.calls;
    expect(call?.url.href).toBe("https://oauth2.googleapis.com/token");
    expect(call?.method).toBe("POST");
    expect(call?.headers.get("content-type")).toBe("application/x-www-form-urlencoded");
    const form = new URLSearchParams(call?.body);
    expect(form.get("grant_type")).toBe("urn:ietf:params:oauth:grant-type:jwt-bearer");
    expect(form.get("assertion")?.split(".")).toHaveLength(3);
  });

  it("caches the token until shortly before it expires, per scope", async () => {
    const { deps, clock, fetchMock } = setup();
    fetchMock.on(GOOGLE_OAUTH_HOST, () => googleTokenReply(3600));
    const sa = await account();
    const options = { deps, timeoutMs: 5000 };

    await getAccessToken(sa, SCOPE_ANDROID_PUBLISHER, options);
    clock.advance(50 * MINUTE);
    await getAccessToken(sa, SCOPE_ANDROID_PUBLISHER, options);
    expect(fetchMock.calls).toHaveLength(1);

    // Another scope needs its own token.
    await getAccessToken(sa, SCOPE_PLAY_INTEGRITY, options);
    expect(fetchMock.calls).toHaveLength(2);

    // Inside the one-minute safety margin: refreshed.
    clock.advance(9 * MINUTE + 30_000);
    await getAccessToken(sa, SCOPE_ANDROID_PUBLISHER, options);
    expect(fetchMock.calls).toHaveLength(3);
  });

  it("reports rejected credentials and outages without leaking any detail", async () => {
    const { deps, fetchMock } = setup();
    const sa = await account();
    const options = { deps, timeoutMs: 5000 };

    fetchMock.on(GOOGLE_OAUTH_HOST, () =>
      jsonReply(400, { error: "invalid_grant", error_description: `Invalid JWT for ${SERVICE_ACCOUNT_EMAIL}` }),
    );
    const rejected = await getAccessToken(sa, SCOPE_ANDROID_PUBLISHER, options).catch((error: unknown) => error);
    expect(rejected).toBeInstanceOf(GoogleRequestError);
    expect(rejected).toMatchObject({ kind: "credentials", status: 400 });
    expect(String((rejected as Error).message)).not.toContain(SERVICE_ACCOUNT_EMAIL);

    fetchMock.on(GOOGLE_OAUTH_HOST, () => jsonReply(503, {}));
    await expect(getAccessToken(sa, SCOPE_ANDROID_PUBLISHER, options)).rejects.toMatchObject({ kind: "unavailable", status: 503 });

    fetchMock.on(GOOGLE_OAUTH_HOST, () => {
      throw new TypeError("network down");
    });
    await expect(getAccessToken(sa, SCOPE_ANDROID_PUBLISHER, options)).rejects.toMatchObject({ kind: "unavailable" });
  });
});
