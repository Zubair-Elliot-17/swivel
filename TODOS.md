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
- **Esc to dismiss the click wheel**: needs the panel to be key; check first that Finder gets keyboard focus back after `orderOut`.
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
- **PDFKit/Vision work blocks the cooperative pool** like the M2 ImageIO work; a 100-page OCR is ~30 s on one thread.

## M3 review
- **Page-number padding uses the total page count** (`PDFRender.swift` renderPDF): a 150-page PDF gives "page 001"; pad to min(count, 100) instead.
- **Tiny text layers block OCR**: a scanned page with a stamp or Bates number has a text layer, so it is never OCR'd.
- **Q1 JPEG re-encode keyed on alphaInfo** (`PDFMaker.swift` hasAlpha): unverified on real iPhone HEIC; check for DCTDecode in QA M3-1, else use kCGImagePropertyHasAlpha.
- **200 MP page-render/OCR clamp is high for memory** (`PDFRender.swift` renderSize): ~800 MB a page with 4 in flight; consider 50 MP.
- **M3 file names logged `.public`** (PDFMaker/PDFRender/TextExtract/main.swift), and failure details carry paths: switch to `.private`.
- **Copy-restricted PDFs still give text** (allowsCopying false): deliberate, the user owns the file.
- **No cancel for slow PDFs**: a 100-page OCR runs to the end.
- **isPDF uses the file extension**: a real PDF without .pdf is skipped, a fake .pdf fails.
- **OCR orientation (M25) and `.accurate` (M26) are unpinned by tests.**
- **Partly drawn source path untested** (`PDFMaker.swift` catch where drawn > 0): no fixture makes ImageIO size a frame but fail to decode it; needs a decode seam.
- **Temp PDF left behind if CGContext creation fails** (`PDFMaker.swift:39-41`): `temp` is set before the context check, so a later source's temp replaces it and the first empty `.swivel-*.pdf` stays; remove `file` before throwing.
- **No `makePDF` read-only-folder test**: reading says "no permission"; add `readOnlyFolderReportsTheWriteError` for `makePDF`.
- **Placeholder swap race** (`Converter.swift:166-167`): `rename(2)` replaces whatever sits at the claimed name; a process swapping our empty placeholder in that window gets overwritten (accepted for exFAT support).
