import { beforeAll, describe, expect, it } from "vitest";
import {
  APPLE_ISSUER,
  AppleSignInError,
  appleAuthorizeUrl,
  base64Url,
  createClientSecret,
  redeemAppleCode,
  verifyAppleIdToken,
  type AppleConfig,
} from "../src/auth/apple";

const NOW = Date.UTC(2026, 8, 28, 9, 0);
const NOW_SECONDS = NOW / 1000;

/** A stand-in for Apple: our own RSA key signs identity tokens and is served as the JWKS. */
let appleSigningKey: CryptoKeyPair;
let applePublicJwk: JsonWebKey & { kid: string };
let developerKey: CryptoKeyPair;
let config: AppleConfig;

beforeAll(async () => {
  appleSigningKey = (await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  const publicJwk = (await crypto.subtle.exportKey("jwk", appleSigningKey.publicKey)) as JsonWebKey;
  applePublicJwk = { ...publicJwk, kid: "apple-key-1" };

  developerKey = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const pkcs8 = new Uint8Array((await crypto.subtle.exportKey("pkcs8", developerKey.privateKey)) as ArrayBuffer);
  config = {
    servicesId: "com.quickbox.web",
    teamId: "TEAM123456",
    keyId: "KEY1234567",
    privateKey: `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pkcs8))}\n-----END PRIVATE KEY-----`,
    redirectUri: "https://quickbox.test/auth/apple/callback",
  };
});

async function signIdToken(claims: Record<string, unknown>, kid = "apple-key-1"): Promise<string> {
  const encode = (value: unknown) => base64Url(new TextEncoder().encode(JSON.stringify(value)));
  const input = `${encode({ alg: "RS256", kid })}.${encode(claims)}`;
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", appleSigningKey.privateKey, new TextEncoder().encode(input));
  return `${input}.${base64Url(new Uint8Array(signature))}`;
}

const validClaims = {
  iss: APPLE_ISSUER,
  aud: "com.quickbox.web",
  exp: NOW_SECONDS + 600,
  iat: NOW_SECONDS,
  sub: "001234.abcd",
  nonce: "nonce-1",
  email: "ada@example.com",
  email_verified: "true",
};

function fakeApple(idToken: string, onTokenRequest?: (body: URLSearchParams) => void): typeof fetch {
  return async (input, init) => {
    const url = String(input instanceof Request ? input.url : input);
    if (url === `${APPLE_ISSUER}/auth/keys`) return Response.json({ keys: [applePublicJwk] });
    if (url === `${APPLE_ISSUER}/auth/token`) {
      onTokenRequest?.(new URLSearchParams(String(init?.body)));
      return Response.json({ id_token: idToken, access_token: "unused" });
    }
    return new Response("not found", { status: 404 });
  };
}

describe("Sign in with Apple", () => {
  it("builds the authorize URL with form_post, state and nonce", () => {
    const url = new URL(appleAuthorizeUrl(config, "state-1", "nonce-1"));

    expect(url.origin + url.pathname).toBe(`${APPLE_ISSUER}/auth/authorize`);
    expect(Object.fromEntries(url.searchParams)).toMatchObject({
      client_id: "com.quickbox.web",
      redirect_uri: config.redirectUri,
      response_type: "code",
      response_mode: "form_post",
      state: "state-1",
      nonce: "nonce-1",
    });
  });

  it("signs a client secret Apple can verify with the developer's public key", async () => {
    const secret = await createClientSecret(config, () => NOW);
    const [header, payload, signature] = secret.split(".");
    const decode = (part: string) => JSON.parse(Buffer.from(part, "base64url").toString());

    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      developerKey.publicKey,
      Buffer.from(signature!, "base64url"),
      new TextEncoder().encode(`${header}.${payload}`),
    );

    expect(valid).toBe(true);
    expect(decode(header!)).toEqual({ alg: "ES256", kid: "KEY1234567", typ: "JWT" });
    expect(decode(payload!)).toEqual({
      iss: "TEAM123456",
      iat: NOW_SECONDS,
      exp: NOW_SECONDS + 300,
      aud: APPLE_ISSUER,
      sub: "com.quickbox.web",
    });
  });

  it("redeems a code and returns verified claims", async () => {
    let tokenRequest: URLSearchParams | undefined;
    const idToken = await signIdToken(validClaims);

    const claims = await redeemAppleCode(config, "code-1", "nonce-1", fakeApple(idToken, (body) => (tokenRequest = body)), () => NOW);

    expect(claims).toEqual({ sub: "001234.abcd", email: "ada@example.com", email_verified: "true" });
    expect(tokenRequest?.get("code")).toBe("code-1");
    expect(tokenRequest?.get("redirect_uri")).toBe(config.redirectUri);
    expect(tokenRequest?.get("client_secret")?.split(".")).toHaveLength(3);
  });

  it.each([
    ["another audience", { aud: "com.someone.else" }],
    ["another issuer", { iss: "https://evil.example" }],
    ["an expired token", { exp: NOW_SECONDS - 120 }],
    ["a replayed nonce", { nonce: "nonce-2" }],
  ])("rejects %s", async (_, overrides) => {
    const idToken = await signIdToken({ ...validClaims, ...overrides });

    await expect(
      verifyAppleIdToken(idToken, { audience: "com.quickbox.web", nonce: "nonce-1" }, fakeApple(idToken), () => NOW),
    ).rejects.toThrow(AppleSignInError);
  });

  it("rejects tokens with a tampered payload or an unknown key", async () => {
    const idToken = await signIdToken(validClaims);
    const [header, , signature] = idToken.split(".");
    const forgedPayload = base64Url(new TextEncoder().encode(JSON.stringify({ ...validClaims, sub: "attacker" })));
    const unknownKey = await signIdToken(validClaims, "other-key");
    const verify = (token: string) =>
      verifyAppleIdToken(token, { audience: "com.quickbox.web", nonce: "nonce-1" }, fakeApple(token), () => NOW);

    await expect(verify(`${header}.${forgedPayload}.${signature}`)).rejects.toThrow("signature");
    await expect(verify(unknownKey)).rejects.toThrow("signing key");
  });
});
