# M3: PDF + text

## Problem
The PDF slice is a stub, PDFs can't be turned into images, and there's no way to pull text out of a screenshot or scan.

## Audience
Me, on my Mac: a handful of photos into one PDF to send, a PDF page as a PNG, text out of a screenshot.

## The one idea
The wheel stays one gesture: drop images on PDF to get one PDF; drop a PDF on an image slice to get its pages; drop either on Text to get a `.txt`.

## Design
- **Wheel:** 7 slices: PNG, JPEG, HEIC, WebP, TIFF, PDF, Text. Per-type layouts stay in M5.
- **Images → PDF (PDF slice):** CoreGraphics `CGContext(consumer:mediaBox:)`, not `PDFPage(image:)` (PDFKit recompresses PNG to JPEG; CG keeps PNG lossless and passes JPEG bytes through). One page per frame (`CGImageSourceGetCount`), page = pixel size at 72 dpi, EXIF orientation applied by rotating the page drawing, not the pixels. A multi-file drop makes **one** PDF in drop order, named after the first image (`<stem>.pdf`, Keep Both naming). Non-images in the drop are skipped; PDFs are skipped as "already PDF".
- **PDF → images (PNG/JPEG/HEIC/WebP/TIFF slices):** render each page into an explicit sRGB bitmap with a white fill at 150 dpi (not `PDFPage.thumbnail`, which scales by the screen's Retina factor), then reuse the M2 encoders. Pages clamped to the 200 MP cap; max 100 pages per PDF (rest skipped, noted in the log). Naming: single page → `<stem>.png`; else `<stem> page N.png`, zero-padded to the page count's width. Locked PDFs (`isLocked`) are skipped "password protected"; owner-password-only PDFs render.
- **Text slice:** images → Vision `VNRecognizeTextRequest`, `.accurate`, revision 3, auto language, language correction on. PDFs → each page's text layer (`PDFPage.string`) first, else render at 300 dpi and OCR. Output `<stem>.txt` (UTF-8), pages separated by a blank line. No text found → skipped "no text found".
- **Outcomes:** per-source as in M2; a combined PDF reports `.converted` for each source with the same output, and `BatchSummary` de-duplicates outputs for the menu line and Reveal.
- **Concurrency:** same 4-in-flight window; the combined PDF is one job.

## Reuse
CoreGraphics PDF context, PDFKit (read/render/text), Vision, the M2 encoders, `OutputName`, `claim`, `BatchSummary`. PDFKit and Vision link under CLT with no settings. Research: ~/.claude/research/swivel-m3-pdf-ocr.md.

## Out
`RecognizeDocumentsRequest` (macOS 26 paragraphs/tables; optional later), page-size options (A4/Letter), PDF merge (PDF + PDF), passwords, OCR'd searchable PDF, `/Rotate` handling beyond what PDFKit gives.

## Test plan
SwivelCore tests on generated fixtures: images → PDF has N pages of the right size and a PNG source stays FlateDecode (not DCTDecode); rotated-EXIF JPEG gives a portrait page; PDF → images page count, naming and 150 dpi size; locked PDF skipped; OCR of large rendered text `contains` the expected words; PDF text layer used without OCR. Manual QA: real Finder drops for each path, 7-slice wheel hit-testing.

## Eng review (scoped, 2026-10-27)
Feasibility: the researcher's probes on this Mac (macOS 26.6.2, CLT SDK) built CG PDF contexts, PDFKit render/text and Vision OCR with no linker settings or permission prompts. No requirement contradicts a constraint.

Findings, all accepted:
1. **Combined PDF memory (P2).** Encoding to `Data` (to keep the atomic `claim`) holds the whole PDF in memory. Fine for drops of tens of photos (JPEG passthrough keeps it near source size); cap the combined PDF at 500 pages, skip the rest with a log note.
2. **Combined PDF and the window (P2).** It is one job, so it doesn't run inside the 4-wide window; draw frames one at a time so only one decoded bitmap is alive (lazily decoded JPEGs aren't decoded at all).
3. **Thread safety (P2).** `PDFDocument`/`PDFPage` aren't `Sendable`; open, render and read each PDF inside one task, never share across tasks.
4. **Long OCR (P3).** A 100-page scanned PDF is ~30 s of OCR at 300 dpi; the busy icon covers it, no progress UI in M3.
5. **Wheel geometry (P2).** 7 slices change every slice angle; geometry tests and the VoiceOver slice elements must follow `sliceNames`, not 6.
6. **Mixed drops (P3).** Text slice: one `.txt` per source; PDF slice: images in, everything else skipped with a reason.
