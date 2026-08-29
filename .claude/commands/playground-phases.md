---
description: MythLogPlayground — integrity states, ledger picker, anchor groundwork
argument-hint: "[A | B | C | all]  default: all"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, WebFetch, WebSearch, TodoWrite
---

Three phases for `MythLogPlayground/`. Each is independent and shippable alone.
Do: $ARGUMENTS (default: all, in order).

## Read first

- `MythLogPlayground/README.md` — structure, conventions, known gaps
- `MythLogPlayground/docs/ANCHOR_DESTINATIONS.md` — needed for Phase C
- `Sources/Model/ZoomLevel.swift` — `IntegrityState` already carries every
  string Phase A needs

## Constraints

**Blast radius.** `MythLogPlayground/` is writable. Everything else in this
repository is read-only — it is the shipping app, live on the App Store. Verify
before each commit:

```sh
git status --porcelain | grep -v '^.. MythLogPlayground/' | grep -v '^.. .claude/' && echo VIOLATION || echo clean
```

**Branch** `playground/phases`, commit per phase, never push.

**Gates must stay green.** `./Scripts/check-layering.sh --self-test` and the test
suite pass before every commit. Never weaken a gate to get there.

**Conventions are not optional:** nested types (`MainPage.Model`, not
`MainPageViewModel`), `Owner+Aspect.swift` filenames, one primary type per file,
no `Utils`/`Helpers`, every colour and size through `Tokens/`. Swift 6 strict
concurrency, zero warnings, no `@unchecked Sendable` or `nonisolated(unsafe)`
without a comment justifying correctness.

---

## Phase A — Render the integrity states

**This is the screen the product exists for, and it is currently invisible.**
`IntegrityState` models `verified`, `failed`, `truncated`, and `anchorOffline`
with full copy. Nothing renders any of them.

Build:

- `IntegrityBanner` (Organism) — icon, title, body, primary action, optional
  secondary. Shown above the event list whenever the state is not `verified`.
- **Per-record verdict in the inspector.** Trust is positional: after a break at
  #3,201, later records are `Untrusted` even though each looks individually fine.
  `InspectorPanel` already has `isTrusted`; make it visible and unmissable.
- **A visible boundary in the list and timeline** at the point verification
  fails. Someone must be able to see where trustworthy history ends without
  reading a number.
- Header treatment per state — the badge already switches colour; confirm it
  reads correctly in each.

**Do not** let a failing ledger render as an empty or calm window. That is the
failure mode this whole product guards against.

**Gate:** all four states reachable in previews over the fixture, each visually
distinct, each legible in greyscale.

## Phase B — Find the ledger without a scheme editor

Replaces the `MYTHLOG_LEDGER` / `MYTHLOG_HMAC_KEY_HEX` environment variables as
the *primary* path. Keep them working as an override for automation and for the
tamper tests in `HUMAN_CHECKLIST-ENGINE.md`, which need arbitrary paths.

Build:

- **Auto-detect, do not auto-load.** Ask `StorageLocations` whether a real ledger
  exists. If it does, offer it — *"A MythLog ledger was found at … · Open"* —
  beside the fixture. Never open real personal history unasked: this app is used
  for screenshots and design work.
- **An "Open ledger…" file picker**, which also removes the env-var requirement
  for pointing at `/tmp/ledger-copy` during tamper testing.
- **A first-run page** for the no-ledger case, reusing the two-column *what it
  records / what it never records* structure from the reference design. The line
  "Excluded by principle, not merely unimplemented" is the point of the screen.
- Remember the last opened ledger, but always show which one is loaded.

**Note the sandbox caveat in a comment:** this works because the playground is
unsandboxed. A sandboxed build could not read the App Group container it is not
entitled to, and would need a security-scoped bookmark from the picker instead.

**Gate:** a person who has never seen the project can launch it, find their
ledger, and open it without editing a scheme.

## Phase C — Anchor groundwork (no new destinations)

From `docs/ANCHOR_DESTINATIONS.md`, phases 1 and 2 only.

- **Extract `AnchorDestination` as a protocol** — write an anchor, read the
  latest, list history. Refactor the existing iCloud and directory destinations
  behind it. No behaviour change, no new destination. This makes every later
  destination purely additive.
- **Reframe the choice in the UI** from a path setting into the question it
  actually is: *who are you keeping this away from?* Plain descriptions of what
  iCloud and a chosen folder each protect against, and — this is the underrated
  one — make the USB-key case discoverable. It already works and nobody knows.
- **Surface the warning that does not exist today:** an anchor written to a
  synced folder is visible on the adversary's devices too. For someone in a
  hostile household the feature meant to protect them could announce them. Say so
  where the choice is made, not in documentation.

Do **not** build Telegram, git, OpenTimestamps, or a remote server. Groundwork
only.

**Gate:** the protocol has both existing destinations behind it, tests still
pass, and the settings copy explains the threat rather than the file path.

---

## Done

- Gates green, `git status` clean outside `MythLogPlayground/`.
- Update the "Known gaps" section of `MythLogPlayground/README.md` to reflect
  what is now built.
- Report what you did not do and why.

Use TodoWrite to track the phases.
