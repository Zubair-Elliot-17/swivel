# M4: audio and video

Research: `~/.claude/research/swivel-m4-av.md` (2026-10-29, probes on macOS 26.6.2).

## Problem
Swivel converts images and PDFs. Dragging a video or audio file today shows the image wheel, and every slice skips it as "not an image". M4 makes the same drag-tap-drop gesture convert video and audio using only system frameworks.

## The one idea
The wheel fits the file. It works out the drop's kind from the file extensions when the wheel opens, with no file reads on the drag path, and shows the slice set for that kind:

| Dragged | Slices |
|---|---|
| images / PDF | PNG, JPEG, HEIC, WebP, TIFF, PDF, Text (today's 7, unchanged) |
| video | MP4, HEVC, MOV, GIF, M4A, WAV |
| audio | M4A, WAV |
| mixed | the set for the first file's kind; files of other kinds skip with a reason |

This pulls "per-type wheel layouts" forward from M5. User-editable layouts stay in M5.

## Targets
- **MP4** means H.264/AAC, for compatibility. Remux when the video is already H.264; otherwise `AVAssetExportPresetHighestQuality`.
- **HEVC** is `HEVCHighestQuality` into `<stem>.mp4`. Remux when the video is already `hvc1`.
- **MOV** is a Passthrough remux when compatible, else HighestQuality.
- **M4A** is Passthrough when the audio is AAC, else `AppleM4A`. It works from video too.
- **WAV** is 16-bit LPCM via AVAssetReader/Writer, max 2 channels.
- **GIF** uses AVAssetImageGenerator and ImageIO at 10 fps, max 480 px on the long side, looping forever, from at most 30 s of source.

Out of v1: MP3 output (macOS has no encoder), MKV/WebM/AVI input (skipped as "not supported by macOS"), ffmpeg in any form, ProRes, size presets, trim, AIFF, HEICS and animated WebP.

## Reuse
- `Outcome`, `SkipReason`, `BatchSummary`, `claim(file:)` and the temp-then-rename pattern from PDFMaker.
- `Converter.window` with `maxInFlight: 1`, since parallel exports gave no speedup.
- `Geometry` already takes a slice count, so only the names become per-show.
- `scripts/qa.sh` gets video and audio rows, with fixtures written by AVAssetWriter.

## Safety (hostile inputs)
- Only pass file types from `session.supportedFileTypes`. Any other type raises an Objective-C exception, which crashes the app.
- Check `isPlayable` plus preset compatibility before exporting. A VP9 .mp4 claims to be exportable but can't be decoded.
- Audio-only sources on video slices skip as "no video"; video-only sources on audio slices skip as "no audio". `hasProtectedContent` skips as "DRM protected".
- Durations stay `Double` until they're finite, then go through `Int(exactly:)`. Rotated sizes go through `abs()`.
- Every export gets a fresh session, writes to a temp file, and the `defer` removes the temp on every path.

## Progress and cancel
- The menu line reads `Converting clip.mov 42% (2 of 5)`. It polls `session.progress` every 0.5 s; GIF reports frames done out of the total.
- "Cancel conversions" cancels the drop Tasks. It leaves no partial file and no temp file, and the outcome is failed "cancelled".
- A second drop runs alongside the first, as it does today.

## Risks
- macOS 14 is unverified, so runtime checks turn surprises into skips.
- DRM handling comes from the headers only, because no protected file was available.
- GIF quality on real camera footage hasn't been tested; it's a manual QA row.
