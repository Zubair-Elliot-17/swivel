# TODOs

P3 hardening from the M1 review (2026-10-24). None blocks M1.

## Drag and wheel
- ~~**Re-read drag types per change, not per drag**~~ Done in M2b (poll re-reads types every tick once changeCount has moved).
- ~~**Timers in common run-loop mode**~~ Done in M2b (drag poll and hide timer).
- **Screen lookup at top/right edge** (`WheelPanel.swift:78`): `CGRect.contains` excludes `maxX/maxY`, so a second display's top row falls back to the main screen. Use `NSMouseInRect`.
- **Stale highlight after a refused drop** (`WheelPanel.swift` `show(at:)`): a new drag within 0.5 s shows the old highlight until the next drag update. The drop slice is still correct. Set `view.highlight = nil` when repositioning.

## Privacy and display
- **Log paths as private** (`main.swift:65`): `urls` is `privacy: .public`. That's fine for a personal tool; switch to `.private` before sharing the app.
- **Sanitize names in the menu** (`BatchSummary.swift:52-56`): the line already shows only the filename, but control or bidi characters in names can garble it.

## Build
- ~~**Quote the plist heredoc**~~ Done in M2b.
- **Hardened runtime** (`scripts/bundle.sh:25`): `codesign --options runtime`, plus `--timestamp` once signed with a real identity. The Finder tap then needs the `com.apple.security.automation.apple-events` entitlement.

## Tests
- **`wheelHasSevenSlices` restates its own literal** (`GeometryTests.swift:21-23`): it only fails when the list is edited on purpose. Delete it, or keep it knowingly.

## M2 review
P3s from the M2 review (2026-10-25). None blocks M2.
- **Pin libwebp-Xcode exactly** (`Package.swift`): `from: "1.6.0"` floats; pin `exact: "1.6.0"` / revision `2b5256c`.
- **Full paths logged as public** (`main.swift:65`): log `lastPathComponent`, or the paths as `.private`.
- **EXIF incl. GPS copied in ImageIO outputs** (`Converter.swift` encode): consider `kCGImageMetadataShouldExcludeGPS`.
- **Type allowlist** (`Converter.swift` convert): restrict decoders with `CGImageSourceSetAllowableTypes`.
- **Whole libwebp compiled, decoder included**: revisit if a WebP decode path is ever added.
- **Partial output on disk full** (`Converter.swift` claim): write to a temp file, then `renamex_np(RENAME_EXCL)`.
- **WebP job memory ~300-400 MB per 24 MP**: release the decoded image earlier; rerun QA row 8 with WebP.
- **Overlapping batches**: an earlier batch's failure shows only in the log.
- **Blocking ImageIO work on the Swift cooperative pool** (`Converter.convertBatch`): move to a dedicated queue if it starves other tasks.
- **Unchecked `width * height`** (`Converter.swift:65`): use `multipliedReportingOverflow`; ImageIO didn't report such sizes in a probe, so not reachable today.
- **`ClaimErrorTests` overlaps `readOnlyFolderFailsWithReason`**: delete it, or keep it knowingly as the named catch-all guard.

## M2 QA feedback (2026-10-26)
- **QA row 6 not confirmed by hand**: the read-only drop was never run from a truly read-only place (the iCloud Desktop made the 555 test folder writable). Unit test `readOnlyFolderFailsWithReason` covers it; re-run from a read-only DMG.
- **Same-format drop reads like an error**: dropping `screenshot.png` on PNG says "already PNG". Consider clearer wording, or re-encode as a copy.
- **Drag + Shift still sometimes needs a re-try** on the M2 build: fixed in M2b (`feat/m2b-trigger`), needs its manual QA rows 1-3.

## M2b Finder tap
- **Stable self-signed signing identity** (`scripts/bundle.sh`): ad-hoc builds get a new cdhash, so the Automation grant is lost on each rebuild (README has the `tccutil reset` workaround).
- ~~**Esc to dismiss the click wheel**~~ Done in M7: the wheel polls the Esc key state (the panel stays non-key), with VoiceOver on or off.
- **Keyboard slice pick** in click mode (arrows/Return), same key-focus caveat as Esc.
- **flagsChanged canary log**: global flagsChanged without Accessibility is undocumented; log "tap monitor: no flagsChanged seen" when the drag poll sees a Shift edge the monitor missed.
- **First click converts at once** (`WheelPanel.swift:163`): no selection count is shown; ignore clicks in the first ~150 ms after open, show the count, or confirm over ~50 items.
- **AppleScript errorMessage logged `.public`** (`FinderTap.swift:108`): it can name files; switch to `.private`.
- **Tap selections hit the public drop log** (`main.swift:65`): Finder-tap paths now go through it too; log `.private` or a count.
- **Dead-zone/corner clicks fall through to Finder** (`WheelPanel.swift:23-24`): clear pixels pass clicks through; check on hardware, add a near-transparent fill if needed.
- **Toggle-off lost while a check is in flight** (`FinderTap.swift:71`): a second tap during the AE check is ignored and the wheel still opens; set a cancel flag instead.
- **Unknown AE errors show "allow Finder access"** (`Tap.swift:78`): any non-0/-1743 code maps to `.needsAccess`; add a generic error line.
- **TapStatus menu-line tests restate literals** (`TriggerTests.swift:121-133`): they only fail on a deliberate copy edit; keep knowingly or test the mapping only.
- **Input methods that switch language on a bare Shift tap** open the wheel too; consider an off switch.
- ~~**Stale line refs in TODOS**~~ Done in M2b fixes (refs re-pointed to current lines).

