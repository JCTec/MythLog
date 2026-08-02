#!/bin/zsh
set -euo pipefail

LABEL="com.jctec.mythlog.agent"
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
INSTALL_DIR="$HOME/Library/Application Support/MythLog"
BIN_DIR="$INSTALL_DIR/bin"
AGENT_APP_DIR="$INSTALL_DIR/MythLog.app"
AGENT_CONTENTS_DIR="$AGENT_APP_DIR/Contents"
AGENT_MACOS_DIR="$AGENT_CONTENTS_DIR/MacOS"
AGENT_RESOURCES_DIR="$AGENT_CONTENTS_DIR/Resources"
AGENT_EXECUTABLE="$AGENT_MACOS_DIR/MythLog"
LOG_DIR="$HOME/Library/Logs/MythLog"
CONFIG_PATH="$INSTALL_DIR/config.json"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
GUI_DOMAIN="gui/$(id -u)"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

finish() {
  local exit_code=$?
  echo
  if [[ $exit_code -eq 0 ]]; then
    echo "MythLog installer finished."
  else
    echo "MythLog installer failed with exit code $exit_code."
  fi

  if [[ -t 0 && "${MYTHLOG_NO_PAUSE:-0}" != "1" ]]; then
    echo
    read "?Press Return to close this window."
  fi
}
trap finish EXIT

section() {
  echo
  echo "==> $1"
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required tool: $1" >&2
    exit 1
  fi
}

confirm_continue() {
  if [[ "${MYTHLOG_ASSUME_YES:-0}" == "1" ]]; then
    return 0
  fi

  echo
  read "?Install and start MythLog recorder at login? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) echo "Cancelled."; exit 0 ;;
  esac
}

section "MythLog LaunchAgent installer"
echo "Project: $ROOT_DIR"
echo "Install dir: $INSTALL_DIR"
echo "LaunchAgent: $PLIST_PATH"
cat <<INFO

This installs MythLog as a visible per-user background recorder.

What will be installed:
  - Agent app: $AGENT_APP_DIR
  - Control tool: $BIN_DIR/mythlogctl
  - LaunchAgent plist: $PLIST_PATH
  - Ledger/config/secrets under: $INSTALL_DIR

What to expect:
  - macOS may show a Background Items notice for MythLog.
  - No admin password is required.
  - No Keychain access is required.
  - Existing MythLog config and ledger files are preserved.

INFO
confirm_continue

require_tool launchctl
require_tool plutil
require_tool codesign

