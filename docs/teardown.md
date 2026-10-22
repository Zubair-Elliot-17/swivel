# Reference teardown: Tangerine 2.0.2

Studied 2026-10-22 from /Applications/Tangerine.app. Behaviour notes only, for a clean-room rebuild.

## Interaction
1. User starts dragging any file (Finder, desktop, browser).
2. While dragging, tapping Shift / Cmd / Ctrl opens a radial wheel of target formats near the cursor.
3. Dropping on a wheel slice converts the file; output lands next to the source.

## How it works
- **App shell:** Swift, SwiftUI + AppKit, sandboxed, `LSUIElement` menu-bar app (no Dock icon).
- **No Accessibility permission / event tap.** Drag detection uses an `NSEvent` global monitor for mouse events plus `NSPasteboard(name: .drag)`: compare its `changeCount` to the value captured at mouse-down to know a file drag is live.
- **Modifiers:** polled with `CGEventSource.flagsState(.combinedSessionState)`.
- **Wheel:** a borderless, non-activating `NSPanel` (theirs: `ConversionOverlayPanel`) that accepts the drop.

## Converters they use
| Area | Their approach | Our first choice |
|------|----------------|------------------|
| Video / audio | Bundled LGPL ffmpeg (VideoToolbox, lame, webp) | AVFoundation export; ffmpeg only if needed |
| Images | cwebp, CoreImage | ImageIO / CoreImage |
| Metadata | ExifTool (Perl) | ImageIO properties |
| PPTX / XLSX | Bundled Java 21 + Apache POI / PDFBox | Defer |
| Pages | JSContext JS parsing IWA/protobuf | Defer |
| PDF | PDFKit | PDFKit |
| OCR / QR / faces | Vision | Vision |

Paywall: RevenueCat (not needed).
