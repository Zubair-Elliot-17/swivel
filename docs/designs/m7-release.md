# M7: Swivel 1.0

## Problem
Swivel works, but only for someone who builds it. A stranger downloading it from GitHub hits Gatekeeper, has no icon to look for, no idea how the gesture works, and no licence notice for libwebp. "Complete" means someone else can install it, understand it in a minute, and keep using it across updates.

## Audience
Mac users on Apple Silicon (macOS 14+) who find the repo or a link. No Developer ID, so no notarization.

## The bold idea
Ship it like a notarized app without paying for one: sign every release with the same self-signed "Swivel Dev" identity, so Finder access and Open at Login survive updates. The install is the one-time "Open Anyway" step, and the first-run window does the rest.

## Scope
IN:
1. **Release build** `scripts/release.sh`: release binary, version 1.0.0 (CFBundleShortVersionString/CFBundleVersion), icon, Credits.rtf, hardened runtime + `com.apple.security.automation.apple-events` entitlement, signed with "Swivel Dev" (refuses ad hoc), `ditto -c -k --keepParent` to `build/Swivel-1.0.0.zip` with LICENSE + THIRD_PARTY_NOTICES.md. Apple Silicon only (CLT builds the host arch).
2. **Icon**: drawn by a Swift script (rounded-square body on Apple's grid, an original swivel/wheel mark), `iconutil` to `.icns`, `CFBundleIconFile`. No `.icon` (needs Xcode).
3. **About Swivel…** menu item: activate + standard About panel; Credits.rtf carries the libwebp BSD-3 notice and PATENTS.
4. **Welcome window**: shown on first launch and from the menu ("Welcome…"), and when Swivel is opened again while running (`applicationShouldHandleReopen`; the menu-bar icon can hide behind the notch). Shows the gesture in three steps, "Enable tap in Finder…" (existing flow), and an Open at Login checkbox.
5. **App Translocation guard**: launched from `/AppTranslocation/`, show "Move Swivel to Applications, then open it again." and don't register a login item.
6. **Privacy sweep**: every file name or path in logs goes `.private` (21 sites); state words stay `.public` (QA reads them). Error strings (localizedDescription, AppleScript messages) go `.private`, codes stay `.public`. Control and bidi characters stripped from names in the menu line.
7. **UX P3s**: Esc closes the click wheel; "Cancelling…" line after Cancel; a failed Open at Login shows a one-line alert; VoiceOver picker double label; slice toggles read "Show PNG on the Images wheel".
8. **README Install** section (researcher's wording) and an MIT LICENSE (user, 2026-11-07), shipped in the zip.

OUT: Developer ID / notarization (user's call, 99 USD/yr), Homebrew cask, universal/Intel build, new formats, the other ~80 P3s, auto-update.

## Reuse
- Existing "Enable tap in Finder…" flow, LoginItem, SettingsWindow hosting pattern (NSWindow + NSHostingController) for the welcome window.
- scripts/bundle.sh Info.plist heredoc; dev-cert.sh identity.
- macui kit for the UI rows; FAT-without-Trash and APFS images in qa.sh.

## Needs the user
- Publishing the GitHub Release: approved by the user (2026-11-07) once checks pass.
- Swivel Dev key: backed up to ~/Documents/Swivel-Dev.p12 (password-protected).
- Developer ID: optional, later.

## Risks
- Hardened runtime without the entitlement silently breaks the Finder tap (-1743, no prompt): a qa/ui row checks the entitlement is present.
- Update path (1.0 -> 1.0.1 keeps the grant) is inferred from the designated requirement, not run end to end: a manual row.
- Open Anyway behaviour verified only on macOS 26.

## Outside voice (reviewer, 2026-11-07, all accepted)
1. P1 Requiring `--qa-drop` for the QA suite would make live `SWIVEL_QA=1` UI runs write the user's own settings: dropped; the suite stays on the env var alone.
2. P1 qa.sh wipes the suite, so "first launch" is true on every `--qa-drop` run: never show the welcome window in QA mode; the seen flag lives in the QA-aware defaults.
3. P2 One signing path: hardened runtime + entitlement move into bundle.sh, so QA tests the shipped binary; release.sh calls bundle.sh and adds version, zip and checks.
4. P2 release.sh checks the designated requirement holds the Swivel Dev leaf hash (`H"ec07fa7a…"`), `codesign --verify --strict`, and the apple-events entitlement.
5. P2 Stage `build/Swivel-1.0.0/` (app, LICENSE, THIRD_PARTY_NOTICES.md) and zip that folder; a quarantined zip, unzipped, must still give an app Open Anyway accepts (manual row).
6. P2 Error text that can hold paths goes `.private` (TrashRun.swift:42, FinderTap.swift:112).
7. P2 While translocated, Open at Login is disabled in the menu and the welcome checkbox, and the welcome window shows the move line.
8. P2 Manual rows: Finder double-click first launch, reopen, and About all come to the front.
9. P3 One zip name `Swivel-1.0.0.zip`; README says Apple Silicon only.
10. P3 release.sh refuses a dirty tree, tags v1.0.0 from HEAD, prints the zip SHA-256 for the release notes.
