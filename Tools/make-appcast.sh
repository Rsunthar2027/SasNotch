#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 SasNotch contributors

# Writes dist/appcast.xml for one release: the Sparkle feed each release
# carries, so releases/latest/download/appcast.xml always describes the
# newest version. The update archive is signed with the EdDSA private key.
#
#   SPARKLE_ED_PRIVATE_KEY='…' ./Tools/make-appcast.sh 1.2.3 owner/SasNotch
#
# The key comes from the environment (the CI secret) or, when unset, from
# the login keychain entry `generate_keys --account sasnotch` created.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: make-appcast.sh <version> <owner/repo>}"
REPOSITORY="${2:?usage: make-appcast.sh <version> <owner/repo>}"
ARCHIVE="dist/SasNotch.zip"
SPARKLE_BIN="$(ls -d .vendor/Sparkle-*/bin 2>/dev/null | tail -1)"
[[ -f "$ARCHIVE" ]] || { echo "✗ $ARCHIVE not found — run Tools/make-zip.sh first" >&2; exit 1; }
[[ -x "$SPARKLE_BIN/sign_update" ]] || { echo "✗ Sparkle tools not found — run ./build.sh first" >&2; exit 1; }
[[ "$VERSION" =~ '^([0-9]+)\.([0-9]+)\.([0-9]+)$' ]] || { echo "✗ version must look like 1.2.3" >&2; exit 1; }
BUILD_NUMBER=$(( ${match[1]} * 10000 + ${match[2]} * 100 + ${match[3]} ))

if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
    KEY_FILE="$(mktemp)"
    trap 'rm -f "$KEY_FILE"' EXIT
    printf '%s' "$SPARKLE_ED_PRIVATE_KEY" > "$KEY_FILE"
    SIGNATURE="$("$SPARKLE_BIN/sign_update" --ed-key-file "$KEY_FILE" "$ARCHIVE")"
else
    SIGNATURE="$("$SPARKLE_BIN/sign_update" --account sasnotch "$ARCHIVE")"
fi
# sign_update prints: sparkle:edSignature="…" length="…"
[[ "$SIGNATURE" == *'sparkle:edSignature="'* ]] || { echo "✗ sign_update failed: $SIGNATURE" >&2; exit 1; }

PUBDATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>SasNotch</title>
    <link>https://github.com/$REPOSITORY</link>
    <description>SasNotch updates</description>
    <language>en</language>
    <item>
      <title>SasNotch $VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$REPOSITORY/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/$REPOSITORY/releases/download/v$VERSION/SasNotch.zip" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
echo "✓ Appcast ready: dist/appcast.xml ($VERSION, build $BUILD_NUMBER)"
