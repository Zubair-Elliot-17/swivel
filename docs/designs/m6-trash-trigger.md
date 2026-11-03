# M6: Move original to Trash, trigger key choice

Research: `~/.claude/research/swivel-m5-polish.md` rows 4-5 (Permute ships the Trash option, off by default; Tangerine's only customisation is the trigger mask).

## Problem
After a convert the user often deletes the source by hand. And Shift or Ctrl alone can clash with other habits (Shift multi-select, Ctrl-click), so some users want only one of them to open the wheel.

## In
1. **Move original to Trash** toggle in Settings, default off. Key `trashOriginal` (Bool), read once per drop like `quality`.
   - Trash a source only when its outcome is `.converted` and every output exists. Never on `.skipped`, `.failed` or cancelled-before-claim.
   - **Conversions only, never extractions:** Text (OCR) and video → M4A/WAV ("Extract audio as…") keep the original, because it holds more than the output. Image→image, image(s)→PDF, PDF→images, video→video/GIF, audio→audio trash it.
   - `FileManager.trashItem` (recoverable). A failure (no Trash on the volume, permission) keeps the file, is logged, and the menu line says "(N not moved to Trash)".
   - Combined PDF: each source is trashed only if the PDF was claimed (all sources share that one output).
2. **Trigger key** picker in Settings: Shift / Control / Shift or Control (default, today's behaviour). Key `triggerKeys` (`shift` | `control` | `both`); junk reads as `both`. Applies to the drag wheel (`DragTrigger`) and the Finder tap (`TapDetector`), read at use time.

## Out
Replace in place, output folder, per-format trash rules, Option/Cmd as triggers, undo UI.

## Reuse
`QualitySetting` pattern for read/write + junk handling; `Outcome` already carries source and outputs; Settings window sections; `AppDefaults` QA suite.

## Bold idea
None needed: two small, well-trodden settings. The one judgment call is "conversions only", which keeps a data-losing default away from extract actions.
