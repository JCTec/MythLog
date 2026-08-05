#!/usr/bin/env bash
set -euo pipefail

# Layering gate for MythLogPlayground.
#
# Everything lives in one app target, which is the right call — but folders are
# a convention, and nothing stops `Ledger/` importing `DesignSystem/` except
# discipline. In a multi-module layout the compiler enforced that for free. This
# script buys it back.
#
# It checks three things:
#
#   1. Framework imports.       Which modules a layer may `import`.
#   2. Cross-layer references.  Which layers' types a layer may name. There are
#                               no import statements to inspect inside a single
#                               module, so this works from the declared type
#                               names in each layer.
#   3. Storage-path resolution. That exactly one file derives a storage path.
#
# The load-bearing rule is the Ledger one. That folder is the audit target:
# someone should be able to read it alone and satisfy themselves the chain is
# sound. Anything in there beyond Foundation and CryptoKit is a defect.
#
# Usage:
#   Scripts/check-layering.sh              # check
#   Scripts/check-layering.sh --self-test  # prove it fails on a real violation
#
# Written for bash 3.2, which is what macOS ships — no associative arrays.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SOURCES="Sources"
STORAGE_RESOLUTION_FILE="$SOURCES/Platform/StorageLocations.swift"

if ! command -v rg >/dev/null 2>&1; then
  echo "Missing required tool: rg (brew install ripgrep)" >&2
  exit 1
fi

failures=0

fail() {
  failures=$((failures + 1))
  echo "" >&2
  echo "LAYERING VIOLATION — $1" >&2
  shift
  while [ "$#" -gt 0 ]; do
    echo "  $1" >&2
    shift
  done
}

layers() {
  echo "Primitives Ledger Platform Config Model Mock DesignSystem Previews App"
}

# Source lines with comment-only lines removed.
#
# A doc comment that names a type in another layer is documentation, not a
# dependency — `AlarmEvent` explaining how `LedgerHashChain` uses it is exactly
# the cross-reference a reader wants. Only code creates coupling, so only code
# is checked.
code_lines() {
  rg --no-heading --line-number -g '*.swift' "$2" "$1" 2>/dev/null \
    | rg -v ':\s*(///|//|\*)' || true
}

# --- 1. Framework imports -----------------------------------------------------
#
# Foundation is allowed everywhere and omitted from each list.

allowed_imports() {
  case "$1" in
    Primitives)   echo "" ;;                       # Foundation only
    # The audit target. CryptoKit for the HMAC; Darwin for `flock(2)`, which has
    # no Foundation equivalent and which the chain's correctness depends on —
    # without it a reader can observe a half-written record and call it tampering.
    # Darwin is the C library, not a framework, and admitting it here keeps the
    # locking visible in the folder an auditor reads rather than hiding it behind
    # an indirection in another layer.
    Ledger)       echo "CryptoKit Darwin" ;;
    Platform)     echo "OSLog Security Darwin" ;;
    Config)       echo "" ;;
    Model)        echo "SwiftUI Observation" ;;    # view models: colours, symbols
    Mock)         echo "" ;;
    DesignSystem) echo "SwiftUI Observation" ;;
    Previews)     echo "SwiftUI" ;;
    App)          echo "SwiftUI" ;;
    *)            echo "" ;;
  esac
}

check_imports() {
  local layer="$1"
  local dir="$SOURCES/$layer"
  [ -d "$dir" ] || return 0

  local allowed
  allowed="Foundation $(allowed_imports "$layer")"

  local entry file module
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    file="${entry%%:*}"
    module="${entry##*:}"
    case " $allowed " in
      *" $module "*) ;;
      *)
        fail "$layer/ may not import $module" \
             "$file" \
             "$layer/ may import: $allowed"
        ;;
    esac
    # `rg -o` with a capture group prints only the module name; pairing it with
    # `--with-filename` keeps the offending file in the message.
  done < <(rg --no-heading --no-line-number --with-filename -o -g '*.swift' \
             '^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)' -r '$1' "$dir" 2>/dev/null || true)
}

# --- 2. Cross-layer type references -------------------------------------------

allowed_layers() {
  case "$1" in
    Primitives)   echo "" ;;
    Ledger)       echo "Primitives" ;;
    Platform)     echo "Primitives" ;;
    Config)       echo "Primitives Platform" ;;
    # The bridge: view models are where the engine meets the interface.
    Model)        echo "Primitives Ledger Platform Config" ;;
    Mock)         echo "Primitives Model" ;;
    # Never Ledger, Platform, or Config directly — always through a view model.
    DesignSystem) echo "Primitives Model" ;;
    # Composition roots. They decide where data comes from, which is precisely
    # the decision every other layer must not make. Nothing may reference them.
    Previews)     echo "Primitives Ledger Platform Config Model Mock DesignSystem" ;;
    App)          echo "Primitives Ledger Platform Config Model Mock DesignSystem" ;;
    *)            echo "" ;;
  esac
}

