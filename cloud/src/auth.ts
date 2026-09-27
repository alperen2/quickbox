import type { Actor } from "./inbox/types";

export interface Principal {
  /** Selects the user's `InboxStore`. */
  userId: string;
  actor: Actor;
}

export interface DevAuthConfig {
  DEV_AUTH_TOKEN?: string;
  DEV_USER_ID?: string;
  DEV_AGENT_NAME?: string;
}

/**
 * Development-only auth: a single shared bearer token set in `.dev.vars`.
 * Fails closed when no token is configured. Replaced by OAuth before any public deployment.
 */
export function authenticateDev(request: Request, config: DevAuthConfig): Principal | null {
  const expected = config.DEV_AUTH_TOKEN;
  const presented = /^Bearer (.+)$/.exec(request.headers.get("Authorization") ?? "")?.[1];
  if (!expected || !presented || !constantTimeEqual(presented, expected)) return null;

  return {
    userId: config.DEV_USER_ID ?? "dev",
    actor: { kind: "agent", name: agentName(config.DEV_AGENT_NAME ?? "agent") },
  };
}

/** Turns a client's display name into a `by:` token value, e.g. "Claude Desktop" → "claude-desktop". */
export function agentName(displayName: string): string {
  const slug = displayName
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return slug || "agent";
}

function constantTimeEqual(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  let difference = left.length ^ right.length;
  for (let index = 0; index < left.length; index += 1) difference |= left[index]! ^ (right[index % right.length] ?? 0);
  return difference === 0;
}
