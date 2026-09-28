# quickbox cloud

Remote MCP server that gives AI agents (claude.ai, Claude Desktop, ChatGPT, any MCP client) access to a user's quickbox inbox. The inbox is the same Markdown task and note files the Mac app writes. Runs on Cloudflare Workers with one Durable Object per user.

```
MCP client ──OAuth 2.1──▶ OAuthProvider ──/mcp + token──▶ createMcpHandler ──▶ InboxStore (one DO per user, SQLite)
                              │                                                  └─ Inbox (domain) ─ one row per .md file
                              └─ /authorize: consent + Sign in with Apple / email code ──▶ AccountDirectory (global DO)
```

- **`src/core/`**: the task line format, natural-language dates and task ids. This is a port of `Packages/QuickboxCore`. Both implementations run against the same `../fixtures/*.json` golden cases.
- **`src/inbox/`**: the `Inbox` domain logic. It follows the app's layout (`<day>.md`, `<Project>/<day>.md`, notes in `_notes/`), its day view, and its editing rules. It is synchronous and storage-agnostic.
- **`src/store/`**: the `InboxStore` Durable Object. Each user gets one instance, which makes it the single writer, so edits from the phone, the Mac and agents never race.
- **`src/auth/`, `src/oauth.ts`**: `@cloudflare/workers-oauth-provider` issues tokens for `/mcp`. It supports Client ID Metadata Documents and dynamic registration. `/authorize` is one consent page that names the client and offers the sign-in methods. Each method then runs as a browser-bound upstream step.
- **`src/accounts/`**: the `AccountDirectory` Durable Object stores users, identities and email codes. Apple and email sign-ins with the same verified address reach the same user.
- **`src/mcp/`**: the tools `list_tasks`, `add_task`, `update_task`, `complete_task`, `read_note` and `write_note`, plus agent instructions. Each request is served statelessly, for both 2025-era and 2026-07-28 clients.

**Device sync** (`src/sync/`): the quickbox apps keep a local Markdown mirror.
- `GET /mcp/sync/changes?cursor=N` returns files changed after version N.
- `POST /mcp/sync/push` replays their offline edits as idempotent ops: `add`, `update`, `delete`, `insertLine`, `importFile`.
- Only the first-party app client may use it. Its OAuth client is created once and published at `GET /app/config`. Agent tokens get `403` there.

Agents never write their own `by:`. The server sets it from the OAuth client's registered name.

### Sign-in notes

- **Email codes** are 6 digits and stored hashed. They expire after 10 minutes, allow 5 attempts, and are limited to 1 send per minute and 5 per hour per address. They are sent through Resend.
- **Apple** returns its result with a cross-site `form_post`, which carries no `SameSite=Lax` cookies. `/auth/apple/callback` therefore answers with a small page that re-submits the result to `/auth/apple/complete` on our own origin. That brings back the cookie that binds the flow to the browser. The identity token is verified against Apple's JWKS, including `iss`, `aud`, `exp` and `nonce`.

## Develop

```bash
npm ci
cp .dev.vars.example .dev.vars   # email codes are printed to the console
npm run dev                      # MCP endpoint: http://localhost:8787/mcp
npm test                         # domain, fixtures, SQL, accounts, Apple, MCP (both protocol eras)
npm run typecheck
```

## Deploy (not done yet)

1. Set `PUBLIC_URL` in `wrangler.jsonc` to the production origin.
2. `wrangler deploy`. `OAUTH_KV` has no id in `wrangler.jsonc`. Recent Wrangler versions create it on deploy; otherwise run `wrangler kv namespace create OAUTH_KV` and add the id.
3. Set these secrets with `wrangler secret put`:
   - `RESEND_API_KEY` and `EMAIL_FROM` (from a verified domain).
   - `APPLE_SERVICES_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY`. The Services ID needs `<PUBLIC_URL>/auth/apple/callback` as a return URL.
4. Add `<PUBLIC_URL>/mcp` as a custom connector in claude.ai.

Account management is first-party only: `GET /mcp/account`, `DELETE /mcp/account/apps/{grantId}` and `POST /mcp/account/delete` (with `{"confirm":"DELETE"}`). The Mac app exposes all three in Settings.

When Sign in with Apple goes live, account deletion must also revoke the user's Apple token (App Store guideline 5.1.1(v)). That requires keeping Apple's refresh token at sign-in, which is not done yet.