## M3 PDF + text
- **Render 200 MP clamp untested** (`PDFRender.swift` render): a real test needs an ~800 MB bitmap; check by hand with a poster-size PDF.
- **OCR orientation not proven by a test** (`TextTests.swift` sidewaysPhotoIsReadUpright): Vision reads rotated text even when told `.up`.
- **Transparent HEIC/WebP stay lossless in a combined PDF** (`PDFMaker.swift`): JPEG would flatten them on black; flatten on white first if file size matters.
- **Partial pages stay on disk** when a PDF page fails part-way (`PDFRender.swift`): named in the log detail, same policy as the claim shortcut.
- **PDFKit joins lines in some PDFs** (`TextExtract.swift`): a cupsfilter PDF's page comes out as one line (`PDFPage.string`); CoreText PDFs keep line breaks. scripts/qa.sh compares words for that reason.
- **PDFKit/Vision work blocks the cooperative pool** like the M2 ImageIO work; a 100-page OCR is ~30 s on one thread.

## M3 review
- **Page-number padding uses the total page count** (`PDFRender.swift` renderPDF): a 150-page PDF gives "page 001"; pad to min(count, 100) instead.
- **Tiny text layers block OCR**: a scanned page with a stamp or Bates number has a text layer, so it is never OCR'd.
- **Q1 JPEG re-encode keyed on alphaInfo** (`PDFMaker.swift` hasAlpha): unverified on real iPhone HEIC; check for DCTDecode in QA M3-1, else use kCGImagePropertyHasAlpha.
- **200 MP page-render/OCR clamp is high for memory** (`PDFRender.swift` renderSize): ~800 MB a page with 4 in flight; consider 50 MP.
- **M3 file names logged `.public`** (PDFMaker/PDFRender/TextExtract/main.swift), and failure details carry paths: switch to `.private`.
- **Copy-restricted PDFs still give text** (allowsCopying false): deliberate, the user owns the file.
- **No cancel for slow PDFs**: a 100-page OCR runs to the end. M4 "Cancel conversions" stops batches between sources only; OCR still doesn't stop between pages.
- **isPDF uses the file extension**: a real PDF without .pdf is skipped, a fake .pdf fails.
- **OCR orientation (M25) and `.accurate` (M26) are unpinned by tests.**
- **Partly drawn source path untested** (`PDFMaker.swift` catch where drawn > 0): no fixture makes ImageIO size a frame but fail to decode it; needs a decode seam.
- **Temp PDF left behind if CGContext creation fails** (`PDFMaker.swift:39-41`): `temp` is set before the context check, so a later source's temp replaces it and the first empty `.swivel-*.pdf` stays; remove `file` before throwing.
- **No `makePDF` read-only-folder test**: reading says "no permission"; add `readOnlyFolderReportsTheWriteError` for `makePDF`.
- **Placeholder swap race** (`Converter.swift:166-167`): `rename(2)` replaces whatever sits at the claimed name; a process swapping our empty placeholder in that window gets overwritten (accepted for exFAT support).

## M4 audio + video
- ~~**Vision OCR can starve the cooperative pool**~~ Done in M5: Vision runs on a GCD thread (the full test run deadlocked once the M5 quality tests added HEIC encodes). The ImageIO work is still on the pool (see M5 polish).
- **macOS 14 cancel path unverified**: there `export(to:as:)` runs Apple's back-deployed body (`guard status != .cancelled`); M4 never enters it in a cancelled task, but only a 14 machine can confirm (QA M4-M5).
- **`status` / `progress` on AVAssetExportSession are deprecated at macOS 15**: fine at the 14 target; switch to `states(updateInterval:)` when the target moves.
- **Temp folder kept if it can't be removed in 2 s** (`AVConvert.swift` removeLate): logged as an error, never seen in tests.
- **Progress index uses `firstIndex(of:)`** (`main.swift` drop): a URL dropped twice reports the first position.
- **"already MP4" ignores the audio codec**: an `avc1` `.mp4` with ALAC audio is skipped, not re-encoded to AAC.
- **Image and OCR jobs already running when cancelled finish their file**; the outcome says so (converted).
- **GIF is built in memory**: ~17 MB worst case at the caps (noise test in research); stream to a temp file if caps grow.