find_bundled_bin_dir() {
  local candidates=(
    "$SCRIPT_DIR/MythLog.app/Contents/Resources/bin"
    "$SCRIPT_DIR/bin"
    "$SCRIPT_DIR/../Resources/bin"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate/mythlog-agent" && -x "$candidate/mythlogctl" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

find_bundled_icon() {
  local candidates=(
    "$SCRIPT_DIR/MythLog.app/Contents/Resources/MythLog.icns"
    "$SCRIPT_DIR/MythLog.icns"
    "$SCRIPT_DIR/../Resources/MythLog.icns"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

if BUNDLED_BIN_DIR="$(find_bundled_bin_dir)"; then
  section "Using bundled release binaries"
  BIN_PATH="$BUNDLED_BIN_DIR"
  echo "Bundled bin dir: $BIN_PATH"
else
  require_tool swift
  section "Building release binaries"
  cd "$ROOT_DIR"
  swift build -c release --disable-build-manifest-caching
  BIN_PATH="$(swift build -c release --show-bin-path)"
fi

if [[ ! -x "$BIN_PATH/mythlog-agent" || ! -x "$BIN_PATH/mythlogctl" ]]; then
  echo "Release binaries were not found in $BIN_PATH" >&2
  exit 1
fi

if BUNDLED_ICON="$(find_bundled_icon)"; then
  echo "Bundled icon: $BUNDLED_ICON"
else
  BUNDLED_ICON=""
  echo "Bundled icon: not found; helper will use the default macOS app icon"
fi

section "Creating install directories"
mkdir -p "$BIN_DIR" "$AGENT_MACOS_DIR" "$AGENT_RESOURCES_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents" "$INSTALL_DIR/runtime" "$INSTALL_DIR/outbox"

section "Stopping any existing LaunchAgent"
launchctl bootout "$GUI_DOMAIN" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootout "$GUI_DOMAIN/$LABEL" >/dev/null 2>&1 || true

section "Installing binaries"
install -m 755 "$BIN_PATH/mythlog-agent" "$AGENT_EXECUTABLE"
install -m 755 "$BIN_PATH/mythlogctl" "$BIN_DIR/mythlogctl"
rm -f "$BIN_DIR/mythlog-agent"
rm -f "$AGENT_MACOS_DIR/MythLogAgent" "$AGENT_MACOS_DIR/mythlog-agent"

if [[ -n "$BUNDLED_ICON" ]]; then
  install -m 644 "$BUNDLED_ICON" "$AGENT_RESOURCES_DIR/MythLog.icns"
fi

cat > "$AGENT_CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>MythLog</string>
  <key>CFBundleExecutable</key>
  <string>MythLog</string>
  <key>CFBundleIconFile</key>
  <string>MythLog</string>
  <key>CFBundleIdentifier</key>
  <string>$LABEL</string>
  <key>CFBundleName</key>
  <string>MythLog</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSBackgroundOnly</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
</dict>
</plist>
PLIST
plutil -lint "$AGENT_CONTENTS_DIR/Info.plist"

section "Signing agent app"
codesign --force --deep --sign - "$AGENT_APP_DIR"
codesign --verify --deep --strict "$AGENT_APP_DIR"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$AGENT_APP_DIR"
fi

section "Preparing config"
if [[ -f "$CONFIG_PATH" ]]; then
  echo "Keeping existing config: $CONFIG_PATH"
else
  "$BIN_DIR/mythlogctl" default-config --output "$CONFIG_PATH"
  chmod 600 "$CONFIG_PATH"
fi

section "Installing LaunchAgent"
"$BIN_DIR/mythlogctl" agent-install \
  --config "$CONFIG_PATH" \
  --agent-path "$AGENT_EXECUTABLE"
"$BIN_DIR/mythlogctl" validate-config --config "$CONFIG_PATH"

section "Checking service"
sleep 2
launchctl print "$GUI_DOMAIN/$LABEL" | sed -n '1,90p'

section "Recent agent log"
if [[ -f "$LOG_DIR/agent.out.log" ]]; then
  tail -n 20 "$LOG_DIR/agent.out.log"
else
  echo "No stdout log yet: $LOG_DIR/agent.out.log"
fi

section "Installed"
echo "Agent app: $AGENT_APP_DIR"
echo "Agent executable: $AGENT_EXECUTABLE"
echo "Control tool: $BIN_DIR/mythlogctl"
echo "Config: $CONFIG_PATH"
echo "Ledger: $INSTALL_DIR/events.jsonl"
echo "Logs: $LOG_DIR"
echo
echo "Useful checks:"
echo "  \"$BIN_DIR/mythlogctl\" status"
echo "  \"$BIN_DIR/mythlogctl\" health"
echo "  \"$BIN_DIR/mythlogctl\" doctor"
echo "  \"$BIN_DIR/mythlogctl\" agent-status"
echo "  \"$BIN_DIR/mythlogctl\" export-proof --config \"$CONFIG_PATH\" --output /tmp/MythLog-Proof"
echo "  launchctl print \"$GUI_DOMAIN/$LABEL\""
echo "  tail -f \"$LOG_DIR/agent.out.log\""
echo "  \"$BIN_DIR/mythlogctl\" verify-ledger --config \"$CONFIG_PATH\""
echo
echo "If System Settings still shows the old helper name/icon, log out and back in or reinstall once after removing the old Background Items row. macOS can cache Login Items metadata."
