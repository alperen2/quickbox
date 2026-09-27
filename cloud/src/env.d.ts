// Secrets and optional vars that `wrangler types` cannot see in wrangler.jsonc.
interface Env {
  DEV_AUTH_TOKEN?: string;
  DEV_USER_ID?: string;
  DEV_AGENT_NAME?: string;
}
