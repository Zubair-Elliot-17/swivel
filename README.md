# Swivel

A local-first Mac file converter. Start dragging a file, tap Shift or Ctrl, and a radial wheel of formats pops up under the cursor. Drop on a format to convert. No uploads, no account.

Status: M1 (drag gesture + wheel) and M2 (image conversion: PNG, JPEG, HEIC, WebP, TIFF; output lands next to the source as `name.ext`, then `name 2.ext`, never overwriting) work. PDF arrives in M3. See [docs/teardown.md](docs/teardown.md) for the reference app study and [docs/plan.md](docs/plan.md) for scope.

## Triggers

- **During a drag:** start dragging a file from Finder, then tap Shift or Ctrl. The wheel opens under the pointer; drop on a format. A key already held when you pressed the mouse (say, Shift from a multi-select) doesn't count; tap it again.
- **No drag, in Finder:** select files in a Finder window or on the Desktop, then tap Shift or Ctrl on its own. The wheel opens at the pointer; click a format. Click outside, tap again or switch apps to dismiss.

The Finder tap reads the selection through Apple events, so it needs Automation access to Finder (no Accessibility or Input Monitoring). Choose **Enable Shift-tap in Finder…** in the menu bar menu once and click Allow. If you chose Don't Allow, the item opens System Settings > Privacy & Security > Automation instead.

### Dev rebuilds

`scripts/bundle.sh` signs ad hoc, so every rebuild looks like a new app to the privacy system and the Automation grant goes stale. After a rebuild, reset it and enable again:

```sh
scripts/bundle.sh && tccutil reset AppleEvents dev.zubair.swivel && open build/Swivel.app
```
