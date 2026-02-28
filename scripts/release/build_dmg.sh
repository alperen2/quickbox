#!/usr/bin/env bash
set -euo pipefail

APP_PATH=${APP_PATH:-build/release/export/quickbox.app}
DMG_PATH=${DMG_PATH:-build/release/quickbox.dmg}
VOLUME_NAME=${VOLUME_NAME:-quickbox}

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  exit 1
fi

TMP_DIR=$(mktemp -d /tmp/quickbox-dmg.XXXXXX)
cp -R "$APP_PATH" "$TMP_DIR/"

mkdir -p "$(dirname "$DMG_PATH")"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$TMP_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"

echo "DMG created at: $DMG_PATH"
