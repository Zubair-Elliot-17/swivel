#!/bin/bash
# Builds build/Swivel.app from the release binary and signs it ("Swivel Dev" if scripts/dev-cert.sh made it, else ad hoc).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Swivel.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Swivel" "$APP/Contents/MacOS/Swivel"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Swivel</string>
    <key>CFBundleIdentifier</key><string>dev.zubair.swivel</string>
    <key>CFBundleName</key><string>Swivel</string>
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
codesign --force -s "$IDENTITY" "$APP"
echo "Built $APP (signed: $IDENTITY)"
