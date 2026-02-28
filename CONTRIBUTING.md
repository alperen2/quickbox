# Contributing to quickbox

Thanks for contributing.

## Development Setup

1. Install Xcode 16+
2. Clone repo
3. Open `quickbox.xcodeproj`
4. Run `quickbox` scheme

## Test Matrix

Run unit tests before every PR:

```bash
xcodebuild test -project quickbox.xcodeproj -scheme quickbox -destination 'platform=macOS' -only-testing:quickboxTests
```

## Design Constraints

quickbox is intentionally minimal:

- Capture speed first
- Low visual/interaction noise
- Avoid feature creep into full task-manager workflows

For UX changes, include before/after screenshots or recordings.

## Pull Request Checklist

- [ ] Scope is small and focused
- [ ] Tests pass locally
- [ ] No unrelated file changes
- [ ] Docs updated when behavior changes
- [ ] Screenshots attached for UI updates

## Commit Style

Recommended:

- `feat: ...`
- `fix: ...`
- `docs: ...`
- `chore: ...`
- `test: ...`

## Issue First Policy

For larger changes, open an issue first to align on direction.
