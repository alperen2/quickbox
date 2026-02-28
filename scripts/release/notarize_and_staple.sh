#!/usr/bin/env bash
set -euo pipefail

APP_PATH=${APP_PATH:-build/release/export/quickbox.app}
NOTARY_PROFILE=${NOTARY_PROFILE:-}
ZIP_PATH=${ZIP_PATH:-build/release/quickbox-notarize.zip}

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  exit 1
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "NOTARY_PROFILE is required. Configure with xcrun notarytool store-credentials." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"

spctl --assess --type execute --verbose "$APP_PATH"

echo "Notarization and stapling complete: $APP_PATH"
