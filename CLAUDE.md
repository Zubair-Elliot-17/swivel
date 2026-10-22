# Swivel

Native macOS menu-bar app: drag a file, tap a modifier key, pick a target format on a radial wheel, drop to convert. Everything runs locally.

## Rules for every session
- Run work through zstack: start with `/z` (reads `.claude/team/STATE.md`, resumes from Next action).
- Clean-room build. `docs/teardown.md` describes how Tangerine behaves; never copy its code, assets, strings or bundled scripts.
- Swift + SwiftUI/AppKit, Swift Package Manager or a plain Xcode project, macOS 14+. Prefer system frameworks (AVFoundation, ImageIO, PDFKit, Vision, CoreImage) before bundling tools like ffmpeg.
- Work on feature branches; main is for merged PRs only.
- Keep code comments to 1-2 lines; longer notes go in `docs/`.

## Layout
- `docs/teardown.md`: what the reference app does and how (behaviour + architecture).
- `docs/plan.md`: scope, milestones, open questions.
- `.claude/team/STATE.md`: local sprint state (git-excluded).
