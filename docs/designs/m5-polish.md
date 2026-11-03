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

---

# Eng review (2026-11-01, /plan-eng-review, Autonomy: full, decisions auto-taken on the recommended option)

Target: this design doc. Evidence: static read of Sources/ at 20e58f4, research probes (swivel-m5-polish.md).

## Step 0: Scope challenge
- **Already exists:** slice lists `Geometry.sliceNames/videoSlices/audioSlices` (Geometry.swift:7-9), kind pick `Geometry.slices(for:)` (:12-17), wheel show/reset sites WheelPanel.swift:45, :104, :118, :195; quality constant Converter.swift:96; status menu main.swift:27-41; QA hook `--qa-drop` main.swift:65-67; bundle id `dev.zubair.swivel` (scripts/bundle.sh).
- **Complexity:** ~7 files touched (Geometry, Converter, WheelPanel, main, new Settings view, new WheelLayout in Core, Package.swift + tests), 2 new types (layout store, settings window controller). Gate trips (2 new types); smaller arrangement considered: put the layout cleaner in Geometry instead of a new type. **Auto-decision D1: Smaller arrangement** (cleaner + kind enum live in Geometry.swift; only the settings window is a new type). Feature list unchanged.
- Scope result: **scope accepted as-is** (smaller arrangement, no feature cut).
- TODOS cross-ref: none block M5; "hub right-click dismiss" P3 stays out.

REALITY: premise-table pass (all premises quoted to file:line above or research probes; unverified=3: next-login launch, .requiresApproval, macOS 14) swivel-m5-polish.md
REALITY: already-done pass (main..origin/main empty; no M5 code on main) git log c43e6b3
REALITY: surface-check pass (SMAppService.mainApp register/unregister/status, openSystemSettingsLoginItems probed by researcher) swivel-m5-polish.md
REALITY: binding-decisions pass (2026-10-31: add SwivelAppTests target, tag gesture rows `ui`; both carried) STATE.md Decisions
REALITY: numbers pass (0.85 [measured: Converter.swift:96]; min slices 1 [estimated: research])
REALITY: deferred-asks pass (Trash original, trigger key deferred with reason in Out of scope) m5-polish.md
REALITY: pr-count pass (one PR, feat/m5-polish)

## 1. Architecture
```
 UserDefaults (wheel.image|video|audio, quality)
        │ read per show
        ▼
 Geometry.kind(for: urls) ─► Geometry.layout(kind, defaults) ─► WheelView.slices
        ▲ clean(raw): known names, dedupe, empty/wrong type → defaults
 SettingsWindow (NSWindow + NSHostingView, SwiftUI List .onMove + Toggle) ─writes─┘
 Status menu: Open at Login (SMAppService.mainApp, status re-read in menuWillOpen) · Settings… ⌘,
```
- [P2] (confidence: 9/10) WheelPanel.swift:104 `view.slices = Geometry.sliceNames` and :118 default: hide() resets to the hard-coded image list, so a drag wheel would first flash the default image layout. Must read the user's image layout. **Accepted (D2)**: every slice source goes through one `Geometry.slices(for:defaults:)`.
- [P2] (confidence: 9/10) Geometry.swift:24 `where slices == videoSlices`: label breaks once the video wheel is reordered/trimmed. **Accepted (D3)**: `label(for:kind:)`.
- [P2] (confidence: 9/10) Converter.swift:96 quality is shared: PDFMaker.swift:124 `encode(frame, to: .jpeg)` (embedding pages in combined PDFs) and PDFRender.swift:26 (PDF→JPEG/HEIC pages) use the same encoder. **Accepted (D4)**: `encode(..., quality:)`; image conversions and PDF→image pages use the setting; PDF embedding keeps 0.85 (internal, keeps PDF sizes stable).
- [P3] (confidence: 8/10) Login item launches whichever copy last ran (research §1). **Accepted**: README note "run from one place"; no code.
- Security: no new trust boundary except UserDefaults, which any local process can write (`defaults write`). Treated as untrusted input → hostile-values AC (D5).

Dispositions: D2, D3, D4, D5 accepted; P3 note accepted.

## 2. Code quality
- [P2] (confidence: 8/10) SwivelCore must stay AppKit-free (Geometry.swift:5 "kept free of AppKit"); layout read takes a `UserDefaults` parameter so tests use `UserDefaults(suiteName:)` and never touch the real domain. **Accepted (D6).**
- [P3] (confidence: 7/10) Settings window must be one reused instance (`isReleasedWhenClosed = false`), else Cmd-, opens duplicates. **Accepted.**
Dispositions: accepted.

