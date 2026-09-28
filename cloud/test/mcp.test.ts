import { Client, StreamableHTTPClientTransport } from "@modelcontextprotocol/client";
import { createMcpHandler } from "@modelcontextprotocol/server";
import { describe, expect, it } from "vitest";
import { localInboxApi } from "../src/inbox/api";
import { MemoryFileStore } from "../src/inbox/fileStore";
import { Inbox } from "../src/inbox/inbox";
import { createQuickboxServer } from "../src/mcp/server";

const NOW = { date: { year: 2026, month: 9, day: 28 }, time: "09:12" };

function makeEndpoint(files: Record<string, string> = {}) {
  const store = new MemoryFileStore(files);
  const inbox = new Inbox(store, { now: () => NOW }, () => "newtask1");
  const handler = createMcpHandler(() => createQuickboxServer(localInboxApi(inbox), { kind: "agent", name: "claude" }));
  return { store, handler, call: (method: string, params: unknown) => rpc(handler, method, params) };
}

/** Sends a 2025-era JSON-RPC request, which is what today's hosted clients speak. */
async function rpc(handler: ReturnType<typeof createMcpHandler>, method: string, params: unknown) {
  const response = await handler.fetch(
    new Request("https://quickbox.test/mcp", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        accept: "application/json, text/event-stream",
        "mcp-protocol-version": "2025-06-18",
      },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    }),
  );
  expect(response.status).toBe(200);
  return parseJsonRpc(await response.text());
}

/** Responses may come back as plain JSON or as a single SSE event. */
function parseJsonRpc(body: string) {
  const payload = body.trimStart().startsWith("{")
    ? body
    : body
        .split("\n")
        .filter((line) => line.startsWith("data:"))
        .map((line) => line.slice("data:".length).trim())
        .join("");
  return JSON.parse(payload);
}

function toolText(message: { result: { content: { text: string }[] } }) {
  return message.result.content[0]!.text;
}

describe("MCP endpoint", () => {
  it("initializes with the agent instructions", async () => {
    const { call } = makeEndpoint();

    const message = await call("initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: { name: "test-client", version: "1.0.0" },
    });

    expect(message.result.serverInfo.name).toBe("quickbox");
    expect(message.result.instructions).toContain('list_tasks for="agent"');
  });

  it("lists the inbox tools", async () => {
    const { call } = makeEndpoint();

    const message = await call("tools/list", {});

    expect(message.result.tools.map((tool: { name: string }) => tool.name).sort()).toEqual([
      "add_task",
      "complete_task",
      "list_tasks",
      "read_note",
      "update_task",
      "write_note",
    ]);
  });

  it("adds a task signed by the authenticated agent", async () => {
    const { call, store } = makeEndpoint({ "2026-09-28.md": "- [ ] 08:00 Create Instagram post for:agent id:request1\n" });

    const message = await call("tools/call", {
      name: "add_task",
      arguments: { text: "Publish post", for: "me", from: "request1", ref: "_notes/request1.md" },
    });

    expect(JSON.parse(toolText(message))).toMatchObject({ id: "newtask1", metadata: { by: "claude", for: "me" } });
    expect(store.read("2026-09-28.md")).toContain(
      "- [ ] 09:12 Publish post by:claude for:me from:request1 ref:_notes/request1.md id:newtask1",
    );
  });

  it("returns domain errors as tool errors the agent can read", async () => {
    const { call } = makeEndpoint();

    const message = await call("tools/call", { name: "complete_task", arguments: { id: "missing1" } });

    expect(message.result.isError).toBe(true);
    expect(toolText(message)).toBe('No task with id "missing1".');
  });

  it("rejects arguments that do not match the schema", async () => {
    const { call } = makeEndpoint();

    const message = await call("tools/call", { name: "update_task", arguments: { id: "x", priority: 7 } });

    expect(message.error ?? message.result?.isError).toBeTruthy();
  });
});

describe("MCP endpoint with the official client", () => {
  it.each(["modern", "legacy"] as const)("serves a %s-era client end to end", async (mode) => {
    const { handler, store } = makeEndpoint({ "2026-09-28.md": "- [ ] 08:00 Write caption for:agent id:request1\n" });
    // Clients default to the 2025 handshake; "auto" probes for 2026-07-28 support first.
    const client = new Client(
      { name: "test-client", version: "1.0.0" },
      { versionNegotiation: { mode: mode === "modern" ? "auto" : "legacy" } },
    );
    const transport = new StreamableHTTPClientTransport(new URL("https://quickbox.test/mcp"), {
      fetch: (input, init) => handler.fetch(new Request(input, init)),
    });

    await client.connect(transport);
    const queue = await client.callTool({ name: "list_tasks", arguments: { for: "agent" } });
    await client.callTool({ name: "complete_task", arguments: { id: "request1" } });
    const era = client.getProtocolEra();
    const instructions = client.getInstructions();
    await client.close();

    expect(era).toBe(mode);
    expect(instructions).toContain("quickbox");
    expect(JSON.parse((queue.content as { text: string }[])[0]!.text)).toEqual([
      expect.objectContaining({ id: "request1", text: "Write caption" }),
    ]);
    expect(store.read("2026-09-28.md")).toBe("- [x] 08:00 Write caption for:agent id:request1\n");
  });
});
