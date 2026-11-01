# M5: Polish (settings, launch at login, wheel layouts)

Research: ~/.claude/research/swivel-m5-polish.md (probes on macOS 26.6, CLT only).

## Problem
Every Swivel wheel is fixed, the app must be started by hand after each login, and there is nowhere to change anything.

## Audience
One user (personal unsandboxed build), daily Finder use.

## The one bold idea
The wheel is yours: per file kind (image, video, audio), choose which slices show and in what order, and the wheel you see on the next drag is exactly that list.

## In scope
1. **Open at Login**: checkable status-menu item on `SMAppService.mainApp`; status re-read on every menu open; `.requiresApproval` shows unchecked and opens Login Items settings.
2. **Settings window**: an `NSWindow` hosting a SwiftUI view (no `Settings` scene), opened from a status-menu "Settings…" item and Cmd-, ; small `NSApp.mainMenu` for Cmd-, / Cmd-W; `activate(ignoringOtherApps: true)`.
3. **Wheel layouts**: three tabs or sections (Images, Video, Audio), each a reorderable list with a visibility toggle per slice; at least 1 visible; "Reset" per kind. Stored as `wheel.image|video|audio` string arrays in UserDefaults, cleaned on read (known names only, no duplicates, empty/wrong type → defaults).
4. **JPEG/HEIC quality**: one slider (default 0.85, today's constant in Converter.swift).
5. **Label fix**: `Geometry.label(for:in:)` keys the "Extract audio as" label on the file kind, not on `slices == videoSlices` (breaks once reordered).
6. **SwivelAppTests target** (decided 2026-10-31): hub alpha test from the M4 researcher probe.

## Out of scope
Move original to Trash, trigger-key choice, custom output folder, replace in place, video/GIF presets, global hotkey, layout import/export, updater, sandbox/App Store. (Trash + trigger key are the next candidates if wanted.)

## Reuse
`SMAppService`, `NSHostingView`, `@AppStorage`/UserDefaults, SwiftUI `List` `.onMove`; `Geometry` slice lists stay the defaults; `--qa-drop` + qa.sh for scripted rows.

## Risks
- Login item launches whichever copy last ran: run from one place (note in README).
- `register()` twice returns no error (header says it should); don't rely on the error.
- Not probed: real next-login launch, `.requiresApproval`, macOS 14.
