import { createMcpHandler } from "@modelcontextprotocol/server";
import { authenticateDev } from "./auth";
import { createQuickboxServer } from "./mcp/server";

export { InboxStore } from "./store/inboxStore";

export default {
  async fetch(request, env): Promise<Response> {
    const { pathname } = new URL(request.url);

    if (pathname === "/health") return new Response("ok");
    if (pathname !== "/mcp") return new Response("Not found", { status: 404 });

    const principal = authenticateDev(request, env);
    if (!principal) {
      return new Response("Unauthorized", { status: 401, headers: { "WWW-Authenticate": "Bearer" } });
    }

    const inbox = env.INBOX.get(env.INBOX.idFromName(principal.userId));
    const handler = createMcpHandler(() => createQuickboxServer(inbox, principal.actor));
    return handler.fetch(request);
  },
} satisfies ExportedHandler<Env>;
