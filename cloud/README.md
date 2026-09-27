# quickbox cloud

Remote MCP server that gives AI agents (claude.ai, Claude Desktop, ChatGPT, any MCP client) access to a user's quickbox inbox. The inbox is the same Markdown task and note files the Mac app writes. Runs on Cloudflare Workers with one Durable Object per user.

```
MCP client ──HTTP──▶ Worker (/mcp) ──auth──▶ InboxStore (Durable Object, SQLite)
                     createMcpHandler        └─ Inbox (domain) ─ FileStore: one row per .md file
```

- **`src/core/`**: the task line format, natural-language dates and task ids. This is a port of `Packages/QuickboxCore`. Both implementations run against the same `../fixtures/*.json` golden cases.
- **`src/inbox/`**: the `Inbox` domain logic. It follows the app's routing (daily file or `<Project>.md` with a `date:` tag), its day view, and its editing rules. It is synchronous and storage-agnostic.
- **`src/store/`**: the `InboxStore` Durable Object. Each user gets one instance, which makes it the single writer, so edits from the phone, the Mac and agents never race.
- **`src/mcp/`**: the tools `list_tasks`, `add_task`, `update_task`, `complete_task`, `read_note` and `write_note`, plus agent instructions. Each request is served statelessly, for both 2025-era and 2026-07-28 clients.

Agents never write their own `by:`. The server sets it from the authenticated client.

## Develop

```bash
npm ci
cp .dev.vars.example .dev.vars   # set DEV_AUTH_TOKEN
npm run dev                      # http://localhost:8787/mcp
npm test                         # domain, fixtures, MCP (both protocol eras)
npm run typecheck
```

## Status

Auth is **development-only**: a single bearer token from `.dev.vars`, mapped to one user. OAuth, which claude.ai and ChatGPT connectors require, comes before any public deployment. Until then, do not deploy this with real data.
