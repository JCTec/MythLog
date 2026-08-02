#!/bin/bash
# ---------------------------------------------------------------------------
# Xcode build phase (Debug only): make the recorder actually RUN in a local
# Xcode build.
#
# Why this exists
#   A DerivedData-hosted app cannot launch its SMAppService login item: macOS
#   applies launch constraints to the managed helper and the kernel kills every
#   spawn with OS_REASON_EXEC ("job state = spawn failed"). Registration
#   succeeds, but the recorder never runs. That is a development-only problem;
#   a notarized DMG installed into /Applications satisfies the constraint.
#
#   To get a running recorder while developing, we sidestep SMAppService and use
#   the classic user LaunchAgent, which carries no such constraint. Rather than
#   hand-roll the plist + config (and drift from the app), we invoke the app's
#   own `mythlogctl agent-install`, i.e. the exact LaunchAgentManager.install()
#   code path the legacy installer uses.
#
# Safety gates (any one bails cleanly, never fails the build):
#   1. CONFIGURATION must be Debug  — never touches Release / Archive.
#   2. ACTION must be a plain build — never runs during archive/install.
#   3. Skipped under CI             — GitHub Actions sets CI / GITHUB_ACTIONS.
#                                      (CI never builds this target anyway; belt.)
#   4. MYTHLOG_DEV_RECORDER=0      — explicit per-developer opt-out.
#
# Idempotent: reinstalls only when the built agent binary actually changed, so
# incremental compiles don't churn launchd.
# ---------------------------------------------------------------------------
set -u

note() { echo "note: dev-recorder: $*"; }

# 1. Debug only. This is the gate that actually protects your own release builds.
if [[ "${CONFIGURATION:-}" != "Debug" ]]; then
  note "skip (CONFIGURATION=${CONFIGURATION:-unset})"; exit 0
fi

# 2. Real build/run only — not archive (ACTION=install) or index builds.
if [[ "${ACTION:-build}" != "build" ]]; then
  note "skip (ACTION=${ACTION:-unset})"; exit 0
fi

# 3. Never in CI. (ci.yml / release.yml build via swift + package scripts, never
#    xcodebuild of this target, so this is defensive against a future change.)
if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ]]; then
  note "skip (CI)"; exit 0
fi

# 4. Explicit opt-out.
if [[ "${MYTHLOG_DEV_RECORDER:-1}" == "0" ]]; then
  note "skip (MYTHLOG_DEV_RECORDER=0)"; exit 0
fi

# Source the helpers from SwiftPM's build dir, NOT the app bundle. The bundle
# copies get re-signed with the app-sandbox entitlement during Xcode's final
# signing phase; a sandboxed mythlogctl would resolve the App Group container
# instead of the ~/Library layout, and a sandboxed agent launched by a plain
# LaunchAgent would mismatch that config. The .build binaries carry no
# entitlements, so both mythlogctl and the agent run unsandboxed and coherent.
# (xcode-copy-helpers.sh, the prior phase, has already built them here.)
BIN_PATH="$(cd "${SRCROOT:?}" && xcrun swift build -c debug --show-bin-path 2>/dev/null)"
CTL="$BIN_PATH/mythlogctl"
AGENT_SRC="$BIN_PATH/mythlog-agent"

if [[ ! -x "$CTL" || ! -x "$AGENT_SRC" ]]; then
  note "skip (helpers not found under $BIN_PATH — did xcode-copy-helpers.sh run?)"; exit 0
fi

# Point the LaunchAgent at a STABLE installed location, not the DerivedData copy
# (which vanishes on a clean). Refresh it from the just-built binary each build.
INSTALL_BIN_DIR="$HOME/Library/Application Support/MythLog/bin"
AGENT_DEST="$INSTALL_BIN_DIR/mythlog-agent"
STAMP="$INSTALL_BIN_DIR/.dev-agent.sha256"

mkdir -p "$INSTALL_BIN_DIR"
NEW_SHA="$(/usr/bin/shasum -a 256 "$AGENT_SRC" | awk '{print $1}')"
OLD_SHA="$(cat "$STAMP" 2>/dev/null || true)"

# Idempotency: if the binary is unchanged AND the agent is already loaded, do
# nothing so incremental builds stay quiet.
if [[ "$NEW_SHA" == "$OLD_SHA" ]] && "$CTL" agent-status >/dev/null 2>&1; then
  note "up to date (agent loaded, binary unchanged)"; exit 0
fi

install -m 755 "$AGENT_SRC" "$AGENT_DEST"

# The app's real legacy installer: writes ~/Library/LaunchAgents plist, creates
# default config + HMAC secret if missing, then bootstrap + kickstart. Runs
# unsandboxed here, so it uses the ~/Library layout. Never fail the build on a
# launchd hiccup.
if "$CTL" agent-install --agent-path "$AGENT_DEST"; then
  echo "$NEW_SHA" > "$STAMP"
  note "recorder installed + started via legacy LaunchAgent ($AGENT_DEST)"
else
  note "agent-install reported an error (build not failed); run '$CTL agent-status' to inspect" >&2
fi

exit 0
