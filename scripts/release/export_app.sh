#!/usr/bin/env bash
set -euo pipefail

ARCHIVE_PATH=${ARCHIVE_PATH:-build/release/quickbox.xcarchive}
EXPORT_PATH=${EXPORT_PATH:-build/release/export}
TEAM_ID=${TEAM_ID:-}

if [[ ! -d "$ARCHIVE_PATH" ]]; then
  echo "Archive not found: $ARCHIVE_PATH" >&2
  exit 1
fi

if [[ -z "$TEAM_ID" ]]; then
  echo "TEAM_ID is required for export (Developer ID team)." >&2
  exit 1
fi

mkdir -p "$EXPORT_PATH"

EXPORT_OPTIONS_FILE=$(mktemp /tmp/quickbox-export-options.XXXXXX.plist)
cat > "$EXPORT_OPTIONS_FILE" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_FILE"

echo "Exported app at: $EXPORT_PATH"
