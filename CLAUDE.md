# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

quickbox is a minimalist macOS (14+) menu bar + Spotlight-style capture app. Captured thoughts are written as Markdown task lines into plain `.md` files in a user-chosen folder. Scope is intentionally limited to **capture + light triage** — avoid features that push it toward a full task manager.

## Commands

Schemes are `quickbox-Direct` and `quickbox-AppStore` (README/CONTRIBUTING mention a `quickbox` scheme, which no longer exists).

```bash
# Unit tests (same invocation as CI)
xcodebuild test -project quickbox.xcodeproj -scheme quickbox-AppStore \
  -destination 'platform=macOS,arch=arm64' -only-testing:quickboxTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM=""

# Single test (Swift Testing: Target/Suite/function)
xcodebuild test -project quickbox.xcodeproj -scheme quickbox-AppStore -destination 'platform=macOS' \
  -only-testing:quickboxTests/quickboxTests/<testName>

# QuickboxCore package tests (parser, analyzer, dates, golden fixtures). Fast, no Xcode project needed
swift test --package-path Packages/QuickboxCore
swift test --package-path Packages/QuickboxCore --filter InboxParserTests

# UI smoke test run in CI
  -only-testing:quickboxUITests/testAutocompleteSupportsMouseSelectionForTagAndProject

# Cloud MCP server (Cloudflare Workers, TypeScript, in cloud/)
cd cloud && npm ci && npm test && npm run typecheck   # npm run dev needs cloud/.dev.vars (see .dev.vars.example)

# Docs (VitePress, source in docs/)
npm install && npm run docs:dev   # docs:build is checked in CI
```

CI (`.github/workflows/ci.yml`) **fails on any Swift compiler warning** (it greps the unit test and `swift test` logs for `.swift:N:N: warning:`), so keep builds warning-free. Release scripts live in `scripts/release/` (archive → export `.pkg` → upload); see `docs/release-playbook.md`.

Commit style: `feat:`, `fix:`, `docs:`, `chore:`, `test:`.

## Build targets

- `quickbox` (bundle `alperen.quickbox`, direct distribution) and `quickboxAppStore` (bundle `alperen.quickbox.appstore`, product name "Quickbox Capture") compile **the same `quickbox/` folder** (file-system synchronized groups, so new files are picked up automatically). Each has its own entitlements file.
- There are no compile-time flags that tell the two apart. Runtime branching uses the bundle ID. For example, `StorageAccessManager` requires a security-scoped bookmark folder only in the App Store build; the direct build falls back to `fallbackStoragePath`.
- App targets use `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` with Swift 5 language mode. Test targets don't use that setting, and they host `quickbox.app`.
- Both app targets link the local SwiftPM package **`Packages/QuickboxCore`**, which holds platform-independent logic: `InboxItem`, `InboxParser`, `CaptureDraftAnalyzer`, the date resolvers, `TaskIdentifier`, `TaskHandoff`, and the sync wire models. It is meant to be shared with future iOS and cloud clients, so keep it free of UI, file I/O, and app types (`AppPreferences`, `FormatSettings`). Its API is `public`, and app files need `import QuickboxCore`. It uses Swift 5 language mode with `BareSlashRegexLiterals`. Its types are nonisolated, not MainActor. The package is wired into `project.pbxproj` by hand (`XCLocalSwiftPackageReference`).
- Build/version numbers are set per target in `project.pbxproj` (`CURRENT_PROJECT_VERSION`, `MARKETING_VERSION`).

## Architecture

**Composition root:** `quickboxApp` → `AppDelegate.applicationDidFinishLaunching` creates one `AppState` and wires up `CaptureWindowController` (the Spotlight-style panel), `SettingsWindowController`, and `MenuBarController` (a popover hosting `MenuBarDashboardView`). Controllers talk to each other through closures on `AppState` (`onCaptureRequested`, `onSettingsRequested`, `onCaptureSaved`), not through direct references. The app runs as `.accessory` (no Dock icon).

