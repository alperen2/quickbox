#!/usr/bin/env bash
set -euo pipefail

SCHEME=${SCHEME:-quickbox-Direct}
PROJECT=${PROJECT:-quickbox.xcodeproj}
CONFIGURATION=${CONFIGURATION:-Release}
ARCHIVE_PATH=${ARCHIVE_PATH:-build/release/quickbox.xcarchive}
REQUIRE_SPARKLE_PUBLIC_ED_KEY=${REQUIRE_SPARKLE_PUBLIC_ED_KEY:-0}
ALLOW_PROVISIONING_UPDATES=${ALLOW_PROVISIONING_UPDATES:-0}
APPSTORE_AUTH_KEY_PATH=${APPSTORE_AUTH_KEY_PATH:-}
APPSTORE_AUTH_KEY_ID=${APPSTORE_AUTH_KEY_ID:-}
APPSTORE_AUTH_KEY_ISSUER_ID=${APPSTORE_AUTH_KEY_ISSUER_ID:-}

mkdir -p "$(dirname "$ARCHIVE_PATH")"

xcodebuild_args=(
  archive
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=macOS"
  -archivePath "$ARCHIVE_PATH"
)

if [[ "$SCHEME" == "quickbox-Direct" ]]; then
  if [[ -n "${SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
    xcodebuild_args+=("SPARKLE_PUBLIC_ED_KEY=$SPARKLE_PUBLIC_ED_KEY")
  elif [[ "$REQUIRE_SPARKLE_PUBLIC_ED_KEY" == "1" ]]; then
    echo "SPARKLE_PUBLIC_ED_KEY is required for quickbox-Direct archives." >&2
    exit 1
  fi
fi

if [[ -n "${MARKETING_VERSION:-}" ]]; then
  xcodebuild_args+=("MARKETING_VERSION=$MARKETING_VERSION")
fi

if [[ -n "${CURRENT_PROJECT_VERSION:-}" ]]; then
  xcodebuild_args+=("CURRENT_PROJECT_VERSION=$CURRENT_PROJECT_VERSION")
fi

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

echo "Archive created at: $ARCHIVE_PATH"
