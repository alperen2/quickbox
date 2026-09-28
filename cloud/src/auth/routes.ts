import { AuthorizationError, CimdFetchError, type AuthRequest, type OAuthHelpers } from "@cloudflare/workers-oauth-provider";
import { accountDirectory } from "../accounts/accountDirectory";
import { appleConfig } from "../config";
import { AppleSignInError, appleAuthorizeUrl, base64Url, isEmailVerified, redeemAppleCode } from "./apple";
import { EmailDeliveryError, emailSender } from "./email";
import { isFirstPartyClient } from "./firstParty";
import { appleBridgePage, appSignInPage, codePage, consentPage, emailPage, messagePage } from "./pages";
import { PRODUCT_NAME } from "../brand";

/** The single scope: full access to the user's inbox. */
export const INBOX_SCOPE = "inbox";

/** What an access token carries to the MCP handler (encrypted at rest by the provider). */
export interface AuthProps {
  userId: string;
  /** The OAuth client's registered name, used to sign agent writes (`by:`). */
  clientName: string;
}

interface SignInState {
  method: "apple" | "email";
  clientName: string;
  /** Apple only: must come back unchanged inside the identity token. */
  nonce?: string;
}

/**
 * The authorization UI: `/authorize` shows consent with the sign-in choices, then the chosen
 * method runs as an "upstream" step whose `state` the provider binds to this browser.
 */
export async function handleAuthRequest(request: Request, env: Env): Promise<Response> {
  const { pathname } = new URL(request.url);
  const method = request.method;
  try {
    if (pathname === "/authorize" && method === "GET") return await showConsent(request, env);
    if (pathname === "/authorize" && method === "POST") return await decide(request, env);
    if (pathname === "/auth/email" && method === "GET") return showEmailForm(request);
    if (pathname === "/auth/email/send" && method === "POST") return await sendCode(request, env);
    if (pathname === "/auth/email/verify" && method === "POST") return await verifyCode(request, env);
    if (pathname === "/auth/apple/callback" && method === "POST") return await bridgeAppleCallback(request);
    if (pathname === "/auth/apple/complete" && method === "GET") return await completeApple(request, env);
    return new Response("Not found", { status: 404 });
  } catch (error) {
    return authErrorResponse(error);
  }
}

async function showConsent(request: Request, env: Env): Promise<Response> {
  const oauth = env.OAUTH_PROVIDER;
  const authRequest = await oauth.parseAuthRequest(request);
  const client = await oauth.lookupClient(authRequest.clientId);
  if (!client) return html(messagePage("Unknown app", `This app is not registered with ${PRODUCT_NAME}.`), { status: 400 });

  const consent = await oauth.beginConsent(authRequest);
  const methods = availableMethods(env);
  const body = (await isFirstPartyClient(env, client.clientId))
    ? appSignInPage(consent.handle, methods)
    : consentPage(client, authRequest, consent.handle, methods);
  return html(body, { headers: consent.headers });
}

async function decide(request: Request, env: Env): Promise<Response> {
  const oauth = env.OAUTH_PROVIDER;
  const form = await request.formData();
  const handle = String(form.get("handle") ?? "");
  const decision = String(form.get("decision") ?? "");
  const methods = availableMethods(env);

  if (decision !== "apple" && decision !== "email") {
    const denied = await oauth.denyConsent(request, handle);
    return new Response(null, { status: 302, headers: denied.headers });
  }
  if (!methods[decision]) return html(messagePage("Unavailable", "This sign-in method is not available."), { status: 400 });

  const approved = await oauth.approveConsent(request, handle, { scope: [INBOX_SCOPE] });
  const client = await oauth.lookupClient(approved.request.clientId);
  const signIn: SignInState = {
    method: decision,
    clientName: client?.clientName ?? approved.request.clientId,
    nonce: decision === "apple" ? randomToken() : undefined,
  };
  const { state, headers } = await oauth.beginUpstream(approved.request, { data: signIn, headers: approved.headers });

  headers.set(
    "Location",
    decision === "apple" ? appleAuthorizeUrl(appleConfig(env)!, state, signIn.nonce!) : `/auth/email?state=${encodeURIComponent(state)}`,
  );
  return new Response(null, { status: 302, headers });
}

function showEmailForm(request: Request): Response {
  const state = requireState(request);
  return html(emailPage(state));
}

async function sendCode(request: Request, env: Env): Promise<Response> {
  const state = requireState(request);
  const sender = emailSender(env);
  if (!sender) return html(messagePage("Unavailable", "Email sign-in is not configured."), { status: 503 });

  const email = String((await request.formData()).get("email") ?? "");
  const result = await accountDirectory(env).requestEmailCode(email);
  if (!result.ok && result.reason === "invalid_email") return html(emailPage(state, "Enter a valid email address."));

  const normalized = email.trim().toLowerCase();
  if (!result.ok) {
    return html(codePage(state, normalized, `Please wait ${result.retryAfterSeconds} seconds before asking for another code.`));
  }
  if (result.deliver) await sender.sendSignInCode(normalized, result.code);
  return html(codePage(state, normalized));
}

