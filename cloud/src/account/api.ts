import type { GrantSummary, ListResult } from "@cloudflare/workers-oauth-provider";

/** The OAuth helpers account management needs (a subset of `OAuthHelpers`). */
export interface GrantAdmin {
  listUserGrants(userId: string, options?: { cursor?: string; limit?: number }): Promise<ListResult<GrantSummary>>;
  revokeGrant(grantId: string, userId: string): Promise<void>;
}

export interface AccountDeps {
  grants: GrantAdmin;
  directory: { accountEmail(userId: string): Promise<string | null>; deleteUser(userId: string): Promise<void> };
  inbox: { deleteAllData(): Promise<void> };
  /** Client id of the quickbox apps, to label them apart from agents. */
  firstPartyClientId: string;
}

export interface AccountPrincipal {
  userId: string;
  /** The grant behind the calling token, shown as "this device". */
  grantId: string | null;
}

export interface ConnectedApp {
  grantId: string;
  name: string;
  /** Milliseconds since the Unix epoch. */
  connectedAt: number;
  isQuickboxApp: boolean;
  isThisDevice: boolean;
}

export const DELETE_CONFIRMATION = "DELETE";

/**
 * Account management for the signed-in user, reachable only from the quickbox apps:
 *   GET    /mcp/account                → email and connected apps
 *   DELETE /mcp/account/apps/{grantId} → disconnect one app or agent
 *   POST   /mcp/account/delete         → delete the account and all cloud data ({"confirm":"DELETE"})
 */
export async function handleAccountRequest(request: Request, principal: AccountPrincipal, deps: AccountDeps): Promise<Response> {
  const { pathname } = new URL(request.url);

  if (pathname === "/mcp/account" && request.method === "GET") {
    return Response.json({
      email: await deps.directory.accountEmail(principal.userId),
      apps: await connectedApps(principal, deps),
    });
  }

  const appMatch = /^\/mcp\/account\/apps\/([^/]+)$/.exec(pathname);
  if (appMatch && request.method === "DELETE") {
    const grantId = decodeURIComponent(appMatch[1]!);
    const owned = (await allGrants(principal.userId, deps.grants)).some((grant) => grant.id === grantId);
    if (!owned) return Response.json({ error: "No such connected app" }, { status: 404 });
    await deps.grants.revokeGrant(grantId, principal.userId);
    return new Response(null, { status: 204 });
  }

  if (pathname === "/mcp/account/delete" && request.method === "POST") {
    const body = (await request.json().catch(() => null)) as { confirm?: unknown } | null;
    if (body?.confirm !== DELETE_CONFIRMATION) {
      return Response.json({ error: `Send {"confirm":"${DELETE_CONFIRMATION}"} to delete the account` }, { status: 400 });
    }
    await deleteAccount(principal.userId, deps);
    return new Response(null, { status: 204 });
  }

  return Response.json({ error: "Not found" }, { status: 404 });
}

/**
 * Order matters. Revoking access first stops agents from writing while data is removed. The
 * directory entry goes last: if a step fails, signing in again with the same address reaches the
 * same user id, and deleting again finishes the job.
 */
async function deleteAccount(userId: string, deps: AccountDeps): Promise<void> {
  for (const grant of await allGrants(userId, deps.grants)) {
    await deps.grants.revokeGrant(grant.id, userId);
  }
  await deps.inbox.deleteAllData();
  await deps.directory.deleteUser(userId);
}

async function connectedApps(principal: AccountPrincipal, deps: AccountDeps): Promise<ConnectedApp[]> {
  const grants = await allGrants(principal.userId, deps.grants);
  return grants
    .map((grant) => ({
      grantId: grant.id,
      name: typeof grant.metadata?.clientName === "string" ? grant.metadata.clientName : grant.clientId,
      connectedAt: grant.createdAt * 1000,
      isQuickboxApp: grant.clientId === deps.firstPartyClientId,
      isThisDevice: grant.id === principal.grantId,
    }))
    .sort((a, b) => b.connectedAt - a.connectedAt);
}

async function allGrants(userId: string, grants: GrantAdmin): Promise<GrantSummary[]> {
  const all: GrantSummary[] = [];
  let cursor: string | undefined;
  do {
    const page = await grants.listUserGrants(userId, { cursor, limit: 100 });
    all.push(...page.items);
    cursor = page.cursor;
  } while (cursor);
  return all;
}
