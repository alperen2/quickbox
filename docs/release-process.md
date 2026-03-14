# Release Process

See:

- `docs/release-playbook.md`
- scripts under `scripts/release/`

High-level flow:

1. Direct channel: tag `vX.Y.Z`, build/sign/notarize DMG, create draft GitHub release, publish GitHub release, then publish appcasts to GitHub Pages
2. App Store channel: archive, export (`app-store`), upload to App Store Connect

## GitHub Actions secrets

Required for release workflow:

- `APPLE_TEAM_ID`
- `APPLE_NOTARY_PROFILE`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `SPARKLE_PUBLIC_ED_KEY`
- `SPARKLE_PRIVATE_ED_KEY`

Required for App Store workflow:

- `APPSTORE_CONNECT_API_KEY_ID`
- `APPSTORE_CONNECT_API_ISSUER_ID`
- `APPSTORE_CONNECT_API_PRIVATE_KEY`

## GitHub Pages

- `docs.yml` publishes the VitePress site to the root of `gh-pages`
- `publish_appcast.yml` preserves the docs site and updates only `appcast.xml` / `appcast-beta.xml`
- Direct update URLs remain:
  - `https://alperen2.github.io/quickbox/appcast.xml`
  - `https://alperen2.github.io/quickbox/appcast-beta.xml`
