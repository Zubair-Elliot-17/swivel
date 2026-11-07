#!/bin/bash
# check-app.sh sign <Swivel.app>: hardened runtime, only the apple-events entitlement, strict verify, Swivel Dev DR.
# check-app.sh bundle <Swivel.app>: version, icon, copyright, Credits.rtf and the icon read-back.
# Prints one FAIL line per failed check; exits non-zero if any failed. Used by qa.sh and release.sh.
set -uo pipefail
mode=$1 app=$2
bad=0
no() { echo "FAIL $1"; bad=1; }
case $mode in
  sign)
    info=$(codesign -dvv "$app" 2>&1)
    [[ "$info" =~ flags=0x[0-9a-f]+\([a-z,]*runtime ]] || no "no hardened runtime flag"
    ents=$(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -convert json -o - - 2>/dev/null)
    [ "$ents" = '{"com.apple.security.automation.apple-events":true}' ] || no "entitlements are '$ents'"
    codesign --verify --strict --deep "$app" 2>/dev/null || no "codesign --verify --strict --deep"
    # The leaf hash pins the Swivel Dev cert, so Finder access and the login item survive updates.
    if grep -q '^Authority=Swivel Dev$' <<<"$info"; then
      dr='identifier "dev.zubair.swivel" and certificate leaf = H"ec07fa7abf92c18dfab000fd7642fa734ac19e63"'
      [[ "$(codesign -d -r- "$app" 2>&1)" == *"designated => $dr"* ]] || no "designated requirement is not the Swivel Dev one"
    fi
    ;;
  bundle)
    # Info.plist, Resources, credits text (AC 4) and the icon read back from the .icns (AC 5).
    plist="$app/Contents/Info.plist" res="$app/Contents/Resources"
    key() { plutil -extract "$1" raw -o - "$plist" 2>/dev/null; }
    [ "$(key CFBundleShortVersionString)" = 1.0.0 ] || no "CFBundleShortVersionString is '$(key CFBundleShortVersionString)'"
    [[ "$(key CFBundleVersion)" =~ ^[1-9][0-9]*$ ]] || no "CFBundleVersion is '$(key CFBundleVersion)'"
    [ "$(key CFBundleIconFile)" = AppIcon ] || no "CFBundleIconFile is '$(key CFBundleIconFile)'"
    [ "$(key NSHumanReadableCopyright)" = "Copyright © 2026 Zubair Elliot. MIT License." ] || no "NSHumanReadableCopyright is '$(key NSHumanReadableCopyright)'"
    credits=$(textutil -convert txt -stdout "$res/Credits.rtf" 2>/dev/null)
    for f in COPYING PATENTS; do
      [[ -n "$credits" && "$credits" == *"$(cat "$(dirname "$0")/../.build/checkouts/libwebp-Xcode/libwebp/$f")"* ]] || no "Credits.rtf lacks libwebp $f"
    done
    [[ "$credits" == *"Copyright (c) 2010, Google Inc."* ]] || no "Credits.rtf lacks the libwebp copyright line"
    set=$(mktemp -d)/i.iconset
    if iconutil -c iconset "$res/AppIcon.icns" -o "$set" 2>/dev/null; then
      for n in 16 32 128 256 512; do
        for f in "icon_${n}x$n.png:$n" "icon_${n}x$n@2x.png:$((n * 2))"; do
          w=$(sips -g pixelWidth "$set/${f%%:*}" 2>/dev/null | awk '/pixelWidth/ {print $2}')
          [ "$w" = "${f#*:}" ] || no "${f%%:*} is '$w' px, want ${f#*:}"
        done
      done
      [ "$(ls "$set" | wc -l | tr -d ' ')" = 10 ] || no "iconset has $(ls "$set" | wc -l | tr -d ' ') PNGs, want 10"
      # Corner outside the rounded body is clear; the centre (the hub) is opaque.
      a=$(swift -e 'import AppKit; let r = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))!
print(Int(r.colorAt(x: 0, y: 0)!.alphaComponent * 255), Int(r.colorAt(x: 512, y: 512)!.alphaComponent * 255))' "$set/icon_512x512@2x.png" 2>/dev/null)
      [ "$a" = "0 255" ] || no "1024 icon corner/centre alpha is '$a', want '0 255'"
    else
      no "AppIcon.icns missing or unreadable"
    fi
    rm -rf "$(dirname "$set")"
    ;;
  *) no "unknown mode $mode" ;;
esac
exit $bad
