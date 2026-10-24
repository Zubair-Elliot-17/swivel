# M1 design: the gesture

## Problem
Converting a file today means opening an app or a terminal. The goal is to convert it mid-drag: start dragging, tap a key, drop on the format you want.

## Audience
Just me, on my own Mac: an unsandboxed personal build.

## The one bold idea
The drag *is* the command. There's no window to open and no menu to read: the wheel appears under the cursor only while a file drag is live, and the drop picks the format.

## What M1 proves
- A file drag from any app is detected, and nothing else is: text and tab drags are ignored.
- Tapping Shift or Ctrl mid-drag shows a 6-slice wheel centred on the cursor.
- The slice under the cursor highlights, and dropping logs the file URL(s) and the slice name.
- Releasing anywhere else, or cancelling the drag with Esc (the system handles it), hides the wheel: it hides when the mouse button is up (D1).

## Mechanism (from teardown + research)
- `NSEvent` global monitors for left mouse down/dragged/up. A file drag is live when `NSPasteboard(name: .drag).changeCount` differs from its value at mouse-down and the pasteboard holds `.fileURL`.
- Modifiers are polled with `CGEventSource.flagsState(.combinedSessionState)` during the drag. This needs no Accessibility permission. The triggers are Shift and Ctrl, because Cmd and Option change the drag operation.
- The wheel is a borderless `NSPanel` with `.nonactivatingPanel`, `hidesOnDeactivate = false`, joins all spaces, and is shown with `orderFrontRegardless()`. One AppKit view does `registerForDraggedTypes([.fileURL])`. `draggingUpdated` maps angle to slice and returns `.copy` when the source mask allows it.
- The shell is an `NSStatusItem` app with accessory activation policy, built by `swift build`. `scripts/bundle.sh` wraps it in `Swivel.app` (Info.plist with `LSUIElement`) and ad-hoc signs it. M1 uses no SwiftPM resources.

## Reuse
Patterns only (no code): CopyWheel (MIT, SwiftPM radial NSPanel) and NotchDrop (MIT, panel flags). boring.notch is GPL, so it's read for ideas only.

## Known risks (verify in the spike)
- File promises (Photos, Mail) carry no URL until the drop, so M1 ignores promise-only drags and shows no wheel (D8). Support comes in M2+.
- Finder reference URLs (`/.file/id=`) need normalising with `filePathURL`.
- The drag pasteboard may trigger the macOS paste-privacy alert.

Research: ~/.claude/research/swivel-m1-gesture.md

---
# Eng review (plan-eng-review, 2026-10-24)
Target: `docs/designs/m1-gesture.md` (this file). Autonomy: full, so every choice below was auto-decided to its recommended option, per the zstack rule.

## Scope Challenge
Planned work is about 7 files (`Package.swift`, 4 sources, `scripts/bundle.sh`, `scripts/test.sh`) plus 1 test file and 0 new services, below the complexity gate. **Scope accepted as-is.** Nothing exists yet to reuse in the repo, so the work rests on system frameworks only.

Surface check (probe, 2026-10-24, macOS 26.6.2 arm64, Swift 6.3.2): `swiftc -typecheck` passed on every named API: `NSPasteboard(name: .drag)`, `changeCount`, `readObjects(... .urlReadingFileURLsOnly)`, `CGEventSource.flagsState(.combinedSessionState)`, `addGlobalMonitorForEvents`, `NSPanel [.borderless, .nonactivatingPanel]`, `hidesOnDeactivate`, `.canJoinAllSpaces/.fullScreenAuxiliary`, `orderFrontRegardless`, `NSURL.filePathURL`, `NSStatusBar`, `.accessory`. `codesign` and `plutil` are present.

REALITY: premise-table pass, 3 unverified premises (drag-pasteboard privacy exemption, reference-URL shape, global mouse monitors firing during a drag session); all are verified in the M1 spike. Source: ~/.claude/research/swivel-m1-gesture.md
REALITY: already-done pass: `git log -- docs/` shows only c8981ce (docs); no code exists.
REALITY: surface-check finding: typecheck OK, but XCTest/Testing do not load under CLT by default (F5).
REALITY: binding-decisions pass: STATE.md decisions 2026-10-24 (unsandboxed, SwiftPM, Shift/Ctrl, NSStatusItem, AppKit drop view) are all honoured.
REALITY: numbers pass: one number, 6 slices [estimated, placeholder].
REALITY: deferred-asks pass: plan.md M1 asks for detect, wheel and log; all are in scope.
REALITY: pr-count pass: 1 PR.