async function verifyCode(request: Request, env: Env): Promise<Response> {
  const state = requireState(request);
  const form = await request.formData();
  const email = String(form.get("email") ?? "");
  const result = await accountDirectory(env).verifyEmailCode(email, String(form.get("code") ?? ""));
  if (!result.ok) {
    const message = {
      invalid_code: "That code is not correct.",
      expired: "That code has expired. Ask for a new one.",
      too_many_attempts: "Too many attempts. Ask for a new code.",
    }[result.reason];
    return html(codePage(state, email, message));
  }

  const { request: authRequest, data, headers } = await env.OAUTH_PROVIDER.finishUpstream<SignInState>(request);
  if (data.method !== "email") throw new AuthorizationError("invalid_request", { description: "Sign-in method mismatch" });
  return completeSignIn(env.OAUTH_PROVIDER, authRequest, result.userId, data.clientName, headers);
}

async function bridgeAppleCallback(request: Request): Promise<Response> {
  const form = await request.formData();
  const fields: Record<string, string> = {};
  for (const name of ["state", "code", "error"]) {
    const value = form.get(name);
    if (typeof value === "string") fields[name] = value;
  }
  const nonce = randomToken();
  return html(appleBridgePage(fields, nonce), { scriptNonce: nonce });
}

async function completeApple(request: Request, env: Env): Promise<Response> {
  const oauth = env.OAUTH_PROVIDER;
  const { request: authRequest, data, headers } = await oauth.finishUpstream<SignInState>(request);
  const params = new URL(request.url).searchParams;
  const code = params.get("code");
  const config = appleConfig(env);

  if (params.get("error") || !code || !config || data.method !== "apple" || !data.nonce) {
    return redirectWithError(authRequest, "access_denied", headers);
  }

  const claims = await redeemAppleCode(config, code, data.nonce);
  const userId = await accountDirectory(env).signInWithApple({
    subject: claims.sub,
    email: claims.email ?? null,
    emailVerified: isEmailVerified(claims),
  });
  return completeSignIn(oauth, authRequest, userId, data.clientName, headers);
}

async function completeSignIn(
  oauth: OAuthHelpers,
  authRequest: AuthRequest,
  userId: string,
  clientName: string,
  headers: Headers,
): Promise<Response> {
  const props: AuthProps = { userId, clientName };
  const { redirectTo } = await oauth.completeAuthorization({
    request: authRequest,
    userId,
    metadata: { clientName },
    scope: authRequest.scope,
    props,
  });
  headers.set("Location", redirectTo);
  return new Response(null, { status: 302, headers });
}

function redirectWithError(authRequest: AuthRequest, error: string, headers: Headers): Response {
  const redirect = new URL(authRequest.redirectUri);
  redirect.searchParams.set("error", error);
  redirect.searchParams.set("state", authRequest.state);
  if (authRequest.issuer) redirect.searchParams.set("iss", authRequest.issuer);
  headers.set("Location", redirect.href);
  return new Response(null, { status: 302, headers });
}

/** Which errors go back to the client and which are shown here (see the provider's consent-page guide). */
function authErrorResponse(error: unknown): Response {
  if (error instanceof AuthorizationError && error.redirectUri) {
    const redirect = new URL(error.redirectUri);
    redirect.searchParams.set("error", error.code);
    redirect.searchParams.set("error_description", error.description);
    if (error.state) redirect.searchParams.set("state", error.state);
    if (error.issuer) redirect.searchParams.set("iss", error.issuer);
    return Response.redirect(redirect.href, 302);
  }
  if (error instanceof AuthorizationError) {
    return html(messagePage("Sign-in expired", `${error.description}. Go back to the app and connect again.`), { status: 400 });
  }
  if (error instanceof CimdFetchError) {
    return html(messagePage("Unknown app", "This app could not be verified."), { status: 400 });
  }
  if (error instanceof EmailDeliveryError) {
    console.error("Sign-in code email failed:", error.message);
    return html(messagePage("Couldn't send the code", "Please try again in a minute."), { status: 503 });
  }
  if (error instanceof AppleSignInError) {
    console.warn("Apple sign-in failed:", error.message);
    return html(messagePage("Apple sign-in failed", "Please go back to the app and try again."), { status: 400 });
  }
  throw error;
}

function availableMethods(env: Env) {
  return { apple: appleConfig(env) !== null, email: emailSender(env) !== null };
}

function requireState(request: Request): string {
  const state = new URL(request.url).searchParams.get("state");
  if (!state) throw new AuthorizationError("invalid_request", { description: "Missing sign-in state" });
  return state;
}

function randomToken(): string {
  return base64Url(crypto.getRandomValues(new Uint8Array(32)));
}

function html(body: string, options: { status?: number; headers?: Headers; scriptNonce?: string } = {}): Response {
  const headers = new Headers(options.headers);
  headers.set("Content-Type", "text/html; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  headers.set("X-Frame-Options", "DENY");
  headers.append(
    "Content-Security-Policy",
    [
      "default-src 'none'",
      "style-src 'unsafe-inline'",
      options.scriptNonce ? `script-src 'nonce-${options.scriptNonce}'` : "script-src 'none'",
      "frame-ancestors 'none'",
      "base-uri 'none'",
    ].join("; "),
  );
  return new Response(body, { status: options.status ?? 200, headers });
}
