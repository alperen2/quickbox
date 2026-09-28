// Secrets, optional vars and injected helpers that `wrangler types` cannot see in wrangler.jsonc.
interface Env {
  /** Injected by `OAuthProvider` into its handlers. */
  OAUTH_PROVIDER: import("@cloudflare/workers-oauth-provider").OAuthHelpers;

  APPLE_SERVICES_ID?: string;
  APPLE_TEAM_ID?: string;
  APPLE_KEY_ID?: string;
  /** Contents of the Sign in with Apple `.p8` key. */
  APPLE_PRIVATE_KEY?: string;

  RESEND_API_KEY?: string;
  /** `"true"` prints sign-in codes to the console instead of emailing them. Local development only. */
  DEV_LOG_EMAIL_CODES?: string;
}
