#!/usr/bin/env bash
set -euo pipefail

VERSION=${VERSION:-}
BUILD=${BUILD:-}
DOWNLOAD_URL=${DOWNLOAD_URL:-}
DMG_PATH=${DMG_PATH:-build/release/quickbox.dmg}
APPCAST_PATH=${APPCAST_PATH:-build/release/appcast.xml}
RELEASE_NOTES_URL=${RELEASE_NOTES_URL:-}

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

if command -v sign_update >/dev/null 2>&1; then
  SIGNATURE=$(sign_update "$DMG_PATH" | awk '/sparkle:edSignature/ {print $2}')
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
