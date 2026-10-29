#!/bin/bash
# Runs the file-in/file-out manual QA rows against the bundled app through its --qa-drop entry point.
# Gesture, Finder-tap and VoiceOver rows stay manual (see the plans' QA sections).
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/bundle.sh >/dev/null
BIN="$PWD/build/Swivel.app/Contents/MacOS/Swivel"
F=$(mktemp -d)
MNT="$F/mnt"
cleanup() { [ -d "$MNT" ] && hdiutil detach -quiet "$MNT" || true; rm -rf "$F"; }
trap cleanup EXIT
echo "sha $(git rev-parse --short HEAD)$(git diff --quiet HEAD || echo '+dirty'), fixtures $F"

fails=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1: $2"; fails=$((fails + 1)); }
# drop <slice> <path>... prints the menu line Swivel would show.
drop() { SWIVEL_QA=1 "$BIN" --qa-drop "$@" 2>/dev/null | tail -1; }
pages() { swift -e 'import PDFKit; print(PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))?.pageCount ?? -1)' "$1"; }
width() { sips -g pixelWidth "$1" | awk '/pixelWidth/ {print $2}'; }
# expect <row> <actual line> <expected line>
expect() { [ "$2" = "$3" ] && pass "$1" || fail "$1" "got '$2', want '$3'"; }

# Fixtures: a photo (no text), JPEGs, PNG "screenshots", a 1-page and a multi-page text PDF, a password PDF.
cd "$F"
cp /System/Library/CoreServices/DefaultDesktop.heic photo.heic
sips -Z 800 -s format jpeg photo.heic --out a.jpg >/dev/null
sips -Z 600 -s format heic photo.heic --out b.heic >/dev/null
sips -Z 700 -s format jpeg photo.heic --out c.jpg >/dev/null
printf 'Swivel quick brown fox\n' > one.txt
cupsfilter one.txt > one.pdf 2>/dev/null
for i in $(seq 1 150); do echo "Line $i of the Swivel QA document"; done > doc.txt
cupsfilter doc.txt > doc.pdf 2>/dev/null
N=$(pages doc.pdf)
swift -e 'import PDFKit; let a = CommandLine.arguments; _ = PDFDocument(url: URL(fileURLWithPath: a[1]))!.write(to: URL(fileURLWithPath: a[2]), withOptions: [.userPasswordOption: "qa", .ownerPasswordOption: "qa-owner"])' one.pdf locked.pdf
mkdir src && cp one.pdf src/shot.pdf && drop PNG src/shot.pdf >/dev/null && mv src/shot.png shot.png
[ -f shot.png ] || { echo "FAIL setup: could not render shot.png"; exit 1; }

# M3-1: three photos in order -> one 3-page PDF named after the first.
mkdir m31 && cp a.jpg b.heic c.jpg m31/
expect M3-1 "$(drop PDF m31/a.jpg m31/b.heic m31/c.jpg)" "Last: a.pdf (3 of 3)"
[ "$(pages m31/a.pdf)" = 3 ] && pass "M3-1 pages" || fail "M3-1 pages" "$(pages m31/a.pdf)"

# M3-2: 2 PNGs + a folder + a PDF -> one 2-page PDF, 2 skipped.
mkdir -p m32/folder && sips -s format png a.jpg --out m32/s1.png >/dev/null && sips -s format png c.jpg --out m32/s2.png >/dev/null && cp one.pdf m32/
expect M3-2 "$(drop PDF m32/s1.png m32/s2.png m32/folder m32/one.pdf)" "Last: s1.pdf (2 of 4, 2 skipped)"
[ "$(pages m32/s1.pdf)" = 2 ] && pass "M3-2 pages" || fail "M3-2 pages" "$(pages m32/s1.pdf)"

