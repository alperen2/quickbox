/**
 * Sign in with Apple for the web (OAuth code flow with `response_mode=form_post`).
 * https://developer.apple.com/documentation/signinwithapplerestapi
 */

export const APPLE_ISSUER = "https://appleid.apple.com";
const AUTHORIZE_URL = `${APPLE_ISSUER}/auth/authorize`;
const TOKEN_URL = `${APPLE_ISSUER}/auth/token`;
const KEYS_URL = `${APPLE_ISSUER}/auth/keys`;
const CLIENT_SECRET_TTL_SECONDS = 5 * 60;
const CLOCK_SKEW_SECONDS = 60;

export interface AppleConfig {
  /** The Services ID registered for web sign-in; it is the OAuth `client_id`. */
  servicesId: string;
  teamId: string;
  keyId: string;
  /** Contents of the `.p8` key file (PKCS#8 PEM, P-256). */
  privateKey: string;
  redirectUri: string;
}

export interface AppleClaims {
  sub: string;
  email?: string;
  email_verified?: boolean | string;
}

export class AppleSignInError extends Error {
  override readonly name = "AppleSignInError";
}

export function appleAuthorizeUrl(config: AppleConfig, state: string, nonce: string): string {
  const url = new URL(AUTHORIZE_URL);
  url.searchParams.set("client_id", config.servicesId);
  url.searchParams.set("redirect_uri", config.redirectUri);
  url.searchParams.set("response_type", "code");
  // Requesting scopes obliges form_post: Apple POSTs the result to the redirect URI.
  url.searchParams.set("response_mode", "form_post");
  url.searchParams.set("scope", "email");
  url.searchParams.set("state", state);
  url.searchParams.set("nonce", nonce);
  return url.href;
}

/** Exchanges the authorization code and returns the verified identity token claims. */
export async function redeemAppleCode(
  config: AppleConfig,
  code: string,
  expectedNonce: string,
  fetchImpl: typeof fetch = fetch,
  now: () => number = Date.now,
): Promise<AppleClaims> {
  const response = await fetchImpl(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" },
    body: new URLSearchParams({
      client_id: config.servicesId,
      client_secret: await createClientSecret(config, now),
      code,
      grant_type: "authorization_code",
      redirect_uri: config.redirectUri,
    }),
  });
  if (!response.ok) throw new AppleSignInError(`Apple token endpoint returned ${response.status}`);

  const { id_token: idToken } = (await response.json()) as { id_token?: string };
  if (!idToken) throw new AppleSignInError("Apple did not return an identity token");
  return verifyAppleIdToken(idToken, { audience: config.servicesId, nonce: expectedNonce }, fetchImpl, now);
}

/** The ES256 JWT Apple accepts as `client_secret`, signed with the developer's `.p8` key. */
export async function createClientSecret(config: AppleConfig, now: () => number = Date.now): Promise<string> {
  const issuedAt = Math.floor(now() / 1000);
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(config.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signingInput = [
    base64UrlJson({ alg: "ES256", kid: config.keyId, typ: "JWT" }),
    base64UrlJson({
      iss: config.teamId,
      iat: issuedAt,
      exp: issuedAt + CLIENT_SECRET_TTL_SECONDS,
      aud: APPLE_ISSUER,
      sub: config.servicesId,
    }),
  ].join(".");
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput));
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

export async function verifyAppleIdToken(
  idToken: string,
  expected: { audience: string; nonce: string },
  fetchImpl: typeof fetch = fetch,
  now: () => number = Date.now,
): Promise<AppleClaims> {
  const [encodedHeader, encodedPayload, encodedSignature] = idToken.split(".");
  if (!encodedHeader || !encodedPayload || !encodedSignature) throw new AppleSignInError("Malformed identity token");

  const header = decodeJson<{ alg?: string; kid?: string }>(encodedHeader);
  if (header.alg !== "RS256" || !header.kid) throw new AppleSignInError("Unexpected identity token algorithm");

  const keys = await fetchImpl(KEYS_URL).then((response) => {
    if (!response.ok) throw new AppleSignInError(`Apple keys endpoint returned ${response.status}`);
    return response.json() as Promise<{ keys: (JsonWebKey & { kid?: string })[] }>;
  });
  const jwk = keys.keys.find((candidate) => candidate.kid === header.kid);
  if (!jwk) throw new AppleSignInError("Unknown identity token signing key");

  const key = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    base64UrlToBytes(encodedSignature),
    new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`),
  );
  if (!valid) throw new AppleSignInError("Invalid identity token signature");

  const claims = decodeJson<AppleClaims & { iss?: string; aud?: string | string[]; exp?: number; nonce?: string }>(encodedPayload);
  const nowSeconds = Math.floor(now() / 1000);
  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (claims.iss !== APPLE_ISSUER) throw new AppleSignInError("Unexpected identity token issuer");
  if (!audiences.includes(expected.audience)) throw new AppleSignInError("Identity token was issued for another app");
  if (typeof claims.exp !== "number" || claims.exp + CLOCK_SKEW_SECONDS < nowSeconds) {
    throw new AppleSignInError("Identity token has expired");
  }
  if (claims.nonce !== expected.nonce) throw new AppleSignInError("Identity token nonce does not match");
  if (!claims.sub) throw new AppleSignInError("Identity token has no subject");

  return { sub: claims.sub, email: claims.email, email_verified: claims.email_verified };
}

export function isEmailVerified(claims: AppleClaims): boolean {
  return claims.email_verified === true || claims.email_verified === "true";
}

function pemToBytes(pem: string): ArrayBuffer {
  const base64 = pem.replace(/-----(BEGIN|END) [A-Z ]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0)).buffer;
}

function base64UrlJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

export function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlToBytes(value: string): Uint8Array {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
}

function decodeJson<T>(segment: string): T {
  try {
    return JSON.parse(new TextDecoder().decode(base64UrlToBytes(segment))) as T;
  } catch {
    throw new AppleSignInError("Malformed identity token");
  }
}