## 3. Tests
| Path | Test | Type |
|---|---|---|
| clean(raw): unknown names, dupes, empty, wrong type, all hidden | GeometryTests (unit) | new |
| layout per kind + reorder reaches WheelView slice order | GeometryTests (unit) | new |
| label by kind after reorder (M4A on video wheel) | GeometryTests | new |
| quality: default 0.85, setting 0.3 makes smaller JPEG, NaN/-1/5 clamp to 0...1 or default | ConverterTests | new |
| PDF embed unchanged by quality setting | PDFTests | new |
| hub alpha (decided 2026-10-31) | SwivelAppTests | new target |
| Open at Login toggle, Settings ⌘, / ⌘W, reorder drag in list | qa `ui` rows (macui kit) | ui |
| next-login launch, .requiresApproval, macOS 14 | manual | manual |
Gaps: none beyond the manual rows. Test plan: written to the planner brief.

## 4. Performance
- One UserDefaults read per wheel show (in-memory cache by the OS). No issues found.

## Failure modes
| Path | Failure | Covered | User sees |
|---|---|---|---|
| layout read | garbage via defaults write | clean() test | default wheel |
| all slices hidden | empty wheel | UI forbids + clean() falls back | default wheel |
| quality | NaN/out of range | clamp test | normal output |
| register() | .requiresApproval | menu shows unchecked, opens Login Items | System Settings |
| register() throws | error | log + menu unchecked | unchecked item (no alert) |
Critical gaps: 0.

## NOT in scope
Trash original (data-loss path, needs its own design), trigger key choice (DragTrigger rework), output folder, replace in place, AV presets, hotkey, import/export, updater, sandbox, WebP quality (encoder param unverified).

## Parallelization
Sequential implementation, no parallelization opportunity (one module pair, Core then App).

## Implementation Tasks
- [ ] **T1 (P2, human ~2h / CC ~15m)** Core: FileKind + clean + slices(for:defaults:) + label(for:kind:) (D2, D3, D5, D6). Verify: scripts/test.sh
- [ ] **T2 (P2, human ~1h / CC ~10m)** Core: quality param, clamp, PDF embed fixed (D4). Verify: scripts/test.sh
- [ ] **T3 (P2, human ~1h / CC ~10m)** App: WheelPanel reads layouts at all 4 sites. Verify: build + ui row
- [ ] **T4 (P2, human ~3h / CC ~20m)** App: Settings window + main menu ⌘, ⌘W. Verify: ui row
- [ ] **T5 (P2, human ~1h / CC ~10m)** App: Open at Login item. Verify: ui row + manual
- [ ] **T6 (P2, human ~1h / CC ~10m)** SwivelAppTests target + hub alpha test. Verify: scripts/test.sh
- [ ] **T7 (P3)** README: settings, run-from-one-place.

## Outside voice
Codex not installed; native fallback: `reviewer` (fresh context, static read @ 20e58f4). Verdict: ready with fixes. All 8 findings accepted (Autonomy: full):
- OV1 [P2] Quality key absent → `double(forKey:)` = 0 (@AppStorage never writes its default). Read `object(forKey:) as? Double ?? 0.85` once per drop in main.swift, pass explicitly convertBatch → convert → renderPDF → `encode(_:to:quality:)`; clamp 0.5...1, NaN → 0.85; test "key absent → 0.85".
- OV2 [P2] WheelPanel.swift:120 `guard slices != oldValue` skips the AX rebuild when kind changes but list is equal (video layout ["M4A","WAV"] = audio list) → VoiceOver says the wrong action. WheelView holds `kind` + `slices`, rebuilds on either; SwivelAppTests asserts AX labels.
- OV3 [P2] Layout reaching WheelView is untestable from GeometryTests, and --qa-drop skips the wheel. WheelPanel takes a `UserDefaults`; SwivelAppTests drives show/hide/draggingEntered with a suite layout and asserts `view.slices` at all 4 sites.
- OV4 [P3] Fresh bundle reports `.notFound`: everything except `.enabled`/`.requiresApproval` = off, register on click.
- OV5 [P3] `quality:` has no default, so PDFRender.swift:26 can't silently miss it; PDF→JPEG page-size test.
- OV6 [P3] Stored layout hides slices added to defaults later: accepted, noted (no new targets planned).
- OV7 [P3] Test suites `removePersistentDomain` after each test.
- OV8 [P3] Login-item + settings logic in their own files, not main.swift AppDelegate.
Task changes: T1 adds OV7; T2 adds OV1, OV5; T3 adds OV2, OV3; T5 adds OV4, OV8; T6 lands before T3 (T3 tests need the target).

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | — | — |
| Outside Review | reviewer subagent (native fallback, codex not installed) | Independent 2nd opinion | 1 | completed | 8 findings (3 P2, 5 P3), all accepted |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | issues_open | 6 issues, 0 critical gaps |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | — |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | — |

- **OUTSIDE COVERAGE:** native reviewer subagent, plan phase, completed, 8 findings accepted. No external-model coverage (codex not installed).
- **VERDICT:** Eng review done with all findings mapped to tasks (issues_open = mapped work); ready for planner.

NO UNRESOLVED DECISIONS
