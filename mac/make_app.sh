#!/bin/bash
# Builds CallBridge.app — a double-clickable macOS app bundle around the
# SwiftPM binary. Output: build/CallBridge.app
set -euo pipefail
cd "$(dirname "$0")"

CONFIGURATION="${1:-release}"

echo "==> swift build -c $CONFIGURATION"
swift build -c "$CONFIGURATION"

BINARY=".build/$CONFIGURATION/callbridge"
APP="build/CallBridge.app"
CONTENTS="$APP/Contents"

echo "==> Assembling $APP"
rm -rf build/CallBridge.app
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/CallBridge"
cp AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"

cat > "$CONTENTS/Info.plist" << 'PLIST'
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
    <string>0.2.2</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.2</string>
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

echo "==> Done: $APP"
echo "    open $APP"
