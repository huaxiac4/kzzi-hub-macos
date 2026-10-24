#!/bin/bash
# Build KZZI HUB.app from source.
# Requires Xcode 26+ (for the SwiftUI Liquid Glass APIs) and macOS 26+.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cd native
swift build -c release --disable-sandbox
cd ..

APP="KZZI HUB.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp native/.build/release/KZZIHub "$APP/Contents/MacOS/KZZI HUB"
cp -R native/.build/release/KZZIHub_KZZIHub.bundle "$APP/Contents/Resources/"

if [ -f assets/appicon.icns ]; then
  cp assets/appicon.icns "$APP/Contents/Resources/"
  ICON_KEY='<key>CFBundleIconFile</key><string>appicon</string>'
else
  ICON_KEY=''
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>KZZI HUB</string>
  <key>CFBundleIdentifier</key><string>com.kzzi.hub.mac</string>
  <key>CFBundleVersion</key><string>1.0.0</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>KZZI HUB</string>
  $ICON_KEY
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

xattr -cr "$APP" || true
codesign --force --deep -s - --identifier com.kzzi.hub.mac "$APP" || true
echo "Built: $APP"
