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

## Tests

- `scripts/test.sh`: the unit tests (Swift Testing) for both targets.
- `scripts/qa.sh`: builds the app, makes fixtures in a temp folder (photos, text PDFs, a password PDF, a read-only disk image) and runs the file-in/file-out QA rows through a hidden entry point, printing PASS/FAIL per row. The M6 trash rows run only on throwaway disk images (one writable APFS image, and a FAT image with no usable Trash), so nothing reaches your own Trash. In QA mode the app reads and writes the `dev.zubair.swivel.qa` settings suite, never your own settings; `qa.sh` deletes the suite at the start and end. The entry point only works with `SWIVEL_QA=1` set: `SWIVEL_QA=1 build/Swivel.app/Contents/MacOS/Swivel --qa-drop <slice> <path>...` runs one drop, prints the menu line and quits.
- Gesture, Finder-tap and VoiceOver rows are driven with synthetic events and the accessibility tree, or run by hand.

## Settings storage

Settings live in `dev.zubair.swivel` (`wheel.image`, `wheel.video`, `wheel.audio`, `quality`, `trashOriginal`, `triggerKeys`). Values are checked on every read: unknown names, duplicates, an empty list or a wrong type fall back to the default wheel, quality is clamped to 0.5-1.0 (anything not a number means 0.85), `trashOriginal` is on only for a real Bool true (a string like "YES" or a number like 2 is off), and `triggerKeys` must be exactly `shift`, `control` or `both` (anything else means both). Reset deletes the key, so a kind you never changed picks up new default slices in later versions; a saved layout keeps exactly the slices it lists, so a slice added to the defaults later stays hidden there until you Reset or switch it on.

## Docs

- `docs/plan.md`: scope and milestones.
- `docs/designs/`: one design note per milestone (M1-M6).
- `docs/teardown.md`: behaviour notes on the reference app, for a clean-room build.
- `TODOS.md`: known limits and P3 follow-ups.
