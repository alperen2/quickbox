# quickbox

quickbox is a minimalist macOS menubar + spotlight-style capture app built for fast thought capture with minimal distraction.

## Why

When you are in flow and a thought appears, you should be able to capture it in 1-2 seconds and return to work.

## Current Scope

- Global shortcut to open capture panel
- Daily markdown inbox (`YYYY-MM-DD.md` style)
- Powerful Natural Language Syntax (`@Project`, `!priority`, `due:next friday`, `defer:end of month`, `time:15m`)
- Today list with quick toggle/edit/delete/undo
- Lightweight settings (shortcut, storage, formats)

Natural language date phrases are intentionally parsed only inside `due:`, `defer:`, and `start:` values for deterministic behavior.

quickbox intentionally stays in **capture + light triage** territory, not a full task manager.

## Install (from source)

### Requirements

- macOS 14+
- Xcode 16+

### Run

1. Open `quickbox.xcodeproj` in Xcode
2. Select `quickbox` scheme
3. Build and run

### CLI test

```bash
xcodebuild test -project quickbox.xcodeproj -scheme quickbox-Direct -destination 'platform=macOS' -only-testing:quickboxTests
```

## Production Release

Release scripts are under `scripts/release/`. See:

- `docs/release-playbook.md`
- `docs/release-process.md`
- `docs/appstore-submission-checklist.md`

Direct releases create a draft GitHub release first. Appcasts are published to GitHub Pages only after that draft is manually published, which keeps Sparkle feeds aligned with public release availability.

## Documentation

- Docs source: `docs/`
- Docs framework: VitePress
- Local preview:

```bash
npm install
npm run docs:dev
```

- Published site: [alperen2.github.io/quickbox](https://alperen2.github.io/quickbox/)

## Privacy

quickbox is local-first. Crash diagnostics are opt-in and do not include task text content.

## Contributing

Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening a PR.

## Security

Please read [`SECURITY.md`](SECURITY.md) for vulnerability reporting.

## License

MIT - see [`LICENSE`](LICENSE).
