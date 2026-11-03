# Swivel

A local-first Mac file converter. Start dragging a file, tap Shift or Ctrl, and a radial wheel of formats pops up under the cursor. Drop on a format to convert. No uploads, no account.

Status: M1 (drag gesture + wheel) and M2 (image conversion: PNG, JPEG, HEIC, WebP, TIFF; output lands next to the source as `name.ext`, then `name 2.ext`, never overwriting) work, and M3 adds PDF (images to one combined PDF, PDF pages to images) and a Text slice (OCR or the PDF's text layer). M4 adds audio and video with a wheel per file type: video gets MP4 (H.264), HEVC, MOV, GIF (10 fps, 480 px, up to 30 s), M4A and WAV; audio gets M4A and WAV. The menu shows progress and a Cancel item. Everything uses macOS's own AVFoundation, so formats it can't decode (MKV, WebM, AVI, VP9) are skipped, and there's no MP3 output. M5 adds Settings (your own wheel per file type and a JPEG/HEIC quality slider) and Open at Login. M6 adds two settings: move the original to the Trash after a conversion, and which key (Shift, Control or either) opens the wheel. See [docs/teardown.md](docs/teardown.md) for the reference app study and [docs/plan.md](docs/plan.md) for scope.

## Triggers

- **During a drag:** start dragging a file from Finder, then tap Shift or Ctrl (or only the one chosen under Settings > General). The wheel opens under the pointer; drop on a format. A key already held when you pressed the mouse (say, Shift from a multi-select) doesn't count; tap it again.
- **No drag, in Finder:** select files in a Finder window or on the Desktop, then tap Shift or Ctrl on its own. The wheel opens at the pointer; click a format. Click outside, tap again or switch apps to dismiss.

The Finder tap reads the selection through Apple events, so it needs Automation access to Finder (no Accessibility or Input Monitoring). Choose **Enable tap in Finder…** in the menu bar menu once and click Allow. If you chose Don't Allow, the item opens System Settings > Privacy & Security > Automation instead.

## Settings

Choose **Settings…** in the menu bar menu (⌘, also opens it once Swivel is the active app; ⌘W closes it).

- **Move original to Trash** (General, default off): after a drop, each source that was fully converted goes to the Trash, so it is recoverable (Finder's Put Back). Conversions only: Extract text, Make GIF and Extract audio (M4A or WAV from anything that is a movie or has a video track) always keep the original, and so does a partial conversion (a multi-page TIFF or animated GIF, of which only the first frame is converted, or a PDF cut by the 100-page or pixel cap). Lossy targets count as conversions too. A source is kept when the batch was cancelled, when another drop still in progress uses it, or when one of its outputs is missing. On volumes without a Trash (some network shares), or for a locked file, the file stays, and the menu line ends with "(N not moved to Trash)". An audio or video output that drops an audio or video track, audio channels or sample rate (say 5.1 to WAV) also counts as partial, so such sources are kept. Known limit: subtitle and other text tracks aren't checked, so with this on, keep a copy of a movie with subtitles.
- **Open the wheel with** (General): Shift, Control, or Shift or Control (default). It applies to the drag wheel (read when you press the mouse) and the Finder tap; with one key chosen, the other key does nothing, and a tap with both keys never opens the wheel.
- **Wheel layouts:** Images, Video and Audio each list their slices. Drag rows to reorder, switch a row off to hide it from that wheel (one always stays on), or press **Reset** for the default list. The next wheel, and the VoiceOver labels on it, follow your list. A hidden slice switched back on goes to the end.
- **Quality:** one slider (50-100%, default 85%) for JPEG and HEIC output, including PDF pages saved as JPEG or HEIC. HEIC tops out at 99% (macOS's HEIC encoder can fail at 100% while a video conversion runs). PNG, TIFF and WebP ignore it, and the JPEG pages Swivel puts inside a combined PDF always use 85%.
- Settings live in `dev.zubair.swivel` (`wheel.image`, `wheel.video`, `wheel.audio`, `quality`, `trashOriginal`, `triggerKeys`). Values are checked on every read: unknown names, duplicates, an empty list or a wrong type fall back to the default wheel, quality is clamped to 0.5-1.0 (anything not a number means 0.85), `trashOriginal` is on only for a real Bool true (a string like "YES" or a number like 2 is off), and `triggerKeys` must be exactly `shift`, `control` or `both` (anything else means both). Reset deletes the key, so a kind you never changed picks up new default slices in later versions; a saved layout keeps exactly the slices it lists, so a slice added to the defaults later stays hidden there until you Reset or switch it on.

## Open at Login

**Open at Login** in the menu bar menu registers Swivel with `SMAppService.mainApp`; the check mark is re-read every time the menu opens. If you switch Swivel off under System Settings > General > Login Items, the item shows unchecked and clicking it opens that pane. The login item launches the copy of Swivel that last registered, so run Swivel from one place (e.g. `/Applications` or `build/Swivel.app`, not both).

### Dev rebuilds

An ad-hoc signature changes with every build, so the privacy system treats each rebuild as a new app and the Automation grant goes stale. Run `scripts/dev-cert.sh` once: it makes a self-signed "Swivel Dev" code-signing identity in your login keychain, and `scripts/bundle.sh` signs with it from then on, so a grant survives rebuilds. Without it the bundle is still signed ad hoc, and after each rebuild you need:

```sh
scripts/bundle.sh && tccutil reset AppleEvents dev.zubair.swivel && open build/Swivel.app
```

### Scripted QA

`scripts/qa.sh` builds the app, makes fixtures in a temp folder (photos, text PDFs, a password PDF, a read-only disk image) and runs the file-in/file-out QA rows through a hidden entry point, printing PASS/FAIL per row. The M6 trash rows run only on a writable throwaway disk image, so nothing reaches your own Trash. In QA mode the app reads and writes the `dev.zubair.swivel.qa` settings suite, never your own settings; `qa.sh` sets `quality` and `trashOriginal` there for the M5 and M6 rows and deletes the suite at the start and end. The entry point only works with `SWIVEL_QA=1` set: `SWIVEL_QA=1 build/Swivel.app/Contents/MacOS/Swivel --qa-drop <slice> <path>...` runs one drop, prints the menu line and quits. Gesture, Finder-tap and VoiceOver rows stay manual.
