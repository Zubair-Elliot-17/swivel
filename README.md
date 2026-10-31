# Swivel

A local-first Mac file converter. Start dragging a file, tap Shift or Ctrl, and a radial wheel of formats pops up under the cursor. Drop on a format to convert. No uploads, no account.

Status: M1 (drag gesture + wheel) and M2 (image conversion: PNG, JPEG, HEIC, WebP, TIFF; output lands next to the source as `name.ext`, then `name 2.ext`, never overwriting) work, and M3 adds PDF (images to one combined PDF, PDF pages to images) and a Text slice (OCR or the PDF's text layer). M4 adds audio and video with a wheel per file type: video gets MP4 (H.264), HEVC, MOV, GIF (10 fps, 480 px, up to 30 s), M4A and WAV; audio gets M4A and WAV. The menu shows progress and a Cancel item. Everything uses macOS's own AVFoundation, so formats it can't decode (MKV, WebM, AVI, VP9) are skipped, and there's no MP3 output. See [docs/teardown.md](docs/teardown.md) for the reference app study and [docs/plan.md](docs/plan.md) for scope.

## Triggers

- **During a drag:** start dragging a file from Finder, then tap Shift or Ctrl. The wheel opens under the pointer; drop on a format. A key already held when you pressed the mouse (say, Shift from a multi-select) doesn't count; tap it again.
- **No drag, in Finder:** select files in a Finder window or on the Desktop, then tap Shift or Ctrl on its own. The wheel opens at the pointer; click a format. Click outside, tap again or switch apps to dismiss.

The Finder tap reads the selection through Apple events, so it needs Automation access to Finder (no Accessibility or Input Monitoring). Choose **Enable Shift-tap in Finder…** in the menu bar menu once and click Allow. If you chose Don't Allow, the item opens System Settings > Privacy & Security > Automation instead.

### Dev rebuilds

`scripts/bundle.sh` signs ad hoc, so every rebuild looks like a new app to the privacy system and the Automation grant goes stale. After a rebuild, reset it and enable again:

```sh
scripts/bundle.sh && tccutil reset AppleEvents dev.zubair.swivel && open build/Swivel.app
```

### Scripted QA

`scripts/qa.sh` builds the app, makes fixtures in a temp folder (photos, text PDFs, a password PDF, a read-only disk image) and runs the file-in/file-out QA rows through a hidden entry point, printing PASS/FAIL per row. The entry point only works with `SWIVEL_QA=1` set: `SWIVEL_QA=1 build/Swivel.app/Contents/MacOS/Swivel --qa-drop <slice> <path>...` runs one drop, prints the menu line and quits. Gesture, Finder-tap and VoiceOver rows stay manual.
