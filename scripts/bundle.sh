#!/bin/bash
# Builds build/Swivel.app from the release binary and signs it ("Swivel Dev" if scripts/dev-cert.sh made it, else ad hoc).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Swivel.app
rm -rf "$APP"
VERSION=1.0.0
BUILD=$(git rev-list --count HEAD)  # monotonic on main
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Swivel" "$APP/Contents/MacOS/Swivel"
cp assets/AppIcon.icns assets/Credits.rtf "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Swivel</string>
    <key>CFBundleIdentifier</key><string>dev.zubair.swivel</string>
    <key>CFBundleName</key><string>Swivel</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Zubair Elliot. MIT License.</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSAppleEventsUsageDescription</key><string>Swivel reads the files you've selected in Finder so it can convert them.</string>
</dict>
</plist>
PLIST
# A stable identity keeps privacy grants across rebuilds; ad hoc changes every build.
IDENTITY=-
security find-identity -p codesigning | grep -q '"Swivel Dev"' && IDENTITY="Swivel Dev"
# Hardened runtime blocks Apple events unless entitled; without it the Finder tap fails silently (-1743).
codesign --force --options runtime --entitlements assets/Swivel.entitlements -s "$IDENTITY" "$APP"
echo "Built $APP $VERSION ($BUILD) (signed: $IDENTITY)"
