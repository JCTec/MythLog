# MythLog Installer

MythLog ships as a drag-to-Applications macOS app.

The DMG is only a transport surface. It should show `MythLog.app` and the
Applications alias; recorder install/start controls belong inside
`MythLog.app` after the user opens the installed app.

The architecture is intentionally split:

- `MythLog.app` registers a visible per-user background recorder.
- `MythLog.app` reads the ledger and controls install/start/stop.

The app does not need to stay open for recording to continue.

## Package

From a source checkout:

```sh
./scripts/package-release.sh
```

This creates:

```text
dist/MythLog.app
dist/INSTALLER.md
dist/MythLog-1.0.1.zip
dist/MythLog-1.0.1.zip.sha256
```

The zip is intentionally app-only. `dist/INSTALLER.md` is written beside the
archive for maintainers, not bundled inside the user-facing archive.

To create a drag-to-Applications DMG:

```sh
./scripts/package-dmg.sh
```

The default packager tries to apply the polished Finder window layout. Use
`MYTHLOG_DMG_FINDER_LAYOUT=required ./scripts/package-dmg.sh` when validating
the visual install experience locally, or `MYTHLOG_DMG_FINDER_LAYOUT=skip`
for headless CI packaging.

This creates:

```text
dist/MythLog-1.0.1.dmg
dist/MythLog-1.0.1.dmg.sha256
```

The DMG contents are intentionally limited to:

```text
MythLog.app
Applications
```

The default DMG is ad-hoc signed for local testing. Public distribution should use a Developer ID identity and notarization:

```sh
MYTHLOG_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
MYTHLOG_NOTARIZE=1 \
MYTHLOG_NOTARY_PROFILE=MythLogNotary \
  ./scripts/package-dmg.sh
```

## Install

1. Open `dist/MythLog-1.0.1.dmg`.
2. Drag `MythLog.app` to `Applications`.
3. Open `MythLog.app` from Applications.
4. Use the in-app setup banner or choose `Recorder > Install Recorder at Login...`.
5. Confirm the visible app prompt.
6. If macOS requires Background Items approval, choose `Open System Settings` from the MythLog prompt and enable MythLog in Login Items & Extensions.

If you open MythLog directly from the DMG, Downloads, or another temporary location, recorder setup will stop and ask you to move the app to Applications first. This keeps macOS Background Items attached to a stable installed app.

Do not add installer command files, shell scripts, or setup documents to the
DMG root. Those make the install flow feel less native and less trustworthy.

The installer:

- uses bundled release binaries when installing from `dist`
- registers the bundled `Contents/Library/LoginItems/MythLog Recorder.app` with `SMAppService` when available
- falls back to the bundled `Contents/Library/LaunchAgents/com.jctec.mythlog.agent.plist` when the Login Item helper is unavailable
- keeps an installed helper fallback at `~/Library/Application Support/MythLog/MythLog.app`
- installs `mythlogctl` into `~/Library/Application Support/MythLog/bin`
- creates `~/Library/Application Support/MythLog/config.json` if needed
- creates a random ledger HMAC key in `~/Library/Application Support/MythLog/secrets` if the configured account is missing
- disables the development fallback key in config once a real installed key exists
- preserves existing config and active production ledger files
- archives an older development-fallback ledger into `~/Library/Application Support/MythLog/archives` before starting the production ledger
- writes `~/Library/LaunchAgents/com.jctec.mythlog.agent.plist` only when the app-bundled ServiceManagement path is unavailable
- starts the recorder immediately
- enables it to start again at login
- writes stdout/stderr logs to `~/Library/Logs/MythLog` for both native and fallback launches

## Verify

```sh
"$HOME/Library/Application Support/MythLog/bin/mythlogctl" status
"$HOME/Library/Application Support/MythLog/bin/mythlogctl" health
"$HOME/Library/Application Support/MythLog/bin/mythlogctl" doctor
"$HOME/Library/Application Support/MythLog/bin/mythlogctl" agent-status
"$HOME/Library/Application Support/MythLog/bin/mythlogctl" export-proof \
  --config "$HOME/Library/Application Support/MythLog/config.json" \
  --output /tmp/MythLog-Proof
launchctl print "gui/$(id -u)/com.jctec.mythlog.agent"
tail -f "$HOME/Library/Logs/MythLog/agent.out.log"
"$HOME/Library/Application Support/MythLog/bin/mythlogctl" verify-ledger \
  --config "$HOME/Library/Application Support/MythLog/config.json"
```

`mythlogctl status` reads the cheap runtime snapshot at `~/Library/Application Support/MythLog/runtime/status.json`.

`mythlogctl health` prints a one-screen human summary from that same runtime snapshot.

`mythlogctl doctor --json` emits the same health report as structured JSON for bug reports, local automation, or future machine checks.

`mythlogctl export-proof` writes a protected proof directory with the copied ledger, verification JSON, human summary, and latest hash. This is the easiest way to preserve evidence before sharing logs or debugging an incident.

`mythlogctl agent-status`, `agent-start`, `agent-stop`, `agent-restart`, `agent-install`, and `agent-uninstall` expose the legacy LaunchAgent control layer from Swift for diagnostics and automation. Normal users should install and remove the recorder from inside `MythLog.app`.

macOS may cache the old Login Items display name/icon after an upgrade from earlier development builds. If System Settings still shows `mythlog-agent`, log out and back in or remove the old Background Items row and reinstall. New packaged builds include a `MythLog Recorder.app` login item helper with the MythLog display name and icon.

## Stop

Choose `Recorder > Stop Recorder` in `MythLog.app`.

The app stops the background recorder while keeping local ledger/config/log files. For the native app-bundled background item, this removes the active `SMAppService` registration because Apple does not expose a separate "stop but stay registered" API for this service type. Use the in-app `Start Recorder` banner or choose `Recorder > Start or Restart Recorder` to start it again.

## Uninstall

Choose `Recorder > Uninstall Recorder...` in `MythLog.app`.

The app stops the background recorder, removes its registration, and removes the legacy fallback plist when present. It intentionally keeps local ledger/config/log files.

To remove all local data later:

```sh
rm -rf "$HOME/Library/Application Support/MythLog" "$HOME/Library/Logs/MythLog"
```

For a complete path-by-path cleanup and verification checklist, see [Uninstall And Local Data](UNINSTALL.md).

## Current Limits

- This installs a per-user background item, not a privileged LaunchDaemon.
- It starts at user login.
- It records while the user session is active.
- It cannot record before login or while the Mac is fully asleep.
- It does not hide itself.
