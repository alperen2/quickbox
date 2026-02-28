# quickbox Release Playbook (Public Beta)

## Prerequisites

- Apple Developer account configured
- Developer ID signing identity installed
- Sparkle signing keys generated (`generate_keys`)
- `SPARKLE_PUBLIC_ED_KEY` set in Xcode build settings for `quickbox` target
- Notary profile configured:

```bash
xcrun notarytool store-credentials quickbox-notary --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>
```

## 1) Build archive

```bash
scripts/release/build_archive.sh
```

## 2) Export signed app

```bash
TEAM_ID=<TEAM_ID> scripts/release/export_app.sh
```

## 3) Notarize + staple

```bash
NOTARY_PROFILE=quickbox-notary scripts/release/notarize_and_staple.sh
```

## 4) Build DMG + checksum

```bash
scripts/release/build_dmg.sh
```

## 5) Publish appcast

```bash
VERSION=1.0.0-beta.1 BUILD=1 DOWNLOAD_URL=https://github.com/alperen2/quickbox/releases/download/v1.0.0-beta.1/quickbox.dmg scripts/release/publish_appcast.sh
```

Release workflow now generates both `appcast.xml` and `appcast-beta.xml`. Host both feeds on GitHub Pages.

## 6) GitHub release

- Upload `.dmg` and `.sha256`
- Attach release notes
- Verify download and update flow on clean machine

## Rollback

- Repoint appcast to last known good version
- Publish patch release with fix notes
