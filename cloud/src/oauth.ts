import { OAuthProvider } from "@cloudflare/workers-oauth-provider";
import { createMcpHandler } from "@modelcontextprotocol/server";
import { agentName } from "./auth/agentName";
import { handleAuthRequest, INBOX_SCOPE, type AuthProps } from "./auth/routes";
import { publicUrl } from "./config";
import { createQuickboxServer } from "./mcp/server";

const DAY_SECONDS = 24 * 60 * 60;

/** `/mcp`, reachable only with an access token issued by this Worker. */
const mcpApiHandler = {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const { userId, clientName } = (ctx as ExecutionContext & { props: AuthProps }).props;
    const inbox = env.INBOX.get(env.INBOX.idFromName(userId));
    const actor = { kind: "agent", name: agentName(clientName) } as const;
    return createMcpHandler(() => createQuickboxServer(inbox, actor)).fetch(request);
  },
};

/** Everything that is not an OAuth endpoint or `/mcp`: the sign-in pages and a health check. */
const defaultHandler = {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (new URL(request.url).pathname === "/health") return new Response("ok");
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