# Top-level type names declared in a layer.
declared_types() {
  local dir="$SOURCES/$1"
  [ -d "$dir" ] || return 0
  rg --no-heading --no-line-number --no-filename -o -g '*.swift' \
    '^(?:@[A-Za-z]+\s+)*(?:public |internal |private |fileprivate |final |indirect )*(?:struct|enum|class|actor|protocol) +([A-Z][A-Za-z0-9_]*)' \
    -r '$1' "$dir" 2>/dev/null | sort -u || true
}

check_layer_references() {
  local layer="$1"
  local dir="$SOURCES/$layer"
  [ -d "$dir" ] || return 0

  local allowed other name hits
  allowed="$(allowed_layers "$layer")"

  for other in $(layers); do
    [ "$other" != "$layer" ] || continue
    case " $allowed " in
      *" $other "*) continue ;;
    esac
    [ -d "$SOURCES/$other" ] || continue

    for name in $(declared_types "$other"); do
      hits="$(code_lines "$dir" "\b$name\b")"
      if [ -n "$hits" ]; then
        fail "$layer/ may not reference $other/ (found \`$name\`)" \
             "$(echo "$hits" | head -3)" \
             "$layer/ may reference: ${allowed:-nothing}"
      fi
    done
  done
}

# --- 3. Storage-path resolution -----------------------------------------------
#
# The 1.0.0 bug: the viewer resolved the ledger from a bare default config
# carrying `~/Library/Application Support/MythLog/events.jsonl` while the
# recorder wrote to the App Group container. Under the sandbox `~` expands to a
# process-private container, so the two named different files — and a wrong path
# is indistinguishable from an empty history.

