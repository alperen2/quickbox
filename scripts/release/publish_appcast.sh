#!/usr/bin/env bash
set -euo pipefail

VERSION=${VERSION:-}
BUILD=${BUILD:-}
DOWNLOAD_URL=${DOWNLOAD_URL:-}
DMG_PATH=${DMG_PATH:-build/release/quickbox.dmg}
APPCAST_PATH=${APPCAST_PATH:-build/release/appcast.xml}
RELEASE_NOTES_URL=${RELEASE_NOTES_URL:-}
SIGN_UPDATE_BIN=${SIGN_UPDATE_BIN:-}
SPARKLE_PRIVATE_ED_KEY=${SPARKLE_PRIVATE_ED_KEY:-}
REQUIRE_SPARKLE_SIGNATURE=${REQUIRE_SPARKLE_SIGNATURE:-0}

if [[ -z "$VERSION" || -z "$BUILD" || -z "$DOWNLOAD_URL" ]]; then
  echo "VERSION, BUILD and DOWNLOAD_URL are required." >&2
  exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH" >&2
  exit 1
fi

LENGTH=$(stat -f "%z" "$DMG_PATH")
PUB_DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S GMT")
SIGNATURE=""

resolve_sign_update() {
  if [[ -n "$SIGN_UPDATE_BIN" ]]; then
    if [[ ! -x "$SIGN_UPDATE_BIN" ]]; then
      echo "SIGN_UPDATE_BIN is not executable: $SIGN_UPDATE_BIN" >&2
      exit 1
    fi
    echo "$SIGN_UPDATE_BIN"
    return 0
  fi

  "$(dirname "$0")/find_sign_update.sh"
}

if sign_update_bin=$(resolve_sign_update 2>/dev/null); then
  if [[ -n "$SPARKLE_PRIVATE_ED_KEY" ]]; then
    SIGNATURE=$(printf '%s\n' "$SPARKLE_PRIVATE_ED_KEY" | "$sign_update_bin" --ed-key-file - -p "$DMG_PATH")
  else
    SIGNATURE=$("$sign_update_bin" -p "$DMG_PATH")
  fi
fi

if [[ "$REQUIRE_SPARKLE_SIGNATURE" == "1" && -z "$SIGNATURE" ]]; then
  echo "Unable to produce Sparkle signature for $DMG_PATH." >&2
  exit 1
fi

mkdir -p "$(dirname "$APPCAST_PATH")"

cat > "$APPCAST_PATH" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
  xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
  xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>quickbox Updates</title>
    <link>https://github.com/alperen2/quickbox/releases</link>
    <description>quickbox public beta updates</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url="${DOWNLOAD_URL}"
        sparkle:version="${BUILD}"
        sparkle:shortVersionString="${VERSION}"
        length="${LENGTH}"
        type="application/octet-stream"$( [[ -n "$SIGNATURE" ]] && printf '\n        sparkle:edSignature="%s"' "$SIGNATURE" ) />
      $( [[ -n "$RELEASE_NOTES_URL" ]] && printf '<sparkle:releaseNotesLink>%s</sparkle:releaseNotesLink>' "$RELEASE_NOTES_URL" )
    </item>
  </channel>
</rss>
XML

echo "Appcast generated at: $APPCAST_PATH"
