#!/bin/zsh
set -euo pipefail

LABEL="com.jctec.mythlog.agent"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
INSTALL_DIR="$HOME/Library/Application Support/MythLog"
LOG_DIR="$HOME/Library/Logs/MythLog"
GUI_DOMAIN="gui/$(id -u)"

finish() {
  local exit_code=$?
  echo
  if [[ $exit_code -eq 0 ]]; then
    echo "MythLog uninstaller finished."
  else
    echo "MythLog uninstaller failed with exit code $exit_code."
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

if [[ "${MYTHLOG_ASSUME_YES:-0}" != "1" ]]; then
  echo "This stops MythLog's user LaunchAgent and removes its plist."
  echo "Ledger, config, logs, and installed binaries are preserved."
  echo
  read "?Uninstall MythLog LaunchAgent? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "Cancelled."; exit 0 ;;
  esac
fi

section "Stopping MythLog LaunchAgent"
launchctl bootout "$GUI_DOMAIN" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootout "$GUI_DOMAIN/$LABEL" >/dev/null 2>&1 || true

section "Removing LaunchAgent plist"
rm -f "$PLIST_PATH"

section "Data preserved"
echo "Kept recorded data and installed binaries:"
echo "  $INSTALL_DIR"
echo "Kept logs:"
echo "  $LOG_DIR"
echo
echo "To delete all local MythLog data later, run manually:"
echo "  rm -rf \"$INSTALL_DIR\" \"$LOG_DIR\""