## Findings and decisions
| # | Sev | Conf | Where | Finding | Decision (auto) |
|---|-----|------|-------|---------|-----------------|
| F1 | P1 | 9/10 | "or pressing Esc, hides the wheel" vs "needs no Accessibility permission" | A global key monitor for Esc needs Accessibility, which contradicts the design. | D1 A: drop Esc. The system Esc already cancels the drag, so the wheel hides when the drag ends: poll `NSEvent.pressedMouseButtons == 0` while the wheel is visible. This also covers release-outside without relying on `leftMouseUp` reaching a global monitor. |
| F2 | P2 | 8/10 | "Tapping Shift or Ctrl mid-drag" | Shift held from a Finder multi-select would open the wheel instantly. | D2 A: trigger only on a rising edge (up to down) observed *after* the drag became live. |
| F3 | P2 | 8/10 | "wheel centred on the cursor" | Near a screen edge or on a second display, the wheel would be clipped. | D3 A: clamp the frame to `visibleFrame` of the screen containing the cursor. |
| F4 | P2 | 8/10 | "slice under the cursor highlights" | No rule for the centre or outside the ring; a drop there could log a wrong slice. | D4 A: a pure `slice(at:center:inner:outer:count:) -> Int?` returns nil in the dead zone and outside, and a nil drop is rejected (`[]` operation, nothing logged). |
| F5 | P2 | 9/10 | (test plan) | Probe: `import XCTest` and `import Testing` both fail under CLT. Swift Testing works with `-F`/`-rpath` to CLT `Frameworks` and `usr/lib`. | D5 A: `scripts/test.sh` wraps `swift test` with those flags; tests use Swift Testing. |
| F6 | P2 | 7/10 | (code) | Swift 6 strict concurrency: NSEvent monitor and Timer closures are nonisolated. | D6 A: tools 6.0, AppKit-facing types `@MainActor`, callbacks use `MainActor.assumeIsolated` (monitors fire on main). |
| F7 | P3 | 7/10 | `leftMouseDragged` monitor | This fires at pointer rate (~120 Hz). | D7 A: compare `changeCount` only; read pasteboard types once per change; the modifier poll timer runs only while a file drag is live. |
| F8 | P2 | 6/10 | "File promises ... logs 'promise, skipped'" | Medium confidence, verify: a promise-only drag has no `.fileURL`, so per the detection rule it never counts as a file drag and the wheel never opens. The design text implies it does. | D8 A: M1 shows the wheel only when `.fileURL` is present; promise-only drags are ignored (no wheel). Promise support is deferred to M2+. |

Dispositions: F1–F8 accepted (D1–D8, auto-decided).

## Architecture
```
 global mouse monitors ──► DragMonitor ──(file drag live)──► modifier poll (30 Hz)
   down: snapshot changeCount           │                        │ rising Shift/Ctrl
   dragged: changeCount≠ && .fileURL ───┘                        ▼
                                                     WheelPanel.show(at: clamped cursor)
                                                                 │
  WheelView (NSView, registerForDraggedTypes [.fileURL])         │
   draggingUpdated → Geometry.slice(at:) → highlight, .copy|[]   │
   performDragOperation → log URLs(filePathURL) + slice name     │
                                                                 ▼
  hide when: drop handled │ pressedMouseButtons == 0 (poll) │ drag no longer live
```
Failure modes:
- A global monitor gets no events (the macOS behaviour changes). The user sees no wheel, a silent failure. Covered by the manual QA run; the menu shows "drag seen" debug state so this is visible.
- The wheel is stuck on screen if the hide poll misses. Covered by the pressedMouseButtons poll plus hide-on-drop, with a QA check for release-outside.
- No critical gaps.

Distribution: a local `.app` from `scripts/bundle.sh` (Info.plist `LSUIElement`, `CFBundleIdentifier` `dev.zubair.swivel`, ad-hoc `codesign -s -`). There's no CI and no notarisation, both NOT in scope for M1.

## Code quality
Modules: `App` (status item, wiring), `DragMonitor`, `WheelPanel` + `WheelView`, `Geometry` (pure). No shared-code candidates. Covered by F2, F4 and F6.

