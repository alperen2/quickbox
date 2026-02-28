#!/usr/bin/env bash
set -euo pipefail

SCHEME=${SCHEME:-quickbox}
PROJECT=${PROJECT:-quickbox.xcodeproj}
CONFIGURATION=${CONFIGURATION:-Release}
ARCHIVE_PATH=${ARCHIVE_PATH:-build/release/quickbox.xcarchive}

mkdir -p "$(dirname "$ARCHIVE_PATH")"

xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH"

echo "Archive created at: $ARCHIVE_PATH"
