import type { InboxStore } from "../store/inboxStore";
import { pushRequestSchema } from "./ops";

const MAX_BODY_BYTES = 4 * 1024 * 1024;

/**
 * Device sync over HTTP, mounted under the MCP resource so the same access tokens apply:
 *   GET  /mcp/sync/changes?cursor=N  → files changed after version N
 *   POST /mcp/sync/push              → apply ops, returns one result per op
 */
export async function handleSyncRequest(request: Request, inbox: DurableObjectStub<InboxStore>): Promise<Response> {
  const url = new URL(request.url);

  if (url.pathname === "/mcp/sync/changes" && request.method === "GET") {
    const cursor = Number(url.searchParams.get("cursor") ?? "0");
    if (!Number.isSafeInteger(cursor) || cursor < 0) return jsonError(400, "cursor must be a non-negative integer");
    return Response.json(await inbox.syncChanges(cursor));
  }

  if (url.pathname === "/mcp/sync/push" && request.method === "POST") {
    if (Number(request.headers.get("content-length") ?? "0") > MAX_BODY_BYTES) return jsonError(413, "Request too large");
    let body: unknown;
    try {
      body = await request.json();
    } catch {
      return jsonError(400, "Body must be JSON");
    }
    const parsed = pushRequestSchema.safeParse(body);
    if (!parsed.success) return jsonError(400, parsed.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`).join("; "));
    return Response.json({ results: await inbox.syncPush(parsed.data) });
  }

  return jsonError(404, "Not found");
}

function jsonError(status: number, message: string): Response {
  return Response.json({ error: message }, { status });
}
