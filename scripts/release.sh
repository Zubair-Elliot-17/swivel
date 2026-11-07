#!/bin/bash
# Builds build/Swivel-1.0.0.zip from the exact bundle qa.sh tested, checks it by reading the zip back,
# prints its SHA-256 and tags v1.0.0 (on main only). Never pushes. See docs/development.md.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=1.0.0 TAG=v1.0.0
NAME=Swivel-$VERSION OUT=build/Swivel-$VERSION APP=build/Swivel.app
WEBP=.build/checkouts/libwebp-Xcode/libwebp
die() { echo "release: $1" >&2; exit 1; }

# Refusals come first, so a refused run writes nothing.
[ -z "$(git status --porcelain)" ] || die "working tree is dirty"
# SWIVEL_IDENTITY overrides the lookup (tests use "-" to prove the ad hoc refusal).
IDENTITY=${SWIVEL_IDENTITY:-}
if [ -z "$IDENTITY" ]; then
  IDENTITY=-
  security find-identity -p codesigning | grep -q '"Swivel Dev"' && IDENTITY="Swivel Dev"
fi
[ "$IDENTITY" = "Swivel Dev" ] || die "signing identity is '$IDENTITY', not Swivel Dev (an ad hoc release would lose users' grants on update)"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then die "tag $TAG already exists"; fi

rm -rf "$OUT" "$OUT.zip"
scripts/test.sh >/dev/null 2>&1 || die "scripts/test.sh failed"
scripts/qa.sh || die "scripts/qa.sh failed"  # builds and signs $APP through bundle.sh
# From here on nothing builds or signs: the zip must hold the bundle QA just tested.
cdhash() { codesign -dvvv "$1" 2>&1 | awk -F= '/^CDHash=/ {print $2}'; }
binsha() { shasum -a 256 "$1/Contents/MacOS/Swivel" | cut -d' ' -f1; }
CDHASH=$(cdhash "$APP") BINSHA=$(binsha "$APP")
[ -n "$CDHASH" ] || die "no CDHash for $APP"

# check <folder> <label>: the folder is exactly what users get, and its app is the tested one.
check() {
  local dir=$1 app=$1/Swivel.app
  [ "$(ls -A "$dir" | tr '\n' ' ')" = "LICENSE Swivel.app THIRD_PARTY_NOTICES.md " ] || die "$2: holds $(ls -A "$dir" | tr '\n' ' ')"
  [ -x "$app/Contents/MacOS/Swivel" ] || die "$2: Contents/MacOS/Swivel is not executable"
  scripts/check-app.sh sign "$app" >/dev/null || die "$2: $(scripts/check-app.sh sign "$app" | head -1)"
  scripts/check-app.sh bundle "$app" >/dev/null || die "$2: $(scripts/check-app.sh bundle "$app" | head -1)"
  [[ "$(codesign -dvv "$app" 2>&1)" == *$'\nAuthority=Swivel Dev\n'* ]] || die "$2: not signed by Swivel Dev"
  [ "$(cdhash "$app")" = "$CDHASH" ] || die "$2: CDHash differs from the tested bundle"
  [ "$(binsha "$app")" = "$BINSHA" ] || die "$2: binary differs from the tested bundle"
  [ "$(head -3 "$dir/LICENSE")" = $'MIT License\n\nCopyright (c) 2026 Zubair Elliot' ] || die "$2: LICENSE is not MIT, Copyright (c) 2026 Zubair Elliot"
  local notices
  notices=$(cat "$dir/THIRD_PARTY_NOTICES.md")
  [[ "$notices" == *"$(cat "$WEBP/COPYING")"* && "$notices" == *"$(cat "$WEBP/PATENTS")"* ]] || die "$2: notices lack libwebp COPYING or PATENTS"
}

mkdir -p "$OUT"
ditto "$APP" "$OUT/Swivel.app"
cp LICENSE THIRD_PARTY_NOTICES.md "$OUT/"
check "$OUT" staged
(cd build && ditto -c -k --keepParent "$NAME" "$NAME.zip")
# Judge the zip by what comes out of it, not by ditto succeeding.
X=$(mktemp -d)
trap 'rm -rf "$X"' EXIT
ditto -x -k "$OUT.zip" "$X"
[ "$(ls -A "$X")" = "$NAME" ] || die "zip root holds $(ls -A "$X" | tr '\n' ' ')"
check "$X/$NAME" "re-extracted zip"

BUILD=$(plutil -extract CFBundleVersion raw -o - "$APP/Contents/Info.plist")
echo "Built $OUT.zip: Swivel $VERSION ($BUILD), CDHash $CDHASH"
echo "SHA-256 $(shasum -a 256 "$OUT.zip" | cut -d' ' -f1)"
if [ "$(git rev-parse --abbrev-ref HEAD)" = main ]; then
  git tag "$TAG"
  echo "Tagged $TAG at $(git rev-parse --short HEAD) (not pushed)"
else
  echo "not tagging: not on main"
fi
