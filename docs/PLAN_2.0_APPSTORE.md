# Plan — MythLog 2.0, App Store edition

Scope: the sandboxed App Store build only (Tier A per
`docs/TECHNICAL_CAPABILITIES.md`). The Developer ID edition inherits everything
here plus its extra sources; it is not planned separately.

Companions: `docs/ARCHITECTURE_2.0.md` (module shape),
`docs/DESIGN_BRIEF_2.0.md` (product framing), and the interactive prototype.

---

## 1. What the design assumes that does not exist yet

Verified against the source. This is the real size of 2.0 — most of it is not UI.

| The design shows | Reality today | Where the work lands |
| --- | --- | --- |
| `#4629 · chained to #4628` on every row | **No record ordinal exists.** `HashChainLedger` stores `event`, `previousHash`, `hash` — no sequence number. Ordinal is implicitly the line index in JSONL. | Ledger (read side) |
| `no coverage 02:04 – 06:28` | **No coverage-gap concept.** `agent.started` events exist; nothing derives a gap. | Ledger / derivation |
| `Drives 22`, `Volume mounted — "Backup" · 2 TB` | **No drive source exists.** | New event source |
| `Display connected — LG UltraFine 5K` | **No display source exists.** | New event source |
| Locked chips (`Failed unlocks`, …) | No capability registry; the app cannot enumerate what it can and cannot observe. | Platform |
| Window-scoped category counts | Counts are not window-scoped today. | Derived state |
| Semantic zoom, 3 levels | Single fixed timeline. | New UI |

### The two subtle ones

**Record ordinals must survive rotation.** With `storage.maxLedgerFileBytes` set,
history spans `events-rotated-*.jsonl` plus the active file. Record #4,629 is
cumulative across segments, so the ordinal cannot be a line index within one
file. It needs a per-segment base count, computed once and cached, or the number
shown will be wrong the moment rotation happens.

**A coverage gap is not a stop/start pair.** The prototype's copy says *"The stop
and restart are records #4,101 and #4,102"* — which assumes a graceful stop. If
the recorder is killed, crashes, or the Mac loses power, **no stop record is
written**. Gap detection therefore has to work from *absence*: an `agent.started`
record whose predecessor is far older than the heartbeat interval. Otherwise the
one case that matters most — someone force-quit the recorder — is exactly the
case that shows no gap. Worth confirming this is what the designer intended,
because the copy currently implies otherwise.

---

## 2. Spikes first

Two unknowns could invalidate the design. Answer them before committing.

**S1 — Timeline performance.** Build a throwaway SwiftUI view over a synthetic
ledger of ~2M records. Drive continuous zoom from 15h to 10min. Confirm the
bucket aggregation can be pre-computed and reused rather than recalculated per
frame, and measure the frame time. **If continuous zoom cannot hold up, the
interaction model changes** — stepped zoom between fixed levels is the fallback,
and the designer needs to know early.

**S2 — Ordinal cost.** Confirm cumulative record ordinals can be computed across
rotated segments without reading every file on every load. A per-segment count
cached alongside the segment is the likely answer; verify it survives rotation
and verification.

Both are throwaway code. Neither ships.

---

## 3. Phases

Each phase is independently shippable and independently revertible. Phases 1–3
ship into **1.x releases** — they improve the app that exists and de-risk 2.0.
Phases 5–8 build behind a flag and ship together as 2.0.

### Phase 1 — Split `MythLogCore`
Per `ARCHITECTURE_2.0.md`: `MythLogPrimitives` → `MythLogLedger` →
`MythLogPlatform` → `MythLogConfig`. Purely mechanical: move files, widen access,
fix imports. No behaviour change, so the existing suite is the safety net.

Do this first so every later phase lands on the right foundation, and so the
ledger module is small and isolated before anyone audits it.

**Gate:** full suite green; `MythLogLedger` imports nothing but Foundation,
CryptoKit, and `MythLogPrimitives`.