**`AppState`** (`@MainActor ObservableObject`) is the single view model for every surface: draft text, the selected inbox date, items, calendar indicators, and preferences. Dependencies are injected through protocols (`InboxWriting`, `InboxRepositorying`, `CrashReporting`, `StorageResolving`), with defaults created in `init`. Tests pass `registerHotkeyOnInit: false` / `loadInboxOnInit: false` along with fakes.

**Storage pipeline (`Core/Storage` + `QuickboxCore`):** there is no database. The Markdown files are the source of truth.
- Line format: `- [ ] HH:mm text !1 @Project #tag due:YYYY-MM-DD key:value date:YYYY-MM-DD id:xxxxxxxx` (parsed by the `InboxParser.taskPattern` regex). New lines get a stable `id:` (`TaskIdentifier`), which is exposed as `InboxItem.taskID`, not as metadata. Item IDs are `"<file>#id:<taskID>"`, so mutations survive lines shifting. Legacy lines without `id:` fall back to `"<file>#<lineIndex>#<rawLine>"`. Any code that rebuilds a line (writer, repository edit) must carry `id:` over.
- Human↔agent handoff uses ordinary metadata keys defined in `TaskHandoff.swift`: `for:` (me/agent/name), `by:` (author, absent = user), `from:` (origin task id), `ref:` (related note path).
- `fixtures/task-lines.json` (parser) and `fixtures/due-dates.json` (natural-language dates) are language-neutral golden cases. Both the Swift package and `cloud/` run them. When you change the syntax or the date rules, add a case there and update **both** implementations.
- **Routing:** `InboxWriter.appendEntry` parses the draft. A task with `@Project` is appended to `<Project>.md` along with a hidden `date:` tag. Other tasks go to the daily file (named via `FormatSettings`, default `YYYY-MM-DD.md`) for the resolved `due:` date, or for today.
- **Reading:** for a given day, `InboxRepository.load(on:)` reads that day's file and also scans every other `.md` file for lines carrying the matching `date:` tag. It hides items whose `defer:` date is in the future.
- Natural-language dates are resolved **only** inside `due:`, `defer:`, and `start:` values (`DueDateResolver`; `DeferDateResolver` delegates to it). `CaptureDraftAnalyzer` generates live token previews for the capture UI using the same token rules as the parser. Keep the parser, analyzer, and writer consistent when you change the syntax.
- All file I/O is serialized on `InboxStorageQueue.shared`. It always follows the resolve-then-`stopAccess` pattern (`storageResolver.resolvedBaseURL()` + `defer stopAccess`) needed for security-scoped access.
- `IndexManager.shared` scans the storage folder for known `#tags` and projects (non-date filenames) to feed autocomplete. `inject` updates it incrementally after each capture.

**Settings:** `AppPreferences` (Codable) is persisted as JSON in UserDefaults under `quickbox.preferences` by `SettingsStore`. If decoding fails, it silently falls back to `.default`. When you add fields, make sure decoding stays backward compatible.

**Observability:** `CrashReporter` is opt-in (consent comes from preferences). It records only non-fatal errors with sanitized context and must never include task text.

**UI testing hooks:** the `--ui-testing` launch argument turns off hotkey registration, uses the `.regular` activation policy, and seeds `IndexManager`. Adding `--ui-test-host-window` also hosts `CaptureView` in a normal window so XCUITest can drive it.

**Cloud sync in the app (`quickbox/Core/Cloud/`), optional:**
- `AppState` wraps the local `InboxWriter` and `InboxRepository` in `SyncingInboxWriter` and `SyncingInboxRepository`, but only when `enableCloudSync` is on. `AppDelegate` turns it off for UI tests and when hosting unit tests. The wrappers keep writing files locally, then record `SyncOp`s into the persisted `SyncOutbox`. Captures get an explicit `id:` so the local and cloud lines share it.
- `SyncEngine` runs one pass:
  - First sync: import local-only files; where both sides have a file and it differs, the cloud wins and the local copy goes to `quickbox-conflicts/`.
  - Push the outbox in batches. Ops the server rejects are dropped.
  - Pull changes since the cursor. A file edited outside quickbox gets a conflict copy before it is overwritten.
