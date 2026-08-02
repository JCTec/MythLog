# Uninstall And Local Data

MythLog should be easy to remove and easy to audit. This page documents what the app installs, what the in-app uninstall removes, and how to perform a full local-data cleanup during development or testing.

## Installed Components

A normal per-user install may create:

```text
/Applications/MythLog.app

~/Library/Application Support/MythLog/
  MythLog.app
  bin/mythlogctl
  config.json
  events.jsonl
  runtime/status.json
  secrets/ledger-hmac-key
  archives/

~/Library/Logs/MythLog/

~/Library/LaunchAgents/com.jctec.mythlog.agent.plist

~/Library/Mobile Documents/com~apple~CloudDocs/MythLog/     # unsandboxed iCloudDrive anchors
  anchor-latest.json
  anchor-history.jsonl

~/Library/Mobile Documents/iCloud~com~jctec~mythlog/Documents/MythLog/   # sandboxed (App Store) iCloudDrive anchors
  anchor-latest.json
  anchor-history.jsonl
```

The iCloud Drive `MythLog` folder holds ledger hash anchors (see `hashAnchor` in `config.json`). Its exact location depends on `hashAnchor.destination`:

- `iCloudDrive` (default): the unsandboxed build uses `~/Library/Mobile Documents/com~apple~CloudDocs/MythLog/`; the sandboxed Mac App Store build uses its ubiquity container `~/Library/Mobile Documents/iCloud~com~jctec~mythlog/Documents/MythLog/`. Both sync off the Mac by design; a full cleanup should remove the folder from iCloud Drive as well.
- `directory`: anchors live at the literal `hashAnchor.directory` path — remove that folder instead.

The sandboxed App Store build also keeps all of its ledger/config/secrets/runtime/outbox/spool state inside the App Group container at `~/Library/Group Containers/S8662L649U.com.jctec.mythlog.shared/`; removing that directory clears the sandboxed install. If `storage.maxLedgerFileBytes` is set, rotated ledger segments named `events-rotated-*.jsonl` sit beside `events.jsonl`.

Packaged builds prefer the visible login item helper bundled inside `MythLog.app`:

```text
MythLog.app/Contents/Library/LoginItems/MythLog Recorder.app
```

The LaunchAgent plist is the fallback path for development, diagnostics, and systems where the bundled login item path is unavailable.

## Stop Recording

In `MythLog.app`, choose:

```text
Recorder > Stop Recorder
```

This stops the active recorder but keeps local data.

For the bundled `SMAppService` login item, Apple does not expose a separate "stop but remain registered" state. Stopping removes the active registration. Start it again with:

```text
Recorder > Start or Restart Recorder
```

## Uninstall Recorder

In `MythLog.app`, choose:

```text
Recorder > Uninstall Recorder...
```

This removes the recorder registration and fallback LaunchAgent plist when present. It intentionally keeps the ledger, config, secrets, logs, and proof material.

Keeping local data is deliberate: users may need the ledger after an incident.

## Full Local Data Cleanup

Use this only when you really want to remove local MythLog state:

```sh
rm -rf \
  "/Applications/MythLog.app" \
  "$HOME/Applications/MythLog.app" \
  "$HOME/Library/Application Support/MythLog" \
  "$HOME/Library/Logs/MythLog" \
  "$HOME/Library/LaunchAgents/com.jctec.mythlog.agent.plist" \
  "$HOME/Library/LaunchAgents/com.jctec.mythlog.recorder.plist" \
  "$HOME/Library/LaunchAgents/com.jctec.mythlog.plist"
```

Optional development cleanup:

```sh
find "$HOME/Library/Preferences" -maxdepth 1 -type f \( \
  -name 'MythLog*.plist' -o \
  -name 'mythlog*.plist' -o \
  -name 'com.jctec.mythlog*.plist' \
\) -delete

find /private/tmp /var/tmp "${TMPDIR:-/tmp}" -maxdepth 5 \( \
  -iname '*mythlog*' -o \
  -iname '*com.jctec.mythlog*' \
\) -exec rm -rf {} +
```

Do not run broad system cleanup commands from project scripts. Keep uninstall behavior scoped to known MythLog paths.

## Verify Removal

```sh
pgrep -afil 'MythLog|mythlog' || true

uid="$(id -u)"
for label in com.jctec.mythlog.agent com.jctec.mythlog.recorder com.jctec.mythlog; do
  launchctl print "gui/$uid/$label" >/dev/null 2>&1 && echo "loaded $label" || echo "not loaded $label"
done

find "$HOME" \( \
  -path "$HOME/Dev/Logging System" -o \
  -path "$HOME/Dev/Logging System/*" \
\) -prune -o \( \
  -iname '*mythlog*' -o \
  -iname '*com.jctec.mythlog*' \
\) -print 2>/dev/null
```

The last command intentionally excludes a common source checkout path. Adjust it for your local clone.

## macOS Background Items Cache

macOS may keep stale Background Items or launchd override metadata after a development install is removed. That cache is Apple-managed and can survive until logout or restart.

This kind of stale row does not mean the recorder is running. Trust these checks first:

```sh
pgrep -afil 'MythLog|mythlog' || true
launchctl print "gui/$(id -u)/com.jctec.mythlog.agent"
```

If the service is not found and no process is running, the recorder is gone.

Avoid resetting all Background Items globally unless you are intentionally troubleshooting your own machine; it can affect unrelated apps.
