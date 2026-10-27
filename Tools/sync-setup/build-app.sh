#!/bin/bash
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Copyright 2026 Zack Bleach. See LICENSE.md.
# Builds "12 Step Sync.app" into Tools/sync-setup/dist/.
#
#   ./build-app.sh                  ad-hoc signed (runs on this Mac)
#   SIGN_ID="Developer ID Application: …" ./build-app.sh
#                                   signed for distribution; then notarize the zip with notarytool
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/12 Step Sync.app"
VERSION="1.0"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/SyncSetup"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/12 Step Sync"

# The icon is drawn by the app itself (AppIconView).
ICONSET="$(mktemp -d)/AppIcon.iconset"
"$APP/Contents/MacOS/12 Step Sync" --render-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>12 Step Sync</string>
    <key>CFBundleDisplayName</key><string>12 Step Sync</string>
    <key>CFBundleIdentifier</key><string>com.zackbleach.TwelveStepSync</string>
    <key>CFBundleExecutable</key><string>12 Step Sync</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Zack Bleach. Free for noncommercial use (PolyForm Noncommercial 1.0.0).</string>
</dict>
</plist>
PLIST

if [[ -n "${SIGN_ID:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
    codesign --force --sign - "$APP"
fi
echo "Built $APP"