## M4 review (P3)
- **No cap on concurrent drops** (`main.swift` drop): each drop starts its own batch; AV batches then share one media engine. Queue or cap them.
- ~~**No "Cancelling…" feedback**~~ Done in M7: the line reads "Cancelling…" and the item is disabled until the batches end or a new drop starts.
- **Failed temp removal not logged on success** (`AVConvert.swift` viaTemp): `try?` drops the error after a claim; log it like removeLate does.
- **Untested: disk full and the same source dropped twice at once**: needs a small disk image fixture and two overlapping convertAV calls on one file.
- **`show(at:)` keeps the previous slice set until draggingEntered** (`WheelPanel.swift`): a wheel shown for a new drag briefly draws the last drag's slices.

## M4 fix re-check (P3)
- **GIF frame times round the track start to 1/600 s** (`AVRender.swift` makeGIF): an edit list starting at e.g. 1001/30000 s asks for frame 0 just before the track; keep the probe's CMTime start.
- **Cancel ignored for an export stuck in `.unknown`** (`AVConvert.swift` run): after the 10 s wait, keep polling until it starts, then cancelExport; today it runs to the end and is discarded.
- **App-layer fixes untested** (`main.swift` lineOwner, progress dedupe): move into a small testable type or keep to manual QA.
- **qa.sh m46r setup can end the run without a FAIL line** (`scripts/qa.sh` ~138): add `|| { echo "FAIL setup: m46r fixtures"; exit 1; }`.
- **qa.sh `afinfo | grep -q` can SIGPIPE under pipefail** (`scripts/qa.sh` ~141): use `grep -q … <<<"$(afinfo …)"`.

## Hub fix re-check (P3)
- **Right-click in the click-mode hub doesn't dismiss** (`WheelPanel.swift` WheelView): the hub is now ours, so the global right-click monitor never sees it; add `rightMouseDown` → `onDismiss` in click mode.
- **Hub pass-through has no automated test**: it happens in WindowServer; keep "drop in the wheel centre, file stays put" as a manual QA row.
- **Wheel can't be driven by scripted QA**: manual rows were run with synthetic CGEvent drags + AX presses (scratchpad tools); worth turning into `scripts/qa-ui.sh` if UI rows keep growing.

## M5 polish (P3)
- **ImageIO HEIC/JPEG encodes still block the cooperative pool** (`Converter.convert`): the HEVC encoder waits on a semaphore; with the pool full of blocking work it was half of the M5 test deadlock. Hop to a GCD queue like OCR now does.
- **HEIC bytes vary run to run** (hardware or software encoder): `lossySizeFollowsQuality` asserts only the size order for HEIC, byte equality for JPEG.
- **`activate(ignoringOtherApps:)` is API_TO_BE_DEPRECATED** (`SettingsWindow.show`): no warning today; a later SDK may warn and break the 0-warning gate. Switch to `NSApp.activate()` (macOS 14+) then.
- **Settings window doesn't reload on outside changes**: a `defaults write` while it is open shows the old list until the next launch; the wheel reads fresh on every show.
- **Stored layouts hide future default slices** (OV6): a saved list keeps only its names; README says so. Consider storing hidden names instead if new slices are added.
- ~~**Settings toggles are labelled by format name only**~~ Done in M7: "Show PNG on the Images wheel".
- **Open at Login, `.requiresApproval` and next-login launch are manual-only** (QA M5-M1, M5-M2), and macOS 14 is unverified (M5-M3).
- **`SWIVEL_QA=1` alone switches settings to the QA suite** (`AppDefaults`), even without `--qa-drop`: intended for scripted runs, noted so nobody sets it in a login shell.

## M5 review (P3)
- ~~**A failed Open at Login is only logged**~~ Done in M7: one alert, "Couldn't change Open at Login.", then the check mark is re-read.
- **OCR never checks cancellation** (`TextExtract.swift` extractText page loop, pre-M5): Cancel conversions doesn't stop a 100-page OCR; check `Task.isCancelled` between pages.
- **QA suite switch reads `SWIVEL_QA` alone** (`AppDefaults.swift` suiteName): also require `--qa-drop`, so a leaked env var can't point the normal app at the suite qa.sh wipes.