# M3-3: a multi-page PDF on each image slice -> one file per page at 150 dpi (Letter = 1275 px wide).
for pair in PNG:png JPEG:jpg HEIC:heic WebP:webp TIFF:tiff; do
  slice=${pair%%:*} ext=${pair#*:}
  mkdir "m33-$ext" && cp doc.pdf "m33-$ext/"
  line=$(drop "$slice" "m33-$ext/doc.pdf")
  got=$(ls "m33-$ext" | grep -c "^doc page [0-9]*\.$ext$" || true)
  first=$(ls "m33-$ext" | grep "^doc page 0*1\.$ext$" || true)
  w=$(width "m33-$ext/$first" 2>/dev/null || echo none)
  [ "$got" = "$N" ] && [ "$w" = 1275 ] && [[ "$line" == "Last: doc page "*" (1 of 1)" ]] \
    && pass "M3-3 $slice ($N pages)" || fail "M3-3 $slice" "$got of $N pages, width $w, line '$line'"
done

# M3-4: a 1-page PDF on JPEG -> no page suffix.
mkdir m34 && cp one.pdf m34/
expect M3-4 "$(drop JPEG m34/one.pdf)" "Last: one.jpg (1 of 1)"

# M3-5: a password PDF on PNG and Text -> skipped, nothing written.
mkdir m35 && cp locked.pdf m35/
expect "M3-5 PNG" "$(drop PNG m35/locked.pdf)" "Skipped 1 of 1: password protected"
expect "M3-5 Text" "$(drop Text m35/locked.pdf)" "Skipped 1 of 1: password protected"
[ "$(ls m35)" = locked.pdf ] && pass "M3-5 nothing written" || fail "M3-5 nothing written" "$(ls m35 | tr '\n' ' ')"

# M3-6: an image with text -> OCR'd .txt.
mkdir m36 && cp shot.png m36/
expect M3-6 "$(drop Text m36/shot.png)" "Last: shot.txt (1 of 1)"
grep -qi "quick brown fox" m36/shot.txt 2>/dev/null && pass "M3-6 text" || fail "M3-6 text" "$(head -c 200 m36/shot.txt 2>/dev/null)"

# M3-7: a scan (image-only PDF) and a text PDF -> two .txt files, the text layer exact.
mkdir m37 && cp shot.png m37/scan.png && drop PDF m37/scan.png >/dev/null && rm m37/scan.png && cp doc.pdf m37/
expect M3-7 "$(drop Text m37/scan.pdf m37/doc.pdf)" "Last: doc.txt (2 of 2)"
grep -qi "quick brown fox" m37/scan.txt 2>/dev/null && pass "M3-7 scan OCR" || fail "M3-7 scan OCR" "$(head -c 200 m37/scan.txt 2>/dev/null)"
# PDFKit reads cupsfilter's lines as one run per page, so compare words, not line breaks.
[ "$(tr -s '[:space:]' ' ' < m37/doc.txt | sed 's/ $//')" = "$(tr -s '[:space:]' ' ' < doc.txt | sed 's/ $//')" ] \
  && pass "M3-7 text layer" || fail "M3-7 text layer" "words differ from doc.txt"

# M3-8: a photo with no text -> skipped.
mkdir m38 && cp photo.heic m38/
expect M3-8 "$(drop Text m38/photo.heic)" "Skipped 1 of 1: no text found"

# M2b row 7 (drop half; the Finder tap itself stays manual): image + folder on PNG.
mkdir -p r7/folder && cp a.jpg r7/
expect "M2b-7" "$(drop PNG r7/a.jpg r7/folder)" "Last: a.png (1 of 2, 1 skipped)"

# M2 row 6: a drop on a read-only volume fails and writes nothing.
mkdir ro && cp a.jpg ro/p.jpg
hdiutil create -quiet -srcfolder ro -format UDRO ro.dmg
mkdir "$MNT" && hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MNT" ro.dmg
line=$(drop PNG "$MNT/p.jpg")
[[ "$line" == "Failed: p.jpg: "*" (0 of 1 converted)" ]] && [ ! -e "$MNT/p.png" ] \
  && pass "M2-6 ($line)" || fail "M2-6" "got '$line'"

echo "$fails failed"
exit $((fails > 0))
