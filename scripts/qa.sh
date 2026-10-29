#!/bin/bash
# Runs the file-in/file-out manual QA rows against the bundled app through its --qa-drop entry point.
# Gesture, Finder-tap and VoiceOver rows stay manual (see the plans' QA sections).
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/bundle.sh >/dev/null
BIN="$PWD/build/Swivel.app/Contents/MacOS/Swivel"
ROOT=$PWD
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

# M4 fixtures: AVAssetWriter clips (scripts/avq.swift), say + afconvert audio, a junk .mp4.
swiftc -O "$ROOT/scripts/avq.swift" -o avq 2>/dev/null
./avq mk clip.mov 2 20 1 0 && ./avq mk rot.mov 2 20 1 1 && ./avq mk mute.mov 2 20 0 0 && ./avq mk long.mov 31 2 0 0
say -o voice.aiff "Swivel audio test"
afconvert -f m4af -d aac voice.aiff voice.m4a && afconvert -f WAVE -d LEI16 voice.aiff voice.wav && afconvert -f mp4f -d aac voice.aiff voice.mp4
printf junk > bad.mp4
codec() { ./avq codec "$1" "${2:-video}"; }
# fresh <dir> <file>...: a new folder holding copies of the fixtures.
fresh() { local d=$1; shift; mkdir "$d" && cp "$@" "$d/"; }

# M4-1, M4-2: clip.mov on MP4 (H.264 remux) and on HEVC (fresh folder).
fresh m41 clip.mov
expect M4-1 "$(drop MP4 m41/clip.mov)" "Last: clip.mp4 (1 of 1)"
expect "M4-1 codec" "$(codec m41/clip.mp4)" avc1
fresh m42 clip.mov
expect M4-2 "$(drop HEVC m42/clip.mov)" "Last: clip.mp4 (1 of 1)"
expect "M4-2 codec" "$(codec m42/clip.mp4)" hvc1

# M4-3: an MP4 on MOV, then on MP4.
fresh m43 m41/clip.mp4
expect "M4-3 MOV" "$(drop MOV m43/clip.mp4)" "Last: clip.mov (1 of 1)"
expect "M4-3 MP4" "$(drop MP4 m43/clip.mp4)" "Skipped 1 of 1: already MP4"

# M4-4: GIFs at 10 fps, 320 px (no upscale), rotated clip upright.
fresh m44 clip.mov rot.mov
expect M4-4 "$(drop GIF m44/clip.mov m44/rot.mov)" "Last: rot.gif (2 of 2)"
read -r n w h delay loop < <(./avq gif m44/clip.gif)
[ "$n $w $h $delay $loop" = "20 320 240 0.1 0" ] && pass "M4-4 clip.gif" || fail "M4-4 clip.gif" "$n frames ${w}x$h delay $delay loop $loop"
read -r n w h _ < <(./avq gif m44/rot.gif)
[ "$h" -gt "$w" ] && pass "M4-4 rot.gif upright (${w}x$h)" || fail "M4-4 rot.gif" "${w}x$h"

# M4-5: audio out of a video, and WAV to M4A.
fresh m45 clip.mov voice.wav
expect "M4-5 clip" "$(drop M4A m45/clip.mov)" "Last: clip.m4a (1 of 1)"
expect "M4-5 voice" "$(drop M4A m45/voice.wav)" "Last: voice.m4a (1 of 1)"
afinfo m45/clip.m4a | grep -q 'aac' && afinfo m45/voice.m4a | grep -q 'aac' && pass "M4-5 aac" || fail "M4-5 aac" "afinfo"

# M4-6: M4A to 16-bit WAV, at most 2 channels.
fresh m46 voice.m4a
expect M4-6 "$(drop WAV m46/voice.m4a)" "Last: voice.wav (1 of 1)"
fmt=$(afinfo m46/voice.wav | grep 'Data format')
[[ "$fmt" =~ ([0-9]+)\ ch.*Int16 ]] && [ "${BASH_REMATCH[1]}" -le 2 ] && pass "M4-6 format" || fail "M4-6 format" "$fmt"

# M4-7: skips and failures, nothing written.
fresh m47 voice.mp4 mute.mov bad.mp4 long.mov
expect "M4-7 no video" "$(drop MP4 m47/voice.mp4)" "Skipped 1 of 1: no video"
expect "M4-7 no audio" "$(drop M4A m47/mute.mov)" "Skipped 1 of 1: no audio"
expect "M4-7 bad" "$(drop MP4 m47/bad.mp4)" "Skipped 1 of 1: not supported by macOS"
expect "M4-7 long" "$(drop GIF m47/long.mov)" "Failed: long.mov: too long for GIF (max 30 s) (0 of 1 converted)"
want="bad.mp4 long.mov mute.mov voice.mp4 "
# Q6: VP9 only when ffmpeg is installed; it is never a project dependency.
if command -v ffmpeg >/dev/null; then
  ffmpeg -loglevel error -f lavfi -i testsrc=size=320x240:rate=10 -t 2 -c:v libvpx-vp9 -deadline realtime -cpu-used 8 m47/vp9.mp4
  expect "M4-7 vp9" "$(drop MP4 m47/vp9.mp4)" "Skipped 1 of 1: codec not supported"
  want+="vp9.mp4 "
else
  echo "SKIP M4-7 vp9 (no ffmpeg)"
fi
expect "M4-7 nothing written" "$(ls -A m47 | sort | tr '\n' ' ')" "$want"

# M4-8: a video plus an image on MP4.
fresh m48 clip.mov a.jpg
expect M4-8 "$(drop MP4 m48/clip.mov m48/a.jpg)" "Last: clip.mp4 (1 of 2, 1 skipped)"

# M4-9: the same drop twice keeps both; no temp file anywhere.
fresh m49 clip.mov
drop MP4 m49/clip.mov >/dev/null
expect M4-9 "$(drop MP4 m49/clip.mov)" "Last: clip 2.mp4 (1 of 1)"
left=$(find . -name '.swivel-*' | head -3)
[ -z "$left" ] && pass "M4-9 no temp files" || fail "M4-9 no temp files" "$left"

# M2 row 6 (and M4-10 with a video): a drop on a read-only volume fails and writes nothing.
mkdir ro && cp a.jpg ro/p.jpg && cp clip.mov ro/
hdiutil create -quiet -srcfolder ro -format UDRO ro.dmg
mkdir "$MNT" && hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MNT" ro.dmg
line=$(drop PNG "$MNT/p.jpg")
[[ "$line" == "Failed: p.jpg: "*" (0 of 1 converted)" ]] && [ ! -e "$MNT/p.png" ] \
  && pass "M2-6 ($line)" || fail "M2-6" "got '$line'"
# MP4, not MOV: a .mov on MOV is skipped as already MOV before anything is written.
line=$(drop MP4 "$MNT/clip.mov")
[[ "$line" == "Failed: clip.mov: "*" (0 of 1 converted)" ]] && [ "$(ls "$MNT" | sort | tr '\n' ' ')" = "clip.mov p.jpg " ] \
  && pass "M4-10 ($line)" || fail "M4-10" "got '$line', $(ls -a "$MNT" | tr '\n' ' ')"

echo "$fails failed"
exit $((fails > 0))
