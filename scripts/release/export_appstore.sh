#!/usr/bin/env bash
set -euo pipefail

ARCHIVE_PATH=${ARCHIVE_PATH:-build/release/quickbox-appstore.xcarchive}
EXPORT_PATH=${EXPORT_PATH:-build/release/export-appstore}
TEAM_ID=${TEAM_ID:-}
ALLOW_PROVISIONING_UPDATES=${ALLOW_PROVISIONING_UPDATES:-0}
APPSTORE_AUTH_KEY_PATH=${APPSTORE_AUTH_KEY_PATH:-}
APPSTORE_AUTH_KEY_ID=${APPSTORE_AUTH_KEY_ID:-}
APPSTORE_AUTH_KEY_ISSUER_ID=${APPSTORE_AUTH_KEY_ISSUER_ID:-}

if [[ ! -d "$ARCHIVE_PATH" ]]; then
  echo "Archive not found: $ARCHIVE_PATH" >&2
  exit 1
fi

if [[ -z "$TEAM_ID" ]]; then
  echo "TEAM_ID is required for App Store export." >&2
  exit 1
fi

mkdir -p "$EXPORT_PATH"

EXPORT_OPTIONS_FILE=$(mktemp /tmp/quickbox-appstore-export-options.XXXXXX.plist)
cat > "$EXPORT_OPTIONS_FILE" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
</dict>
</plist>
PLIST

xcodebuild_args=(
  -exportArchive
  -archivePath "$ARCHIVE_PATH"
  -exportPath "$EXPORT_PATH"
  -exportOptionsPlist "$EXPORT_OPTIONS_FILE"
)

if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
  xcodebuild_args+=(-allowProvisioningUpdates)
fi

if [[ -n "$APPSTORE_AUTH_KEY_PATH" || -n "$APPSTORE_AUTH_KEY_ID" || -n "$APPSTORE_AUTH_KEY_ISSUER_ID" ]]; then
  if [[ -z "$APPSTORE_AUTH_KEY_PATH" || -z "$APPSTORE_AUTH_KEY_ID" || -z "$APPSTORE_AUTH_KEY_ISSUER_ID" ]]; then
    echo "APPSTORE_AUTH_KEY_PATH, APPSTORE_AUTH_KEY_ID, and APPSTORE_AUTH_KEY_ISSUER_ID must all be set together." >&2
    exit 1
  fi
  xcodebuild_args+=(
    -authenticationKeyPath "$APPSTORE_AUTH_KEY_PATH"
    -authenticationKeyID "$APPSTORE_AUTH_KEY_ID"
    -authenticationKeyIssuerID "$APPSTORE_AUTH_KEY_ISSUER_ID"
  )
fi

xcodebuild "${xcodebuild_args[@]}"

echo "Exported App Store package at: $EXPORT_PATH"