- `CloudSyncController` (Settings → quickbox Cloud) owns sign-in and the schedule (every 60 s, on app activation, and 2 s after a local change). Sign-in is `CloudAuthenticator`: OAuth + PKCE via `ASWebAuthenticationSession`, tokens in the Keychain, client id from `GET /app/config`.
- While connected, file naming is fixed to the cloud's format (`yyyy-MM-dd.md`, `HH:mm`, no prefix).
- The op types (`SyncOp`, `PushRequest`, `ChangesResponse`) live in `QuickboxCore` (`SyncModels.swift`), where iOS can reuse them. Their JSON is pinned by `fixtures/sync-push-request.json`, which both the package tests and the server's zod schema check.
- App-hosted unit tests must not read files under `~/Documents`, the repository included. An unsigned host app triggers a macOS privacy prompt and the test hangs. Put repository-fixture tests in the package instead.

**Cloud (`cloud/`):** a remote MCP server on Cloudflare Workers that exposes a user's inbox to AI agents. See `cloud/README.md`.
- **Keep Cloudflare at the edges, so the server can move to self-hosting.**
  - Only these may touch Cloudflare-specific APIs: `src/store/` (Durable Objects), `src/accounts/accountDirectory.ts`, `src/oauth.ts` and `src/auth/` (the OAuth provider), and `src/index.ts`. That includes `cloudflare:workers`, `DurableObject`, KV and `env` bindings.
  - Domain and protocol code must stay runtime-agnostic and run under plain Node (the tests prove this). It receives storage through interfaces: `FileStore` and `Sql` (the `SqlStorage` subset). This covers `src/core`, `src/inbox`, `src/sync` (except `api.ts`), `src/accounts/accounts.ts` and `src/mcp`.
  - New features should follow the same shape: logic behind an interface, plus a thin Durable Object adapter.
- `cloud/src/core` is a TypeScript port of `QuickboxCore` (parser, line formatting, dates, ids) and must mirror it.
- `Inbox` (in `cloud/src/inbox`) mirrors the app's routing, day view and edit rules on top of a synchronous `FileStore`.
- The `InboxStore` Durable Object (one per user, SQLite, one row per `.md` file) is the single writer.
- Expected errors cross the Durable Object RPC boundary as `InboxResult` values, not exceptions.
- The server derives `by:` from the OAuth client's name (token props), never from tool input.
- Auth: `@cloudflare/workers-oauth-provider` (`src/oauth.ts`) protects `/mcp`. `/authorize` is a consent page offering Sign in with Apple and email codes (`src/auth/`). The global `AccountDirectory` Durable Object owns users and codes.
- Apple's `form_post` callback is bridged to a same-site GET, because the flow's binding cookie is `SameSite=Lax`.
- Device sync lives under `/mcp/sync/*` (it shares the MCP resource's tokens):
  - `GET changes?cursor=N` returns versioned files.
  - `POST push` takes idempotent op batches: `add`, `update`, `delete`, `insertLine`, `importFile`.
  - Only the first-party app client may call it, and it writes as the user.
- Account management lives under `/mcp/account*` (`src/account/api.ts`) and is first-party only:
  - It lists grants as "connected apps" and can revoke one.
  - `POST /mcp/account/delete` with `{"confirm":"DELETE"}` deletes the account in this order: revoke all grants, wipe the user's `InboxStore` storage, then remove the directory entry.
  - The Mac's "Disconnect this Mac" also revokes its own grant.
- If you change what the cloud stores, update `docs/privacy.md` and `quickbox/PrivacyInfo.xcprivacy`.
- Local dev: `DEV_LOG_EMAIL_CODES=true` prints codes to the console. Tests run the Durable Object SQL on `node:sqlite` (`test/sqlite.ts`).