## M6 trash and trigger (P3)
- **Trash runs on the main actor** (`TrashRun.run`): fine for local volumes; a big batch on a slow network share could stall the menu. Move it off main if that shows up.
- **iPhone HEIC with aux or burst images** may report more than one frame and so never be trashed (safe); not checked on a real burst.
- **Video→video can drop subtitle, chapter, timecode and metadata tracks unchecked** (`AVConvert.swift` `keepsTracks`): audio and video tracks are compared; README warns about the rest. Comparing track counts by media type would catch them.
- **One unreadable later audio track now skips the whole file** (`AVConvert.swift:277-278` probe): every audio track's format is loaded with `try`; use `try?` for tracks after the first and record (0,0), as before M6.
- **Tracks are paired by position** (`AVConvert.swift:112-115` `keepsTracks`): an export that reorders audio tracks would read as partial (safe: original kept); sort both lists by (channels, rate) if it ever shows up.
- **No Ctrl drag in macui** (`ev` has no `ctrldown`): the Control-only drag is covered by pure tests; add `ctrldown/ctrlup` to drive it.
- **Duplicate sources keep the first outcome's outputs** (`Trash.trashCandidates`): the exists check looks at those only; fine since every copy converted the same file.
- **Combined-PDF `catch where drawn > 0` untested, mutant survived** (`PDFMaker.swift:91-96`): unreachable from files (14 broken TIFFs tried; frame-read failures also fail the pixelSize precheck); add a frame-read seam if it ever becomes reachable.
- **EXIF/GPS lost for WebP and combined PDF before the original is trashed** (`Converter.swift:136`, `PDFMaker.swift`): the trashed original was the only copy of that metadata.
- **Source replaced at the same path between conversion and trash** (atomic save, sync) is trashed unchecked (`TrashRun.swift:31`): compare fileResourceIdentifier + modification date from conversion time.
- **Symlinked source trash behaviour not pinned** (`TrashRun.swift:51`): untested whether the link or its target goes; consider skipping symlinks.
- **In-use and dedupe compare standardized paths only** (`TrashRun.swift:24`, `Trash.swift:17`): /var vs /private/var and case differences slip through; use fileResourceIdentifier.
- **qa.sh trust checks** (`scripts/qa.sh:10`, `:228-230`): assert $MNT is a separate mounted volume (`stat -f %d`), and make tdrop reject `/../` and paths off the image.
- ~~**Pre-existing: full drop paths logged with privacy .public**~~ Done in M7: names, paths and error text are logged `.private`.
- **main.swift trash wiring has no app-level test** (`main.swift:140-150`): cancel between job() and trash and the busy bookkeeping are unit-covered via TrashRun only.


- ~~Settings picker label is spoken twice by VoiceOver~~ Done in M7: the extra label is gone (spoken check is manual, U8).

## M7 review (P3)
- **Empty failure reason reads "file"** (`BatchSummary.swift:89`): `menuName` falls back to "file"; give it a fallback parameter and pass "unknown error" for reasons.
- **Welcome key observer never removed** (`WelcomeWindow.swift:71`): add `deinit { keyObserver.map(NotificationCenter.default.removeObserver) }` (only test instances leak).
- **`menuName` is a denylist with no length cap** (`BatchSummary.swift:33`): consider an allowlist plus an ~80-character cap with "…".
- **qa.sh M7-7 drops the whole `drop slice=` line** (`scripts/qa.sh:328,331`): count matches with `grep -o` so flipping its urls part to `.public` would fail.
- **Notices check passes vacuously if COPYING/PATENTS are missing** (`release.sh:44`, `check-app.sh:32`): check the files exist and are non-empty first.
- **Tag check is local only** (`release.sh:20`): also check `git ls-remote --tags origin v1.0.0`.
- **Off-main release.sh builds a shippable-looking zip** (`release.sh`): label the output "not a release" (its CFBundleVersion follows the branch's commit count).
- **Esc under VoiceOver polls `keyState` at 30 Hz** (`WheelPanel.swift:319`): a tap under 33 ms can be missed; latch with `secondsSinceLastEventType`, and keep U6 as the check.

## M7 test (P3)
- **Settings row id includes `isOn`** (`SettingsWindow.swift:39`): toggling gives the row a new identity, so SwiftUI reinserts it (focus can drop). Make `Row` Identifiable on kind + name.
- **Esc under VoiceOver is polled at 30 Hz** (`WheelPanel.swift:51`): a held press always lands (U6 5/5); a 0 ms synthetic Esc can slip between polls. Fine for people; revisit only if a scripted client needs it.
- **"Cancelling…" lasts under a second** (`main.swift:210`): only seen through the `lineAfterProgress` test; the menu can't be reopened fast enough to catch it on a 1080p HEVC cancel.
