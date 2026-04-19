# Release Process

See:

- `docs/release-playbook.md`
- scripts under `scripts/release/`

High-level flow:

1. Build App Store archive
2. Export `.pkg` for App Store Connect
3. Upload with `release_appstore.yml`
4. Complete metadata, screenshots, and review notes in App Store Connect
5. Submit for review and release manually after approval

## GitHub Actions secrets

Required for App Store workflow:

- `APPLE_TEAM_ID`
- `APPSTORE_CONNECT_API_KEY_ID`
- `APPSTORE_CONNECT_API_ISSUER_ID`
- `APPSTORE_CONNECT_API_PRIVATE_KEY`

Optional for local notarization-related checks:

- `APPLE_NOTARY_PROFILE`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

## GitHub Pages

- `docs.yml` publishes the VitePress site to the root of `gh-pages`
- The published site is used for support and privacy URLs referenced in App Store Connect
