#!/bin/bash
# Builds CallBridge.app — a double-clickable macOS app bundle around the
# SwiftPM binary. Output: build/CallBridge.app
#
# APP_VERSION overrides the bundle version (CI passes the tag; update tests
# use it to stage a newer build):
#   APP_VERSION=0.3.0 ./make_app.sh release
set -euo pipefail
cd "$(dirname "$0")"

CONFIGURATION="${1:-release}"
APP_VERSION="${APP_VERSION:-0.2.3}"
REPO_SLUG="thepushkaraj/CallBridge"

echo "==> swift build -c $CONFIGURATION"
swift build -c "$CONFIGURATION"

BINARY=".build/$CONFIGURATION/callbridge"
APP="build/CallBridge.app"
CONTENTS="$APP/Contents"

echo "==> Assembling $APP"
rm -rf build/CallBridge.app
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Frameworks" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/CallBridge"
cp AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"

# Point dyld at Contents/Frameworks (SwiftPM doesn't add this rpath; Xcode
# does it for you). Kept for any future bundled frameworks.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/CallBridge" 2>/dev/null || true

cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>CallBridge</string>
    <key>CFBundleDisplayName</key>
    <string>CallBridge</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.thepushkaraj.callbridge.mac</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleExecutable</key>
    <string>CallBridge</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License</string>
</dict>
</plist>
PLIST

# Ad-hoc signature keeps notifications (UNUserNotificationCenter) working.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
codesign --verify --deep "$APP" >/dev/null 2>&1 && echo "==> signature valid"

echo "==> Done: $APP"
echo "    open $APP"
