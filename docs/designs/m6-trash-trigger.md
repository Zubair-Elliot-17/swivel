# M6: Move original to Trash, trigger key choice

Research: `~/.claude/research/swivel-m5-polish.md` rows 4-5 (Permute ships the Trash option, off by default; Tangerine's only customisation is the trigger mask).

## Problem
After a convert the user often deletes the source by hand. And Shift or Ctrl alone can clash with other habits (Shift multi-select, Ctrl-click), so some users want only one of them to open the wheel.

## In
1. **Move original to Trash** toggle in Settings, default off. Key `trashOriginal` (Bool), read once per drop like `quality`.
   - Trash a source only when its outcome is `.converted` and every output exists. Never on `.skipped`, `.failed` or cancelled-before-claim.
   - **Conversions only, never extractions:** Text (OCR) and video → M4A/WAV ("Extract audio as…") keep the original, because it holds more than the output. Image→image, image(s)→PDF, PDF→images, video→video, audio→audio trash it. Video→GIF is an extraction too (drops audio, 256 colours): keep.
   - `FileManager.trashItem` (recoverable). A failure (no Trash on the volume, permission) keeps the file, is logged, and the menu line says "(N not moved to Trash)".
   - Combined PDF: each source is trashed only if the PDF was claimed (all sources share that one output).
2. **Trigger key** picker in Settings: Shift / Control / Shift or Control (default, today's behaviour). Key `triggerKeys` (`shift` | `control` | `both`); junk reads as `both`. Applies to the drag wheel (`DragTrigger`) and the Finder tap (`TapDetector`), read at use time.

## Out
Replace in place, output folder, per-format trash rules, Option/Cmd as triggers, undo UI.

## Reuse
`QualitySetting` pattern for read/write + junk handling; `Outcome` already carries source and outputs; Settings window sections; `AppDefaults` QA suite.

## Bold idea
None needed: two small, well-trodden settings. The one judgment call is "conversions only", which keeps a data-losing default away from extract actions.

## Plan review (outside voice, 2026-11-03), all accepted
- **P1 partial output:** `.converted` can be partial (PDF→images page/pixel caps, combined-PDF 500-page cap and `drawn > 0` partials, multi-frame image sources). Add `complete: Bool = true` to `Outcome.converted`; converters set false on those paths; trash requires `complete`.
- **P2 per-source extraction:** M4A/WAV targets keep any source that conforms to `.movie` or has a video track (decided per source, not by the batch kind).
- **P2 cancel:** a cancelled batch trashes nothing.
- **P2 overlapping drops:** don't trash a source another in-flight drop references.
- **P2 duplicates:** dedupe candidates by standardized path; guard output != source; check outputs exist just before trashing.
- **P2 tap chord:** a disabled trigger key counts as `other` in TapDetector input (chord never taps); DragTrigger passes false for it, setting read once at mouse-down.
- **P3:** toggle reads `as? Bool == true` (junk = off); Settings footnote "lossy formats too"; window height grows for 2 controls; menu labels "Tap: ready" / "Enable tap in Finder…"; QA trash rows on the `$MNT` disk image (`.Trashes`), no-Trash volume (SMB) stays manual; trash once at batch end, never per file.
- **Shape:** SwivelCore pure `trashCandidates(outcomes, slice:, isVideo:)`; `BatchSummary(notTrashed:)` appends "(N not moved to Trash)"; app layer: skip if cancelled/off → drop in-flight-referenced → exists check → trashItem + count → summary.
- Known limit (logged, not fixed): video→video can drop extra audio/subtitle tracks.
