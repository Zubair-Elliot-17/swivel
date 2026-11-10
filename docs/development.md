# Development

Swivel is a Swift package built with the Command Line Tools (no Xcode project). `SwivelCore` holds the converters and pure logic; `Swivel` is the menu-bar app.

## Build and run

```sh
scripts/bundle.sh && open build/Swivel.app
```

### Dev rebuilds

An ad-hoc signature changes with every build, so the privacy system treats each rebuild as a new app and the Automation grant goes stale. Run `scripts/dev-cert.sh` once: it makes a self-signed "Swivel Dev" code-signing identity in your login keychain, and `scripts/bundle.sh` signs with it from then on, so a grant survives rebuilds. Without it the bundle is still signed ad hoc, and after each rebuild you need:

```sh
scripts/bundle.sh && tccutil reset AppleEvents dev.zubair.swivel && open build/Swivel.app
```

### Release

`scripts/release.sh` makes `build/Swivel-1.0.0.zip` for GitHub Releases. It refuses a dirty tree, a missing "Swivel Dev" identity (an ad hoc release would cost every user their Finder access and login item on update) and an existing `v1.0.0` tag. It then runs `scripts/test.sh` and `scripts/qa.sh`, records the tested bundle's CDHash, stages `build/Swivel-1.0.0/` (the app, `LICENSE`, `THIRD_PARTY_NOTICES.md`), zips it with `ditto`, unzips it into a temp folder and checks that copy: contents, executable bit, hardened runtime, the apple-events entitlement, the Swivel Dev designated requirement, the same CDHash and binary, Info.plist values, icon, credits, licence and notices. Nothing builds or signs after QA. It prints the zip's SHA-256 and tags `v1.0.0` only on `main` (elsewhere it prints "not tagging: not on main"); it never pushes. `scripts/release-test.sh` checks the three refusals in a scratch worktree.

Every bundle is signed with the hardened runtime and `assets/Swivel.entitlements` (only `com.apple.security.automation.apple-events`); without that entitlement the Finder tap fails silently with -1743. `scripts/check-app.sh sign|bundle <app>` holds the signature and bundle checks that `qa.sh` (rows M7-1, M7-2) and `release.sh` share.

The version is `VERSION` in `scripts/bundle.sh`; the build number is `git rev-list --count HEAD`. Bump `VERSION` (and the checks in `check-app.sh` and `release.sh`) for the next release.

**Keep the signing key safe.** Users' grants are tied to the Swivel Dev certificate (its leaf hash is in the designated requirement). Export it from Keychain Access as a password-protected `.p12` and keep a copy off this Mac. If the key is lost, every user has to allow Finder access and re-enable Open at Login once after the next update.

Generated assets are committed: `swift scripts/icon.swift` redraws `assets/AppIcon.icns`, and `assets/Credits.rtf` (the About panel) is libwebp's `COPYING` and `PATENTS` run through `textutil -convert rtf`.

## Tests

- `scripts/test.sh`: the unit tests (Swift Testing) for both targets.
- `scripts/qa.sh`: builds the app, makes fixtures in a temp folder (photos, text PDFs, a password PDF, a read-only disk image) and runs the file-in/file-out QA rows through a hidden entry point, printing PASS/FAIL per row. The M6 trash rows run only on throwaway disk images (one writable APFS image, and a FAT image with no usable Trash), so nothing reaches your own Trash. In QA mode the app reads and writes the `dev.zubair.swivel.qa` settings suite, never your own settings; `qa.sh` deletes the suite at the start and end. The entry point only works with `SWIVEL_QA=1` set: `SWIVEL_QA=1 build/Swivel.app/Contents/MacOS/Swivel --qa-drop <slice> <path>...` runs one drop, prints the menu line and quits.
- Gesture, Finder-tap and VoiceOver rows are driven with synthetic events and the accessibility tree, or run by hand.

## Settings storage

Settings live in `dev.zubair.swivel` (`wheel.image`, `wheel.video`, `wheel.audio`, `quality`, `trashOriginal`, `triggerKeys`, `welcomeSeen`). Values are checked on every read: unknown names, duplicates, an empty list or a wrong type fall back to the default wheel, quality is clamped to 0.5-1.0 (anything not a number means 0.85), `trashOriginal` and `welcomeSeen` count only a real Bool true (a string like "YES" or a number like 2 is off; QA runs never read or write `welcomeSeen`), and `triggerKeys` must be exactly `shift`, `control` or `both` (anything else means both). Reset deletes the key, so a kind you never changed picks up new default slices in later versions; a saved layout keeps exactly the slices it lists, so a slice added to the defaults later stays hidden there until you Reset or switch it on.

## Docs

- `docs/plan.md`: scope and milestones.
- `docs/designs/`: one design note per milestone (M1-M7).
- `docs/teardown.md`: behaviour notes on the reference app, for a clean-room build.
- `TODOS.md`: known limits and P3 follow-ups.
