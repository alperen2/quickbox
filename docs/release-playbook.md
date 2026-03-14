# quickbox Release Playbook (Dual Channel)

## Prerequisites

- Apple Developer account configured
- Developer ID signing identity installed
- App Store Connect API key available (`APPSTORE_CONNECT_API_KEY_ID`, `APPSTORE_CONNECT_API_ISSUER_ID`, `APPSTORE_CONNECT_API_PRIVATE_KEY`)
- Sparkle signing keys generated (`generate_keys`)
- `SPARKLE_PUBLIC_ED_KEY` available as a GitHub Actions secret for direct release builds
- `SPARKLE_PRIVATE_ED_KEY` available as a GitHub Actions secret for appcast signing
- Notary profile configured:

```bash
xcrun notarytool store-credentials quickbox-notary --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>
```

## Channel A: Direct distribution (Sparkle + DMG)

### 1) Build archive

```bash
SCHEME=quickbox-Direct scripts/release/build_archive.sh
```

### 2) Export signed app

```bash
TEAM_ID=<TEAM_ID> scripts/release/export_app.sh
```

### 3) Notarize + staple

```bash
NOTARY_PROFILE=quickbox-notary scripts/release/notarize_and_staple.sh
```

### 4) Build DMG + checksum

```bash
scripts/release/build_dmg.sh
```

### 5) Publish appcast

```bash
VERSION=1.0.0 BUILD=1 DOWNLOAD_URL=https://github.com/alperen2/quickbox/releases/download/v1.0.0/quickbox.dmg REQUIRE_SPARKLE_SIGNATURE=1 SPARKLE_PRIVATE_ED_KEY='<private-key>' scripts/release/publish_appcast.sh
```

`publish_appcast.sh` locates Sparkle's `sign_update` binary automatically after a build. The direct release workflow generates both `appcast.xml` and `appcast-beta.xml` as draft release assets. `publish_appcast.yml` publishes those feeds to GitHub Pages only after the GitHub release itself is published, so live users never see a draft-only download URL.

### 6) GitHub release

- Upload `.dmg` and `.sha256`
- Attach release notes
- Publish the draft release only when the App Store build is approved and ready to ship
- Verify download and update flow on clean machine

## Channel B: App Store distribution

### 1) Build App Store archive

```bash
SCHEME=quickbox-AppStore ARCHIVE_PATH=build/release/quickbox-appstore.xcarchive scripts/release/build_archive.sh
```

### 2) Export App Store package

```bash
TEAM_ID=<TEAM_ID> ARCHIVE_PATH=build/release/quickbox-appstore.xcarchive EXPORT_PATH=build/release/export-appstore scripts/release/export_appstore.sh
```

### 3) Upload to App Store Connect

`release_appstore.yml` workflow uploads the generated `.pkg` using App Store Connect API key credentials.

### 4) Submission readiness checklist

See [`docs/appstore-submission-checklist.md`](appstore-submission-checklist.md).
Review notes template: [`docs/appstore-review-notes.md`](appstore-review-notes.md).

## Rollback

- Repoint appcast to last known good version
- Publish patch release with fix notes
