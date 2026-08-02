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
dist/MythLog-1.0.0.zip
dist/MythLog-1.0.0.zip.sha256
dist/MythLog-1.0.0.dmg
dist/MythLog-1.0.0.dmg.sha256
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
