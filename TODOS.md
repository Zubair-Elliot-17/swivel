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
