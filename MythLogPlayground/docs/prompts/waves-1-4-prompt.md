# Effort: Waves 1–4 — bring the engine into MythLogPlayground

Read this whole prompt, then `docs/EXTRACTION_PLAN.md`, before writing code.

Work on a branch named `engine/waves-1-4`. Commit after each wave passes its
gate. Never push. Never weaken a gate, delete a test, or silence a warning to get
green. If blocked twice on the same problem, write `BLOCKED.md` at the repository
root with exactly what you tried, then continue with the next independent piece.

## Where to run

Run from the repository root — the `Logging System/` directory. That is the git
root, so branching and committing only work from there, and the shipping engine
you are porting from lives there.

Two trees matter:

| Path | Role | Access |
| --- | --- | --- |
| `MythLogPlayground/` | The app you are building | **Read and write** |
| Everything else at the root (`Sources/`, `docs/`, `scripts/`, `Xcode/`, …) | The shipping app | **Read only** |

**The read-only rule is absolute and is verified, not trusted.** After every
wave, run:

```sh
git status --porcelain | grep -v '^.. MythLogPlayground/' && echo "VIOLATION" || echo "clean"
```

If anything outside `MythLogPlayground/` is modified, revert it before
committing. The shipping app is live, on the App Store, and being fixed on its
own track — a stray edit here is a production risk, not a tidiness problem.

## What exists

`MythLogPlayground/` is a standalone macOS app: design system and UI, driven by
`Sources/Mock/MockLedger.swift` (paths inside the playground are relative to it).
It renders a timeline at three zoom levels, an event list, filters, and an
inspector. It has no engine — no ledger, no file I/O, no recorder.

The shipping app at the repository root has a working engine, chiefly in
`Sources/MythLogCore/`. **It is reference material.** Read it, learn from it,
copy behaviour — never import it, never edit it, never make the playground depend
on it. The point is to carry the behaviour forward without inheriting the shape:
41 files in one flat directory is the thing being left behind.

## Scope

Waves 1–4 from `docs/EXTRACTION_PLAN.md`, ending at the milestone: **the existing
UI rendering a real ledger written by the shipping app.**

Out of scope: capture sources, the agent runtime, `SMAppService`, notifiers,
Telegram. Do not start them.

---

## Phase 0 — Research, before any code

Swift 6 concurrency guidance changed substantially and most of the internet is
stale. Ground this work in primary sources only:

- `developer.apple.com` — documentation, WWDC session transcripts, sample code.
- `swift.org` — the language guide, evolution proposals, migration guide.

Read specifically on: strict concurrency checking, `Sendable` conformance and
when `@unchecked` is legitimate, actor isolation and `nonisolated`, `sending`
parameters, `AsyncSequence` / `AsyncStream`, structured concurrency and
`TaskGroup`, cancellation, and current property-wrapper guidance alongside the
Observation framework.

Do **not** build the design on a blog post, a Stack Overflow answer, or an LLM
recollection — including your own. If you cannot verify a concurrency claim
against Apple or swift.org, treat it as unknown and say so.

Write `docs/RESEARCH_NOTES.md`: what you verified, the source URL, and the date.
Where a decision could reasonably go two ways, record both and why you chose.

---

## Showcase requirements

This code is meant to be read. Someone auditing it should come away thinking the
author understood modern Swift — not that they sprinkled keywords.

**Swift 6 strict concurrency, complete.** `SWIFT_STRICT_CONCURRENCY: complete` is
already set in `project.yml`. Zero warnings. Never reach for
`@preconcurrency`, `@unchecked Sendable`, or `nonisolated(unsafe)` to make an
error disappear — each is allowed only with a comment explaining why it is
*correct*, not why it was convenient.

**`async`/`await` where it earns its place.** File reads, verification, and
bucket aggregation are genuinely asynchronous and genuinely cancellable. Show:

- An `actor` owning ledger file access, so concurrent readers serialise without
  locks.
- `AsyncSequence` / `AsyncStream` for streaming records rather than loading a
  whole ledger into memory — a two-year ledger will not fit comfortably.
- `TaskGroup` for verifying rotated segments concurrently, since each segment's
  internal chain is independent until the seam.
- Real cancellation: `Task.checkCancellation()` in loops. Zoom changes fire
  rapidly and every superseded computation must die immediately.

Do not make something `async` that is pure computation on values already in
memory. Gratuitous suspension points are noise.

**`Sendable`, deliberately.** Model types are `Sendable` value types.
Cross-actor boundaries are explicit. Where a reference type must cross, prefer
redesigning it as a value. Use `sending` where ownership transfer is the honest
description. Every `@unchecked Sendable` needs a comment that would satisfy a
reviewer.

