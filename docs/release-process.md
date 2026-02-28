# Release Process

See:

- `docs/release-playbook.md`
- scripts under `scripts/release/`

High-level flow:

1. Build archive
2. Export app
3. Notarize and staple
4. Build DMG + checksum
5. Publish appcast
6. Create GitHub release

## GitHub Actions secrets

Required for release workflow:

- `APPLE_TEAM_ID`
- `APPLE_NOTARY_PROFILE`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
