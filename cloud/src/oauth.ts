import { OAuthProvider } from "@cloudflare/workers-oauth-provider";
import { createMcpHandler } from "@modelcontextprotocol/server";
import { agentName } from "./auth/agentName";
import { handleAccountRequest } from "./account/api";
import { accountDirectory } from "./accounts/accountDirectory";
import { APP_REDIRECT_URI, ensureFirstPartyClientId, isFirstPartyClient } from "./auth/firstParty";
import { handleAuthRequest, INBOX_SCOPE, type AuthProps } from "./auth/routes";
import { publicUrl } from "./config";
import { createQuickboxServer } from "./mcp/server";
import { handleSyncRequest } from "./sync/api";

const DAY_SECONDS = 24 * 60 * 60;

type ProtectedContext = ExecutionContext & { props: AuthProps; auth: { clientId: string; token: string } };

/** `/mcp` and `/mcp/sync/*`, reachable only with an access token issued by this Worker. */
const mcpApiHandler = {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const { props, auth } = ctx as ProtectedContext;
    const inbox = env.INBOX.get(env.INBOX.idFromName(props.userId));

    const { pathname } = new URL(request.url);
    const isSync = pathname.startsWith("/mcp/sync/");
    const isAccount = pathname === "/mcp/account" || pathname.startsWith("/mcp/account/");
    if (isSync || isAccount) {
      // These act as the user (sync writes, account deletion), so only the quickbox apps may use them.
      if (!(await isFirstPartyClient(env, auth.clientId))) return Response.json({ error: "Forbidden" }, { status: 403 });
      if (isSync) return handleSyncRequest(request, inbox);

      const token = await env.OAUTH_PROVIDER.unwrapToken(auth.token);
      return handleAccountRequest(
        request,
        { userId: props.userId, grantId: token?.grantId ?? null },
        { grants: env.OAUTH_PROVIDER, directory: accountDirectory(env), inbox, firstPartyClientId: auth.clientId },
      );
    }

    const actor = { kind: "agent", name: agentName(props.clientName) } as const;
    return createMcpHandler(() => createQuickboxServer(inbox, actor)).fetch(request);
  },
};

/** Everything that is not an OAuth endpoint or `/mcp`: the sign-in pages and a health check. */
const defaultHandler = {
  async fetch(request: Request, env: Env): Promise<Response> {
    const { pathname } = new URL(request.url);
    if (pathname === "/health") return new Response("ok");
    if (pathname === "/app/config" && request.method === "GET") {
      // Public: everything the apps need to start OAuth. The client id is not a secret (PKCE, public client).
      const origin = publicUrl(env);
      return Response.json({
        clientId: await ensureFirstPartyClientId(env, env.OAUTH_PROVIDER),
        redirectUri: APP_REDIRECT_URI,
        authorizationEndpoint: `${origin}/authorize`,
        tokenEndpoint: `${origin}/oauth/token`,
        resource: `${origin}/mcp`,
        scope: INBOX_SCOPE,
      });
    }
    return handleAuthRequest(request, env);
  },
};

let cached: { origin: string; provider: OAuthProvider<Env> } | undefined;

/** The provider's resource and issuer are this deployment's public origin, known only from `env`. */
export function oauthProvider(env: Env): OAuthProvider<Env> {
  const origin = publicUrl(env);
  if (cached?.origin === origin) return cached.provider;

  const provider = new OAuthProvider<Env>({
    apiRoute: "/mcp",
    apiHandler: mcpApiHandler,
    defaultHandler,
    authorizeEndpoint: "/authorize",
    tokenEndpoint: "/oauth/token",
    // Kept for clients that predate Client ID Metadata Documents.
    clientRegistrationEndpoint: "/oauth/register",
    clientIdMetadataDocumentEnabled: true,
    scopesSupported: [INBOX_SCOPE],
    // Agents run on schedules; keep a grant alive while it is used, expire it after a month idle.
    refreshTokenIdleTTL: 30 * DAY_SECONDS,
    resourceMetadata: {
      resource: `${origin}/mcp`,
      authorization_servers: [origin],
      scopes_supported: [INBOX_SCOPE],
      bearer_methods_supported: ["header"],
      resource_name: "quickbox",
    },
  });
  cached = { origin, provider };
  return provider;
}
