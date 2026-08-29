---
description: Port the MythLog engine into MythLogPlayground (Waves 1–4)
argument-hint: "[wave number to start from, default 1]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, WebFetch, WebSearch, TodoWrite
---

Port the MythLog engine into the playground app, Waves 1–4, ending with the
playground UI rendering a real ledger.

Start from wave: $ARGUMENTS (default: 1)

## Read first

1. `MythLogPlayground/docs/prompts/waves-1-4-prompt.md` — the full brief. It is
   authoritative; everything below is a summary you must not let drift from it.
2. `MythLogPlayground/docs/EXTRACTION_PLAN.md` — wave definitions and the eight
   improvements to make during the port.

## Non-negotiable constraints

**Blast radius.** `MythLogPlayground/` is writable. Everything else in this
repository is **read only** — it is the shipping app, live on the App Store.
Read it freely to learn the engine; never edit it.

Verify after every wave, and before every commit:

```sh
git status --porcelain | grep -v '^.. MythLogPlayground/' | grep -v '^.. .claude/' && echo VIOLATION || echo clean
```

If it prints VIOLATION, revert those paths before continuing.

**Branch.** Work on `engine/waves-1-4`, cut from the current branch. Commit after
each wave passes its gate. **Never push.**

**Never fake green.** Do not weaken a gate, delete or skip a test, or silence a
warning to make something pass. If blocked twice on the same problem, write
`BLOCKED.md` at the repository root describing exactly what you tried, then move
to the next independent piece.

## Phase 0 — Research before code

Swift 6 concurrency guidance changed substantially and most of the web is stale.
Use primary sources only: `developer.apple.com` and `swift.org`.

Read on: strict concurrency, `Sendable` and when `@unchecked` is legitimate,
actor isolation and `nonisolated`, `sending` parameters, `AsyncSequence` /
`AsyncStream`, `TaskGroup`, cancellation, and property wrappers alongside
Observation.

If a concurrency claim cannot be verified against those two domains, treat it as
unknown and say so — including your own recollection.

Write `MythLogPlayground/docs/RESEARCH_NOTES.md`: claim, source URL, date.

## The waves

1. **Primitives + Ledger** — event model, canonical JSON, hash chain, lock,
   anchor, proof export. Add **cumulative record ordinals across rotated
   segments** (not line indices) and the **additive-only schema** rule as a doc
   comment on the event type: a new non-optional field retroactively breaks
   verification of every ledger a user already has.
2. **Platform** — sandbox detection, container, paths, entitlements. **One
   resolution point** for storage paths, plus `Scripts/check-layering.sh`
   enforcing layer imports. Prove the script fails on a deliberate violation.
3. **Config** — schema and validation, container-aware defaults only.
4. **Real data (the milestone)** — replace `MockLedger` as the UI's source with
   a streaming, cancellable loader over a real ledger. Keep `MockLedger` behind a
   switch for previews. Derive coverage gaps **from absence, not stop/start
   pairs** — a force-quit writes no stop record, and that is the case that
   matters most.

Out of scope: capture sources, agent runtime, `SMAppService`, notifiers,
Telegram.

## Showcase requirements

This code is meant to be read by someone auditing it.

- **Swift 6 strict concurrency, zero warnings.** `@preconcurrency`,
  `@unchecked Sendable`, and `nonisolated(unsafe)` each require a comment
  explaining why they are *correct*, not convenient.
- **async/await where it earns its place** — an `actor` owning ledger file
  access, `AsyncSequence` streaming (a two-year ledger will not fit in memory),
  `TaskGroup` verifying rotated segments in parallel, real
  `Task.checkCancellation()` because zoom fires rapidly. Do not make pure
  in-memory computation `async`.
- **Sendable deliberately** — value types across boundaries, `sending` where
  ownership transfer is the honest description.
- **Property wrappers that carry weight** — two or three excellent ones, not a
  dozen thin ones. Strong candidates: `@Clamped` making an invalid time window
  unrepresentable, and a memoisation wrapper on bucket aggregation (the hot path
  behind continuous zoom). Justify each in a doc comment; reject any that makes
  call sites harder to reason about.

## Definition of done

- Zero strict-concurrency warnings.
- `Scripts/check-layering.sh` passes, and demonstrably fails on a violation.
- Tests: rotation, tampering, truncation, ordinal continuity, gap-from-absence.
- A ledger written by the shipping app loads, verifies, and renders at every zoom
  level with a real gap and a real burst visible.
- `git status` clean outside `MythLogPlayground/`.
- `MythLogPlayground/docs/RESEARCH_NOTES.md` and
  `HUMAN_CHECKLIST-ENGINE.md` written.

Use TodoWrite to track the waves and report progress as you go.