## Test review
```
CODE PATHS                                         USER FLOWS
[+] Geometry.slice(at:…)                           [+] Drag Finder file, tap Shift, drop on slice
  ├── [GAP→unit] each of 6 slices (angle wrap)        └── [GAP→manual QA] log shows URL + slice
  ├── [GAP→unit] dead zone → nil                   [+] Same with Ctrl
  └── [GAP→unit] outside ring → nil                [+] Release outside the wheel → wheel hides
[+] Geometry.clampedFrame(…)                       [+] Shift held before drag (multi-select) → no wheel
  └── [GAP→unit] edges + second screen origin      [+] Text/tab drag + Shift → no wheel
[+] ModifierEdge (pure rising-edge detector)       [+] Multi-file drag → all URLs logged
  └── [GAP→unit] held-before-start, tap, release   [+] Photos drag (promise) → no wheel
[+] DragMonitor / WheelView (AppKit glue)
  └── [manual QA only: needs a real drag session]
COVERAGE plan: 3 pure units with unit tests; AppKit glue via manual QA (no UI-test harness without Xcode)
```
Proposed tests (`Tests/SwivelTests/`, Swift Testing, via `scripts/test.sh`):
- Value: protects=angle→slice mapping incl. 0°/360° wrap; fails_when=slice offset or wrap is off by one; why_new=no tests exist; seam=none; no_claim=real drag hit-testing (manual QA)
- Value: protects=dead zone and outside ring yield nil; fails_when=drop in centre logs a slice; why_new=new rule F4; seam=none; no_claim=none beyond protects
- Value: protects=wheel frame stays inside visibleFrame on any screen; fails_when=clamp ignores non-zero screen origin; why_new=new rule F3; seam=none; no_claim=real multi-display layout
- Value: protects=only an up→down edge after drag start triggers; fails_when=held Shift opens wheel; why_new=new rule F2; seam=none; no_claim=flagsState polling timing

Test plan artifact: written to the gstack project dir (see Completion summary).

## Performance
F7 only. Work is bounded to live drags; no IO besides logging.

## Outside voice
Codex is not installed and the native fallback needs TaskOutput, which this session lacks, so it is **unavailable**. Missing outside coverage, not a clean review.

## NOT in scope
Conversion (M2), file promises (M2+), settings, launch at login, notarisation/CI, Esc-to-dismiss (F1), and Accessibility-based key monitoring.

## What already exists
Nothing in the repo. Patterns only (no code) come from CopyWheel and NotchDrop (MIT); boring.notch is GPL and used for reading only.

## Worktree parallelization
Sequential implementation, no parallelization opportunity.

## Implementation Tasks
- [ ] **T1 (P1, human: ~2h / CC: ~10min)** SwiftPM skeleton, `scripts/bundle.sh`, `scripts/test.sh`, status item. Surfaced by F5/F6, distribution. Verify: `scripts/test.sh` runs ≥1 test; `scripts/bundle.sh && open build/Swivel.app` shows the menu-bar icon, no Dock icon.
- [ ] **T2 (P1, human: ~3h / CC: ~10min)** `Geometry` (slice, clamp) + `ModifierEdge`, with unit tests. Surfaced by F2/F3/F4. Verify: `scripts/test.sh` all green.
- [ ] **T3 (P1, human: ~4h / CC: ~20min)** `DragMonitor` (monitors, changeCount + `.fileURL`, modifier poll during live drag only). Surfaced by F1/F7/F8. Verify: manual QA rows 1–5.
- [ ] **T4 (P1, human: ~4h / CC: ~20min)** `WheelPanel` + `WheelView` drop target, highlight, log, hide rules. Surfaced by F1/F3/F4. Verify: manual QA rows 1–7.

## Unresolved decisions
None.

## Completion summary
- Step 0: Scope Challenge: scope accepted as-is
- Reality rows: 7/7 applicable rows emitted, 3 unverified premises
- Architecture Review: 4 issues found (F1, F3, F4, F8)
- Code Quality Review: 2 issues found (F2, F6)
- Test Review: diagram produced, 1 gap identified (F5 framework) plus 4 unit tests and 7 manual QA rows proposed
- Performance Review: 1 issue found (F7)
- NOT in scope: written
- What already exists: written
- TODOS.md updates: 0 items proposed (deferrals live in docs/plan.md milestones)
- Failure modes: 0 critical gaps flagged
- Unresolved decisions: 0 in this review
- Outside voice: codex, unavailable (not installed; native fallback lacks TaskOutput)
- Parallelization: 1 lane, 0 parallel / 1 sequential
- Lake Score: 8/8

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | — | — |
| Outside Review | codex via `/plan-eng-review` | Independent 2nd opinion | 1 | unavailable | codex not installed; no native fallback (TaskOutput missing) |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | issues_open | 8 issues, 0 critical gaps (all accepted into plan) |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | — |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | — |

- **OUTSIDE COVERAGE:** codex, plan-review, unavailable, no findings. Missing coverage, not clean.
- **VERDICT:** No review is CLEAR. Eng Review mapped 8 findings into tasks T1–T4 (issues_open means mapped work). Eng review is required.

NO UNRESOLVED DECISIONS
