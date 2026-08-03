# Release Checklist

This checklist is for maintainers preparing MythLog for a public release.

## Repository Readiness

- [x] Add a public `LICENSE` file (MythLog Personal Use License).
- [ ] Confirm `README.md` describes the product, limits, install path, data locations, and safety boundaries.
- [ ] Confirm `SECURITY.md` has a private reporting path or a clear fallback process.
- [ ] Confirm issue templates and pull request template do not invite private logs or secrets.
- [ ] Confirm screenshots and generated assets do not reveal private machine data.
- [ ] Remove local exports, proof bundles, debug logs, and `.pyc` files that should not be public.

## Build Gate

This is a verification pass, not the release build — `MYTHLOG_DMG_FINDER_LAYOUT=skip`
below is intentional so this DMG builds fast without needing a Finder GUI
session. It is a throwaway artifact used only to exercise the gate suite. Do
not attach it to a release or hand it to a user; see "Distribution Readiness"
below for the DMG that actually ships.

```sh
./scripts/check-repository-metadata.sh
./scripts/check-format.sh
./scripts/check-swiftui-appkit-boundaries.sh
./scripts/check-swiftui-background-tasks.sh
./scripts/check-swiftui-main-thread-io.sh
./scripts/check-swiftui-store-boundaries.sh
./scripts/verify-release.sh
MYTHLOG_SKIP_RELEASE_BUILD=1 MYTHLOG_DMG_FINDER_LAYOUT=skip ./scripts/package-dmg.sh
./scripts/audit-distribution.sh
```

Expected artifacts:

```text
dist/MythLog.app
dist/MythLog-1.0.1.zip
dist/MythLog-1.0.1.zip.sha256
dist/MythLog-1.0.1.dmg
dist/MythLog-1.0.1.dmg.sha256
dist/INSTALLER.md
```

## Local Install QA

Use a clean user account or remove previous development installs first.

- [ ] Open the DMG.
- [ ] Confirm the DMG contains only `MythLog.app` and `Applications`.
- [ ] Drag `MythLog.app` to Applications.
- [ ] Open the app from Applications.
- [ ] Confirm the app asks to install/start the recorder from inside the app.
- [ ] Install the recorder.
- [ ] Approve Background Items if macOS asks.
- [ ] Confirm System Settings shows a friendly MythLog name and icon where macOS allows it.
- [ ] Confirm the live timeline opens with the last 24 hours.
- [ ] Lock and unlock the Mac, then confirm events appear.
- [ ] Send a test notification from the app menu.
- [ ] Run `mythlogctl health`.
- [ ] Run `mythlogctl doctor`.
- [ ] Export a proof bundle from the app.
- [ ] Stop and restart the recorder from the app menu.
- [ ] Uninstall the recorder from the app menu.

## Accessibility Smoke Test

No automated check in this repository observes the rendered UI, so this pass is
the only evidence the app behaves as [Accessibility](ACCESSIBILITY.md) describes.
Run it on the built app, not a debug build, with events already in the timeline.

- [ ] Turn on VoiceOver (<kbd>⌘</kbd><kbd>F5</kbd>) and walk the timeline and
      toolbar with the keyboard only. Every control is reachable, is named, and
      makes sense read aloud; VoiceOver reads events oldest to newest and never
      lands on the grid, ticks, or connector lines.
- [ ] Set **System Settings → Accessibility → Display → Text size** to the
      largest setting. No text is clipped or truncated, and no button loses its
      glyph.
- [ ] Turn on **System Settings → Accessibility → Display → Color Filters →
      Grayscale**. Warning and critical events are still distinguishable from
      each other and from normal ones; recorder health and ledger status are
      still readable.
- [ ] Turn on **Reduce motion** and confirm selecting an event, opening the
      inspector, and a new event arriving all still work without sliding or
      springing.
- [ ] With **Keyboard navigation** on, navigate the whole app without a mouse,
      including the filter settings and ledger integrity sheets. Nothing is a
      dead end, and <kbd>⌥</kbd><kbd>←</kbd>/<kbd>⌥</kbd><kbd>→</kbd> step
      between events.
- [ ] Record any regression against the [Known gaps](ACCESSIBILITY.md#known-gaps)
      list — if a gap has closed or a new one appeared, update that page in the
      same release.

## Distribution Readiness

This is the DMG that actually ships. It runs `package-dmg.sh` without
`MYTHLOG_DMG_FINDER_LAYOUT=skip`, so it defaults to `required`: it builds the
full styled Finder layout (background art, positioned icons) and fails loudly
instead of silently falling back to a plain DMG if that layout can't be
applied. Run this from an interactive macOS session (not a headless/remote
shell) so Finder automation can actually run.

Local test builds may be ad-hoc signed. Public builds should use Developer ID signing and notarization:

```sh
MYTHLOG_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
MYTHLOG_NOTARIZE=1 \
MYTHLOG_NOTARY_PROFILE=MythLogNotary \
  ./scripts/package-dmg.sh
```

Before publishing:

- [ ] Verify `codesign --verify --deep --strict dist/MythLog.app`.
- [ ] Verify notarization status.
- [ ] Verify `shasum -a 256 -c` for zip and DMG checksums.
- [ ] Download the uploaded artifact on another Mac and repeat install QA.

## Privacy And Safety Review

- [ ] No keylogging.
- [ ] No screenshots.
- [ ] No private-content capture.
- [ ] No hidden persistence.
- [ ] No privilege escalation without explicit user consent.
- [ ] No bypassing macOS privacy prompts.
- [ ] New event sources are documented in `ALARM_HOOKS.md`.
- [ ] New custom integrations are documented in `docs/CUSTOM_EVENTS.md`.

## Cleanup Review

After uninstalling a release candidate, verify there are no unexpected leftovers:

```sh
pgrep -afil 'MythLog|mythlog' || true
find "$HOME/Library/Application Support" "$HOME/Library/Logs" "$HOME/Library/LaunchAgents" "$HOME/Library/Preferences" \
  -maxdepth 4 \( -iname '*mythlog*' -o -iname '*com.jctec.mythlog*' \) -print 2>/dev/null
```

Expected retained data depends on the uninstall mode:

- Recorder uninstall keeps ledger/config/logs.
- Full local-data cleanup removes known MythLog paths.
- macOS may retain Apple-managed Background Items metadata until logout or restart.