### Phase 2 — Data foundations *(ships in 1.x)*
- Cumulative record ordinals, rotation-safe (S2's answer).
- Coverage-gap derivation from absence, not from stop/start pairs.
- A capability registry: which sources this build can observe, and why not when
  it cannot. Extends `SandboxEnvironment.unavailableReason` rather than
  inventing a parallel mechanism.

**Gate:** unit tests for ordinals across a rotated ledger, and for gap detection
where the recorder was killed without a stop record.

### Phase 3 — New Tier A event sources *(ships in 1.x, one at a time)*
- **Drives** — `NSWorkspace.didMountNotification` / `didUnmountNotification`.
- **Displays** — `CGDisplayRegisterReconfigurationCallback`.
- **User switching** — `NSWorkspace.sessionDidBecomeActiveNotification` /
  `…ResignActive`.

Each is small, sandbox-safe, and independently valuable. Shipping them before
2.0 means the redesign launches with real data in every category rather than
empty ones.

**Constraint:** any new field on `AlarmEvent` must be `Optional` defaulting to
`nil`, or verification of existing ledgers breaks retroactively — see
`TECHNICAL_CAPABILITIES.md` §4. Prefer `metadata` where it fits.

**Gate:** each source verified on hardware; `CGDisplayRegisterReconfigurationCallback`
and the session notifications are currently marked *inferred* for sandbox
availability and must be confirmed, not assumed.

### Phase 4 — Extract `MythLogDesign`
Tokens and primitives out of `SharedUI`. Mechanical. Gives the 2.0 component
inventory somewhere principled to land.

### Phase 5 — Timeline canvas *(the hard one)*
**One component, three renderers.** A single `TimelineCanvas` with a level enum —
not `DensityView` / `ClusterView` / `NodeView`. Selection, hover, window state,
and the coverage-gap overlay must behave identically at every level; splitting
them is how the gap hatching and selection drift apart.

Includes: window state, continuous zoom with derived level, ⌘+/⌘−/⌘0, ctrl-wheel
(how trackpad pinch arrives), presets, click-a-bar-to-zoom, and the 10-minute
minimum span.

**Gate:** S1's performance target met with the real ledger; gap renders correctly
at all three levels.

### Phase 6 — Event list and inspector
Window-slaved list with the 60-row cap and honest `newest N of M` labelling.
Inspector with payload and provenance.

**Decide during this phase:** what the inspector shows when the selected record
is filtered out. The prototype currently keeps displaying it while the list says
`0 events`.

### Phase 7 — Integrity states
The four banners — verified, failed, truncated, anchor-offline — plus per-record
verdict (`Verified` / `Untrusted` by position relative to the break). This is the
screen the product exists for; it is not polish.

### Phase 8 — First run
Two-column *what it records / what it never records*, recorder install with its
waiting state, optional watch-folders grant.

Must make "installed and running" unmistakable — 1.0.0 shipped a bug where the
app kept asking to install after a successful install.

### Phase 9 — Accessibility, Dynamic Type, localisation
Not a final polish pass — budget it as real work. The prototype has **no ARIA,
roles, or tab order**, so the entire accessibility layer is authored fresh in
SwiftUI. `docs/ACCESSIBILITY.md` describes guarantees already made publicly:
VoiceOver reads the timeline chronologically and skips decoration, every control
is keyboard-reachable, severity never relies on colour alone, Reduce Motion is
respected. A canvas with three renderers and a data table are the two hardest
things to satisfy those with.

**Gate:** the existing accessibility smoke test in `RELEASE_CHECKLIST.md` passes
against the new UI.

---

## 4. Sequencing summary

```
1.x releases:        Phase 1 → Phase 2 → Phase 3 (drives, displays, switching)
Behind a flag:       Phase 4 → 5 → 6 → 7 → 8 → 9
2.0 release:         flag on
```

Spikes S1 and S2 run before Phase 2 and Phase 5 respectively.

## 5. Explicitly out of scope

- Any Tier B source (failed unlocks, permission prompts, remote access, USB
  identity). They appear only as locked chips in this edition.
- Actor attribution ("which process changed this file") — Tier C, requires an
  Apple entitlement the project does not have.
- Per-event user/session identity — a schema change with no Tier A source to
  populate it.
- Binary rename (`mythlogd` / `mythlog-cli`). Cosmetic, breaking, and unrelated
  to shipping 2.0.

## 6. Open decisions

1. Do level transitions animate, or snap? The prototype snaps. A cross-fade is
   cheap in SwiftUI and would make semantic zoom legible — ask the designer
   whether snapping was intent or a prototype shortcut.
2. Inspector behaviour when the selection is filtered out.
3. Zero-count chip vs locked chip: both show nothing, and they must never be
   confusable. One means "nothing happened", the other "I cannot see".
4. Does the 60-row cap stay, or does the list virtualise fully?
