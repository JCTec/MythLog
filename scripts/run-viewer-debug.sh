#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c debug --product MythLogApp

swift build -c debug --product mythlog-agent --product mythlogctl

BIN_PATH="$(swift build -c debug --show-bin-path)"
EXECUTABLE="$BIN_PATH/MythLogApp"
APP_DIR="$ROOT_DIR/.build/MythLogApp-Debug.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BIN_RESOURCES_DIR="$RESOURCES_DIR/bin"
APP_ICON_PATH="$ROOT_DIR/DesignAssets/AppIcon/MythLog.icns"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "MythLogApp executable was not found at $EXECUTABLE" >&2
  exit 1
fi

pkill -f "$APP_DIR/Contents/MacOS/MythLogApp" 2>/dev/null || true
rm -rf "$HOME/Library/Saved Application State/com.jctec.mythlog.debug.savedState"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$BIN_RESOURCES_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/MythLogApp"
cp "$BIN_PATH/mythlog-agent" "$BIN_RESOURCES_DIR/mythlog-agent"
cp "$BIN_PATH/mythlogctl" "$BIN_RESOURCES_DIR/mythlogctl"
chmod 755 "$BIN_RESOURCES_DIR/mythlog-agent" "$BIN_RESOURCES_DIR/mythlogctl"

if [[ -f "$APP_ICON_PATH" ]]; then
  cp "$APP_ICON_PATH" "$RESOURCES_DIR/MythLog.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
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
  <string>MythLogApp</string>
  <key>CFBundleIconFile</key>
  <string>MythLog</string>
  <key>CFBundleIdentifier</key>
  <string>com.jctec.mythlog.debug</string>
  <key>CFBundleName</key>
  <string>MythLog</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.1</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open -n "$APP_DIR"

echo "Launched $APP_DIR"
echo "Ledger: $HOME/Library/Application Support/MythLog/events.jsonl"
