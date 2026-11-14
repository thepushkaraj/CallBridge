#!/bin/bash
# Generates a Sparkle appcast for one release. CI uploads the output as an
# asset named `appcast.xml` on the release; clients poll the stable URL:
#   https://github.com/thepushkaraj/CallBridge/releases/latest/download/appcast.xml
#
# Usage: make_appcast.sh <version> <download-url> <zip-path>
#   version      release version without the leading v (e.g. 0.3.0)
#   download-url the URL the zip will be published at
#   zip-path     local path of the built zip (for file size)
set -euo pipefail

VERSION="${1:?version required}"
URL="${2:?download-url required}"
ZIP="${3:?zip-path required}"

LENGTH=$(stat -f%z "$ZIP")
PUBDATE=$(date -u "+%a, %d %b %Y %H:%M:%S GMT")

cat << EOF
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
  <channel>
    <title>CallBridge</title>
    <link>https://github.com/thepushkaraj/CallBridge</link>
    <description>CallBridge releases</description>
    <language>en</language>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>
      <enclosure url="$URL" length="$LENGTH" type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF
