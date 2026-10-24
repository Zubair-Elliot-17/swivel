# M2: image conversions

## Problem
M1 shows the wheel and logs the slice on drop. M2 makes the five image slices actually convert.

## Audience
Me, on my Mac: quick format swaps (HEIC from the phone to JPEG, screenshots to WebP) without opening Preview.

## The one idea
One drop converts the whole batch, writes each output next to its source, never overwrites, and never blocks the wheel.

## Design
- **ImageIO path (PNG, JPEG, HEIC, TIFF):** `CGImageSourceCreateWithURL` → `CGImageDestinationAddImageFromSource` at the primary index → `Finalize`. Keeps EXIF, orientation and ICC. JPEG/HEIC quality 0.85. Alpha to JPEG flattens on white (ImageIO default). First frame only. Delete the partial output if `Finalize` fails.
- **WebP:** ImageIO can't write WebP on macOS 26 (checked with `CGImageDestinationCopyTypeIdentifiers`). Use the SwiftPM package `SDWebImage/libwebp-Xcode` (vendored libwebp 1.6.0, BSD-3), `WebPEncodeRGBA` lossy q75. Pixels are oriented by `CGImageSourceCreateThumbnailAtIndex(...WithTransform)` and turned into straight sRGB RGBA via vImage. No EXIF in WebP output (fine for now).
- **Naming (SwivelCore, unit-tested):** `photo.png` → `photo.jpg`; if taken, `photo 2.jpg`, `photo 3.jpg`, ... like Finder "Keep Both". The extension for JPEG is `jpg`.
- **Skips:** source already the target type ("already PNG"), non-images, unreadable files. Skips are counted, not errors.
- **Concurrency:** a `nonisolated` async converter run in a task group from the main-actor drop handler.
- **Feedback:** status icon changes while working; menu line "Last: photo.jpg (3 of 3)" or the first failure; a "Reveal in Finder" item for the last outputs. No notifications in M2.
- **PDF slice:** stays logging-only with "PDF arrives in M3".

## Reuse
ImageIO, vImage, UniformTypeIdentifiers (system); libwebp via libwebp-Xcode. Research: ~/.claude/research/swivel-m2-images.md.

## Eng review (scoped, 2026-10-24)
Feasibility: libwebp-Xcode builds under CLT for macOS 14 (researcher scratch build + ImageIO reads the output); task-group converter compiles clean under Swift 6. No requirement contradicts a constraint.

Findings, all accepted:
1. **Name race (P1).** `photo.png` and `photo.heic` in one batch both want `photo.jpg`; check-then-write lets one clobber the other, and `CGImageDestinationCreateWithURL` overwrites. Fix: encode to `Data` (`CGImageDestinationCreateWithData`), then claim the name with `Data.write(options: .withoutOverwriting)`, moving to the next candidate on "file exists". No partial files either.
2. **Unbounded batch (P2).** 200 RAW-sized photos at once can blow memory. Cap the task group at 4 in flight.
3. **Unwritable folder (P2).** A read-only volume or a DMG makes the write fail: report it as a failure with the reason; no fallback location in M2.
4. **Inputs that aren't image files (P2).** Folders, aliases and PDFs: skip unless `CGImageSourceGetCount > 0` and the type conforms to `public.image`. PDF input is M3.
5. **Concurrent drops (P3).** A second drop while one batch runs just adds its own jobs; the menu line shows the latest batch.
6. **Test plan.** Unit-test in SwivelCore: naming (taken names, "photo 2" already existing, dotfiles, no extension, multi-dot names), skip rules, target extension map. Integration tests in SwivelCore: convert generated fixtures (an RGBA PNG, a rotated-EXIF JPEG) to each of the 5 formats, read back with ImageIO, assert the type, size, orientation-applied pixels for WebP, and orientation tag kept for the ImageIO path. Manual QA: real Finder drops, batch, collision, read-only folder.
