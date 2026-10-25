# TODOs

P3 hardening from the M1 review (2026-10-24). None blocks M1.

## Drag and wheel
- **Re-read drag types per change, not per drag** (`DragMonitor.swift:45-48`): a source that clears the pasteboard before writing could be marked "non-file drag" for good. Swap `checked` for `lastCheckedCount`.
- **Timers in common run-loop mode** (`DragMonitor.swift:56`, `WheelPanel.swift:41`): if the run loop is in event-tracking mode, the hide poll stalls. Add the timers with `RunLoop.main.add(_, forMode: .common)`.
- **Screen lookup at top/right edge** (`WheelPanel.swift:32`): `CGRect.contains` excludes `maxX/maxY`, so a second display's top row falls back to the main screen. Use `NSMouseInRect`.
- **Stale highlight after a refused drop** (`WheelPanel.swift` `show(at:)`): a new drag within 0.5 s shows the old highlight until the next drag update. The drop slice is still correct. Set `view.highlight = nil` when repositioning.

## Privacy and display
- **Log paths as private** (`main.swift:272`): `urls` is `privacy: .public`. That's fine for a personal tool; switch to `.private` before sharing the app.
- **Show only the filename in the menu** (`main.swift:273`): the full path shows during screen sharing, and control or bidi characters in names can garble the line.

## Build
- **Quote the plist heredoc** (`scripts/bundle.sh:10`): use `<<'PLIST'` so a future `$` can't expand.
- **Hardened runtime** (`scripts/bundle.sh:24`): `codesign --options runtime`, plus `--timestamp` once signed with a real identity.

## Tests
- **`wheelHasSixSlices` restates its own literal** (`GeometryTests.swift:18-20`): it only fails when the list is edited on purpose. Delete it, or keep it knowingly.

## M2 review
P3s from the M2 review (2026-10-25). None blocks M2.
- **Pin libwebp-Xcode exactly** (`Package.swift`): `from: "1.6.0"` floats; pin `exact: "1.6.0"` / revision `2b5256c`.
- **Full paths logged as public** (`main.swift:40`): log `lastPathComponent`, or the paths as `.private`.
- **EXIF incl. GPS copied in ImageIO outputs** (`Converter.swift` encode): consider `kCGImageMetadataShouldExcludeGPS`.
- **Type allowlist** (`Converter.swift` convert): restrict decoders with `CGImageSourceSetAllowableTypes`.
- **Whole libwebp compiled, decoder included**: revisit if a WebP decode path is ever added.
- **Partial output on disk full** (`Converter.swift` claim): write to a temp file, then `renamex_np(RENAME_EXCL)`.
- **WebP job memory ~300-400 MB per 24 MP**: release the decoded image earlier; rerun QA row 8 with WebP.
- **Reveal stays on the previous batch after a PDF drop** (`main.swift` drop).
- **Overlapping batches**: an earlier batch's failure shows only in the log.
- **Blocking ImageIO work on the Swift cooperative pool** (`Converter.convertBatch`): move to a dedicated queue if it starves other tasks.
- **Unchecked `width * height`** (`Converter.swift:63`): use `multipliedReportingOverflow`; ImageIO didn't report such sizes in a probe, so not reachable today.
- **`ClaimErrorTests` overlaps `readOnlyFolderFailsWithReason`**: delete it, or keep it knowingly as the named catch-all guard.