**Property wrappers, where they carry weight.** A showcase, not a decoration —
two or three excellent ones beat a dozen thin ones. Strong candidates in this
domain:

- `@Clamped` — a window span that cannot be constructed outside
  `minimumSpan...fullHistory`, making an invalid window unrepresentable rather
  than validated after the fact.
- `@Cached` / memoisation keyed on window + filter — bucket aggregation is the
  hot path behind continuous zoom, and this is where a wrapper genuinely removes
  repetition instead of hiding it.
- A file-backed configuration wrapper, *if* it reads better than a plain
  `load`/`save` — justify it or skip it.

Reject any wrapper that makes call sites harder to reason about. Explain each
one's justification in a doc comment.

---

## Wave 1 — Primitives and Ledger

Create `Sources/Primitives/` and `Sources/Ledger/`.

Port the event model, canonical JSON, hex encoding, hash chain, file lock,
anchor, and proof export.

Two improvements land here:

**Cumulative record ordinals.** The UI shows `#4629 · chained to #4628` on every
row. There is no ordinal in the current model. It must be cumulative **across
rotated segments**, so it cannot be a line index within one file. Carry a
per-segment base count, computed once and cached beside the segment.

**Additive-only schema, permanently.** `computeHash` HMACs the canonical JSON of
the whole event, and verification re-encodes stored records to recheck them. **A
new non-optional field retroactively breaks verification of every ledger a user
already has.** New fields are `Optional`, default `nil`, never reordered, never
renamed. Put this as a doc comment on the event type so nobody rediscovers it the
hard way.

**Gate:** a ledger written by the shipping app verifies here, with correct
cumulative ordinals across rotated segments. Add tests for a rotated ledger, a
tampered record, and a truncated file.

## Wave 2 — Platform

Create `Sources/Platform/`. Sandbox detection, shared container resolution,
installation paths, entitlement reading.

**One resolution point, enforced.** The 1.0.0 bug: the viewer read `~/Library/…`
while the recorder wrote to the App Group container, so the app reported
"Recorder Not Running" forever while the recorder was healthy — under the sandbox
`~` expands to a *process-private* container. One type answers "where does
everything live". Nothing else derives a storage path.

Write `Scripts/check-layering.sh` and make it fail the build on a storage path
derived from a bare default config, and on any import that violates:

| Layer | May reference |
| --- | --- |
| `Primitives/` | Foundation only |
| `Ledger/` | Primitives, CryptoKit |
| `Platform/` | Primitives |
| `Config/` | Primitives, Platform |
| `DesignSystem/` | Primitives and view models only |

The ledger rule is load-bearing: that folder is the audit target and must read
cleanly on its own.

**Gate:** the script passes, and fails when you deliberately introduce a
violation. Prove both.

## Wave 3 — Config

Create `Sources/Config/`. Schema and validation. Container-aware defaults from
the start — the tilde-path default must never be reachable for storage paths.

**Gate:** a config written by the shipping app round-trips unchanged.

## Wave 4 — Real data *(the milestone)*

Replace `MockLedger` as the UI's source with a real loader reading an actual
ledger from disk.

- Keep `MockLedger` behind a switch. Previews and design work need determinism,
  and a fixture with a known gap and a known burst stays valuable.
- Loading is `async`, streaming, and cancellable.
- Derive the coverage gap **from absence, not from a stop/start pair.** A
  graceful stop writes a record; a force-quit, crash, or power loss does not —
  and that is precisely the case a frightened user cares about. Detect a gap as a
  start record whose predecessor is older than the heartbeat interval allows, and
  treat any stop record as extra detail.
- Window-scoped category counts recompute per window, off the main actor,
  cancellable.

**Gate:** timeline, list, counts, and inspector render months of real history at
every zoom level, with a real gap and a real burst visible, and no main-thread
stall while zooming.

---

## Verification

- Zero strict-concurrency warnings.
- `Scripts/check-layering.sh` passes, and demonstrably fails on a violation.
- Tests: rotation, tampering, truncation, ordinal continuity, gap-from-absence.
- Load a ledger of at least 100k records and confirm zoom stays responsive.
- Every `@unchecked Sendable`, `nonisolated(unsafe)`, and property wrapper has a
  doc comment justifying it.

## Human checklist

Write `HUMAN_CHECKLIST-ENGINE.md`:

- Point the app at a real ledger from the shipping app and confirm the history
  matches what the shipping app shows.
- Confirm a ledger that fails verification is reported as failing, not as empty.
- Confirm the coverage gap appears for a recorder that was force-quit, not only
  one stopped cleanly.
