import type { AppleConfig } from "./auth/apple";

/** Canonical origin of this deployment, e.g. `https://quickbox.example.com` (no trailing slash). */
export function publicUrl(env: Env): string {
  return env.PUBLIC_URL.replace(/\/+$/, "");
}

/** Sign in with Apple is offered only when every credential is configured. */
export function appleConfig(env: Env): AppleConfig | null {
  const { APPLE_SERVICES_ID, APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY } = env;
  if (!APPLE_SERVICES_ID || !APPLE_TEAM_ID || !APPLE_KEY_ID || !APPLE_PRIVATE_KEY) return null;
  return {
    servicesId: APPLE_SERVICES_ID,
    teamId: APPLE_TEAM_ID,
    keyId: APPLE_KEY_ID,
    privateKey: APPLE_PRIVATE_KEY,
    redirectUri: `${publicUrl(env)}/auth/apple/callback`,
  };
}
