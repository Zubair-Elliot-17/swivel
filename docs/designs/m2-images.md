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
