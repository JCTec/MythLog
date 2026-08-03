#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# A bare `MythLogConfig()` carries the historical tilde storage defaults
# (~/Library/Application Support/MythLog/...). Under the App Sandbox `~` expands
# to each process's own private container, so resolving the ledger, runtime
# directory, spool, or outbox from it makes the viewer app read files the
# recorder never writes — and the failure is silent, because a missing file
# reads as "recorder not running" rather than as an error.
#
# This shipped once: the App Store build showed "Recorder Not Running" forever
# while the recorder was registered and healthy, and the timeline read an empty
# ledger. Resolve through InstalledConfiguration (viewer) or
# MythLogConfig.installedDefault(paths:) instead, both of which are
# container-aware.

APP_SUPPORT_DIR="Sources/MythLogAppSupport"
ALLOWED_FILE="$APP_SUPPORT_DIR/State/InstalledConfiguration.swift"

if ! command -v rg >/dev/null 2>&1; then
  echo "Missing required tool: rg" >&2
  exit 1
fi

# Flag storage-path reads taken off a freshly constructed config.
matches="$(rg -n 'MythLogConfig\(\)\s*\.storage' "$APP_SUPPORT_DIR" || true)"
violations="$(awk -F: -v allowed="$ALLOWED_FILE" '$1 != allowed { print }' <<<"$matches")"

if [[ -n "$violations" ]]; then
  echo "Storage paths must not be resolved from a bare MythLogConfig()." >&2
  echo "Under the App Sandbox its tilde paths expand to this process's private" >&2
  echo "container, not the shared App Group container the recorder writes to." >&2
  echo "Use InstalledConfiguration (ledgerURL/statusURL/config) instead." >&2
  echo "$violations" >&2
  exit 1
fi

echo "Container path resolution checks passed."