check_storage_resolution() {
  local hits

  # 3a. Only the resolution point may name the ledger file.
  hits="$(code_lines "$SOURCES" '"events\.jsonl"' | grep -v "^$STORAGE_RESOLUTION_FILE:" || true)"
  if [ -n "$hits" ]; then
    fail "the ledger filename may only appear in $STORAGE_RESOLUTION_FILE" \
         "$hits" \
         "Derive it from StorageLocations.ledgerURL instead."
  fi

  # 3b. No tilde-rooted path may be resolved. Under the sandbox `~` expands to a
  #     process-private container, so a tilde default can never be correct for
  #     shared storage — and must not be reachable at all.
  #
  #     What is forbidden is a tilde-rooted *path*: `"~/` followed by something.
  #     A bare `"~/"` — the argument to a `hasPrefix` check — is a detector, not
  #     a path, and `Config/ConfigValidation.swift` exists precisely to find
  #     these in a user's config and complain about them. Banning the detector
  #     along with the thing it detects would mean the only way to warn about a
  #     tilde path is to not warn about it.
  #
  #     `Sources/Mock/` is exempt: its tildes are display text inside fixture
  #     event descriptions ("~/Documents/lease.pdf"), never resolved into a URL.
  #     Rule 3e closes that door for every layer including Mock, so the exemption
  #     cannot be used to smuggle in a real path.
  hits="$(code_lines "$SOURCES" '"~/[^"]' | grep -v "^$SOURCES/Mock/" || true)"
  if [ -n "$hits" ]; then
    fail "tilde-rooted path literals are forbidden outside Sources/Mock/" \
         "$hits" \
         "Under the App Sandbox \`~\` expands to a process-private container." \
         "Resolve through StorageLocations, which is container-aware."
  fi

  # 3c. Only the resolution point may ask where home is.
  hits="$(code_lines "$SOURCES" 'homeDirectoryForCurrentUser|NSHomeDirectory\(\)' \
          | grep -v "^$STORAGE_RESOLUTION_FILE:" || true)"
  if [ -n "$hits" ]; then
    fail "only $STORAGE_RESOLUTION_FILE may resolve the home directory" \
         "$hits"
  fi

  # 3d. Only SharedContainer may ask macOS for the App Group container.
  hits="$(code_lines "$SOURCES" 'containerURL\(forSecurityApplicationGroupIdentifier' \
          | grep -v "^$SOURCES/Platform/SharedContainer.swift:" || true)"
  if [ -n "$hits" ]; then
    fail "only Platform/SharedContainer.swift may resolve the App Group container" \
         "$hits"
  fi

  # 3e. Nothing, anywhere, may expand a tilde. This is the operation that turned
  #     a harmless-looking default into the 1.0.0 bug: the string is only
  #     dangerous at the moment something resolves it.
  hits="$(code_lines "$SOURCES" 'expandingTildeInPath|standardizingPath' || true)"
  if [ -n "$hits" ]; then
    fail "tilde expansion is forbidden everywhere" \
         "$hits" \
         "A tilde expands to a process-private container under the sandbox," \
         "so the expansion is correct in the viewer and wrong in the recorder."
  fi
}

# --- 4. Escape hatches must be justified --------------------------------------
#
# Not a layering rule, but the same kind of gate: `@unchecked Sendable`,
# `nonisolated(unsafe)`, and `@preconcurrency` are each allowed only with a
# comment on the line above explaining why they are *correct*.

check_concurrency_escape_hatches() {
  local hits entry file line
  # Comment lines are excluded: prose *about* these annotations — including the
  # notes in RESEARCH_NOTES.md's neighbours explaining why they were not used —
  # is not a use of them.
  hits="$(code_lines "$SOURCES" '@unchecked Sendable|nonisolated\(unsafe\)|@preconcurrency')"
  [ -n "$hits" ] || return 0

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    # `file:line:content`; content may contain colons, so take the first two
    # fields only.
    file="$(printf '%s' "$entry" | sed -E 's/^([^:]+):([0-9]+):.*/\1/')"
    line="$(printf '%s' "$entry" | sed -E 's/^([^:]+):([0-9]+):.*/\2/')"
    [ "$line" -gt 1 ] 2>/dev/null || line=2

    if ! sed -n "$((line - 1))p" "$file" | rg -q '//'; then
      fail "a concurrency escape hatch with no justification" \
           "$entry" \
           "@unchecked Sendable, nonisolated(unsafe), and @preconcurrency each" \
           "require a comment on the line above explaining why the use is" \
           "correct, not why it was convenient."
    fi
  done <<< "$hits"
}

# Returns non-zero if anything was found, so the self-test can tell whether a
# deliberate violation was actually rejected.
run_checks() {
  failures=0
  local layer
  for layer in $(layers); do
    check_imports "$layer"
    check_layer_references "$layer"
  done
  check_storage_resolution
  check_concurrency_escape_hatches
  [ "$failures" -eq 0 ]
}

# --- Self-test ----------------------------------------------------------------
#
# A gate nobody has watched fail is a gate nobody knows works. This introduces
# one real violation of each rule, confirms the check catches it, and removes it
# again.

PROBE_FILE="$SOURCES/Ledger/__layering_probe.swift"
probe_passed=0
probe_total=0

probe_case() {
  local description="$1"
  local body="$2"
  probe_total=$((probe_total + 1))
  printf '%s\n' "$body" > "$PROBE_FILE"
  # In a subshell so the probe's failures do not pollute the real tally.
  if (run_checks) >/dev/null 2>&1; then
    echo "  NOT CAUGHT: $description" >&2
  else
    echo "  caught: $description"
    probe_passed=$((probe_passed + 1))
  fi
  rm -f "$PROBE_FILE"
}

self_test() {
  trap 'rm -f "$PROBE_FILE"' EXIT

  echo "Self-test — each case is a real violation the gate must reject:"

  probe_case "Ledger/ importing SwiftUI" \
    'import SwiftUI
enum LayeringProbe {}'

  probe_case "Ledger/ referencing a Platform type" \
    'import Foundation
enum LayeringProbe { static func probe(_ value: StorageLocations) {} }'

  probe_case "a second file naming the ledger file" \
    'import Foundation
enum LayeringProbe { static let path = "events.jsonl" }'

  probe_case "a tilde-rooted path literal" \
    'import Foundation
enum LayeringProbe { static let path = "~/Library/Application Support/MythLog" }'

  probe_case "resolving the home directory outside StorageLocations" \
    'import Foundation
enum LayeringProbe { static let home = FileManager.default.homeDirectoryForCurrentUser }'

  probe_case "an unjustified @unchecked Sendable" \
    'import Foundation
final class LayeringProbe: @unchecked Sendable {}'

  echo ""
  if [ "$probe_passed" -eq "$probe_total" ]; then
    echo "Self-test passed: $probe_passed/$probe_total violations caught."
    return 0
  fi
  echo "Self-test FAILED: only $probe_passed/$probe_total violations caught." >&2
  return 1
}

if [ "${1:-}" = "--self-test" ]; then
  self_test || exit 1
  echo ""
  echo "Now checking the real tree:"
fi

if ! run_checks; then
  echo "" >&2
  echo "$failures layering violation(s)." >&2
  exit 1
fi

echo "Layering checks passed."
