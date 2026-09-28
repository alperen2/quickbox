import type { AuthRequest, ClientInfo } from "@cloudflare/workers-oauth-provider";
import { PRODUCT_NAME } from "../brand";

/** Every value that reaches HTML goes through this: client names and URIs are attacker-chosen. */
export function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (char) => `&#${char.charCodeAt(0)};`);
}

const STYLE = `
:root { --bg:#f6f6f4; --card:#fff; --text:#1c1c1e; --muted:#6b6b70; --line:#e3e3df; --accent:#1c1c1e; --accent-text:#fff; --danger:#b3261e; }
@media (prefers-color-scheme: dark) { :root { --bg:#111113; --card:#1c1c1f; --text:#f2f2f3; --muted:#a1a1a8; --line:#2e2e33; --accent:#f2f2f3; --accent-text:#111113; --danger:#ff8a80; } }
* { box-sizing:border-box; }
body { margin:0; min-height:100vh; display:grid; place-items:center; padding:16px; background:var(--bg); color:var(--text);
  font:16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
main { width:100%; max-width:420px; background:var(--card); border:1px solid var(--line); border-radius:16px; padding:28px; }
h1 { font-size:20px; margin:0 0 12px; }
p { margin:0 0 12px; color:var(--muted); }
strong { color:var(--text); }
.warning { color:var(--danger); }
form { margin:0; }
label { display:block; font-size:14px; margin:16px 0 6px; }
input[type=email], input[type=text] { width:100%; padding:12px; font:inherit; border:1px solid var(--line); border-radius:10px; background:var(--bg); color:var(--text); }
button { width:100%; margin-top:12px; padding:12px; font:inherit; font-weight:600; border-radius:10px; border:1px solid var(--line); background:var(--card); color:var(--text); cursor:pointer; }
button.primary { background:var(--accent); color:var(--accent-text); border-color:var(--accent); }
button.link { border:none; background:none; color:var(--muted); font-weight:400; }
.brand { font-weight:700; letter-spacing:-0.01em; margin-bottom:20px; }
`;

function page(title: string, body: string, scriptNonce?: string): string {
  const script = scriptNonce
    ? `<script nonce="${scriptNonce}">document.forms[0].submit();</script>`
    : "";
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>${escapeHtml(title)}</title>
<style>${STYLE}</style>
</head>
<body><main><div class="brand">${PRODUCT_NAME}</div>${body}</main>${script}</body>
</html>`;
}

export interface SignInMethods {
  apple: boolean;
  email: boolean;
}

function signInButtons(handle: string, methods: SignInMethods, denyLabel: string): string {
  return `<form method="post" action="/authorize">
  <input type="hidden" name="handle" value="${escapeHtml(handle)}">
  ${methods.apple ? '<button class="primary" name="decision" value="apple">Continue with Apple</button>' : ""}
  ${methods.email ? `<button${methods.apple ? "" : ' class="primary"'} name="decision" value="email">Continue with email</button>` : ""}
  <button class="link" name="decision" value="deny">${denyLabel}</button>
</form>`;
}

/** The first-party apps' own sign-in: no third party is being granted access. */
export function appSignInPage(handle: string, methods: SignInMethods): string {
  return page(
    `Sign in to ${PRODUCT_NAME}`,
    `<h1>Sign in to ${PRODUCT_NAME}</h1>
<p>Sync your inbox across your devices and your AI agents.</p>
${signInButtons(handle, methods, "Cancel")}`,
  );
}

/** Consent and sign-in in one step: every "continue" button is an approval for this client. */
export function consentPage(client: ClientInfo, request: AuthRequest, handle: string, methods: SignInMethods): string {
  const name = escapeHtml(client.clientName ?? client.clientId);
  const redirectHost = new URL(request.redirectUri).hostname;
  const isLocal = /^(localhost|127(\.\d{1,3}){3}|\[::1\])$/.test(redirectHost);
  const publisher = client.clientId.startsWith("https://")
    ? `Published by <strong>${escapeHtml(new URL(client.clientId).hostname)}</strong>.`
    : "This app registered itself, so its name is not verified.";

  return page(
    `Allow ${client.clientName ?? "this app"} to use ${PRODUCT_NAME}`,
    `<h1>Allow <strong>${name}</strong> to use your ${PRODUCT_NAME} inbox?</h1>
<p>It will be able to read and change your tasks and notes. ${publisher}</p>
<p>Access will be sent to <strong>${escapeHtml(redirectHost)}</strong>.</p>
${isLocal ? '<p class="warning">This sends access to an app on your computer. Continue only if you just started connecting from it.</p>' : ""}
${signInButtons(handle, methods, "Don't allow")}`,
  );
}

export function emailPage(state: string, message?: string): string {
  return page(
    `Sign in to ${PRODUCT_NAME}`,
    `<h1>Sign in with email</h1>
<p>We'll send you a 6-digit code.</p>
${message ? `<p class="warning">${escapeHtml(message)}</p>` : ""}
<form method="post" action="/auth/email/send?state=${encodeURIComponent(state)}">
  <label for="email">Email</label>
  <input id="email" type="email" name="email" autocomplete="email" required autofocus>
  <button class="primary">Send code</button>
</form>`,
  );
}

export function codePage(state: string, email: string, message?: string): string {
  return page(
    "Enter your code",
    `<h1>Check your email</h1>
<p>Enter the code we sent to <strong>${escapeHtml(email)}</strong>. It expires in 10 minutes.</p>
${message ? `<p class="warning">${escapeHtml(message)}</p>` : ""}
<form method="post" action="/auth/email/verify?state=${encodeURIComponent(state)}">
  <input type="hidden" name="email" value="${escapeHtml(email)}">
  <label for="code">Code</label>
  <input id="code" type="text" name="code" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9 ]{6,7}" required autofocus>
  <button class="primary">Continue</button>
</form>
<form method="post" action="/auth/email/send?state=${encodeURIComponent(state)}">
  <input type="hidden" name="email" value="${escapeHtml(email)}">
  <button class="link">Send a new code</button>
</form>`,
  );
}

/**
 * Apple POSTs its result from appleid.apple.com, a cross-site request that carries no
 * `SameSite=Lax` cookies. This page re-submits the fields to our own origin as a same-site
 * navigation, so the browser-binding cookie of the sign-in flow is sent again.
 */
export function appleBridgePage(fields: Record<string, string>, scriptNonce: string): string {
  const inputs = Object.entries(fields)
    .map(([name, value]) => `<input type="hidden" name="${escapeHtml(name)}" value="${escapeHtml(value)}">`)
    .join("");
  return page(
    "Signing in…",
    `<h1>Signing you in…</h1>
<form method="get" action="/auth/apple/complete">${inputs}<noscript><button class="primary">Continue</button></noscript></form>`,
    scriptNonce,
  );
}

export function messagePage(title: string, message: string): string {
  return page(title, `<h1>${escapeHtml(title)}</h1><p>${escapeHtml(message)}</p>`);
}
