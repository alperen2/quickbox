# quickbox Release Playbook (App Store)

## Prerequisites

- Apple Developer account configured
- App Store Connect API key available (`APPSTORE_CONNECT_API_KEY_ID`, `APPSTORE_CONNECT_API_ISSUER_ID`, `APPSTORE_CONNECT_API_PRIVATE_KEY`)
- Notary profile configured:

```bash
xcrun notarytool store-credentials quickbox-notary --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>
```

## App Store distribution

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
