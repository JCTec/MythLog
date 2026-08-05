# Extraction plan — engine into the playground

Bring the working engine across from the shipping app, improving it with what
the last year taught, until the playground stops being a playground.

The old app is **read-only** during this. Nothing here imports it; files are
copied and rewritten, never referenced. That is deliberate — the point is to
carry the *behaviour* forward without inheriting the shape.

## The one thing a single target costs

Everything lives in one app target now, which is simpler and the right call. But
folders are a convention, not a boundary: nothing stops `Ledger/` importing
`DesignSystem/` except discipline. In the old multi-module layout the compiler
enforced that for free.

Recover it with a lint gate, in the style already used in the shipping repo:

```
Scripts/check-layering.sh
```

Rules it should enforce:

| Layer | May reference |
| --- | --- |
| `Primitives/` | nothing but Foundation |
| `Ledger/` | Primitives, CryptoKit |
| `Platform/` | Primitives |
| `Config/` | Primitives, Platform |
| `Sources/` (capture) | Primitives, Platform, Config |
| `Runtime/` | all of the above |
| `DesignSystem/` | Primitives + view models only — never Ledger or Runtime directly |

**The load-bearing rule is the ledger one.** It is the audit target: someone
should be able to read that folder alone and satisfy themselves the chain is
sound. Any import beyond Foundation and CryptoKit in there is a defect.

## Improvements to make during the copy

Not a straight port. Each of these is a lesson that cost something.

**1. One path resolution point, enforced.**
The 1.0.0 bug: the viewer read `~/Library/…` while the recorder wrote to the App
Group container, so the app reported "Recorder Not Running" forever while the
recorder was healthy. Under the sandbox `~` expands to a *process-private*
container. Resolve every path through a single type, and add a gate that fails
the build on storage paths derived from a bare default config.

**2. Record ordinals, designed in — not bolted on.**
The UI shows `#4629 · chained to #4628` on every row. There is no ordinal in the
current model. It must be **cumulative across rotated segments**, so it cannot be
a line index within one file. Carry a per-segment base count, computed once and
cached beside the segment.

**3. Coverage gaps from absence, not from stop/start pairs.**
A graceful stop writes a record. A force-quit, a crash, or a power loss does
not — and that is exactly the case a frightened user cares about. Detect a gap
as *a start record whose predecessor is older than the heartbeat interval
allows*, and treat any stop record as a bonus detail rather than the trigger.

**4. Additive-only schema, forever.**
`computeHash` HMACs the canonical JSON of the whole event, and verification
re-encodes stored records to recheck them. **A new non-optional field breaks
verification of every ledger a user already has.** New fields are `Optional`,
default `nil`, never reordered, never renamed. Write this as a comment on the
event type itself so nobody has to rediscover it.

**5. Capability registry as a first-class concept.**
The locked chips in the UI are not cosmetic — they are the honesty mechanism. The
engine should be able to enumerate, at runtime, which sources it can observe and
why not. Extend the existing "unavailable under App Sandbox: …" phrasing rather
than inventing a second vocabulary.

**6. No non-`Sendable` shared state.**
Swift 6 is strict here and the old code predates it. The `DateFormatter` statics
already bit us once. Prefer `FormatStyle` and value types; if something must be
shared and unsafe, it gets `nonisolated(unsafe)` *and* a comment justifying it.

**7. Attributed failure, never silence.**
Keep the existing principle: anything the sandbox forbids fails loudly with one
recognisable, greppable string. A capability that cannot run must never look like
a capability that found nothing.

**8. Diagnostics stay on their own subsystem.**
The agent polls the unified log for custom events. Diagnostic logging must use a
distinct subsystem or the recorder ingests its own debug output as user events.

## Waves

Dependency-ordered. Each wave leaves the app building and running.

### Wave 1 — Primitives + Ledger
`AlarmEvent`, severity, canonical JSON, hex; then the hash chain, file lock,
anchor, proof export.

Add ordinals (improvement 2) and the additive-schema comment (4) as it lands.
This is the folder that must read cleanly on its own.

**Done when:** a ledger written by the shipping app verifies here, byte for byte,
with correct cumulative ordinals across rotated segments.

### Wave 2 — Platform
Sandbox detection, shared container, installation paths, entitlement reading.
Single resolution point (1) plus the lint gate.

**Done when:** one type answers "where does everything live", and the gate fails
a build that bypasses it.

### Wave 3 — Config
Schema and validation. Container-aware defaults from the start; the tilde-path
default never becomes reachable for storage paths.

### Wave 4 — Read a real ledger *(the milestone)*
Swap `MockLedger` for a real loader, pointed at an existing ledger produced by
the shipping app.

This is the moment the playground stops being a demo. It also validates Waves 1–3
against real data rather than fixtures — including a real coverage gap and a real
burst, which no handwritten mock fully imitates.

Keep `MockLedger` alive behind a switch: SwiftUI previews and the design work
still need deterministic data.

**Done when:** the timeline, list, counts, and inspector render months of real
history at every zoom level.

### Wave 5 — Capture
Session, file, spool sources; then the new Tier A sources the design already
shows and the engine does not have — **drives** (`NSWorkspace.didMountNotification`),
**displays** (`CGDisplayRegisterReconfigurationCallback`), **user switching**
(`sessionDidBecomeActive`).

Capability registry (5) lands here, because this is where "cannot observe"
becomes real.

### Wave 6 — Runtime
Pipeline, rules, heartbeat, agent status. The agent becomes able to run.

### Wave 7 — Lifecycle
`SMAppService`, login item, install and uninstall. Deliberately last: the most
sandbox-sensitive code, and the least urgent while a ledger can be read from
disk.

### Wave 8 — Delivery
Notifiers, and Telegram behind its own guard. This is the only code that touches
the network — keep it in one obviously-named folder so the answer to "what can
reach the internet?" stays one word.

## Order of value

If the waves need reordering, this is the priority:

1. **Wave 4** — real data in the new UI. Everything before it is plumbing;
   everything after it is additive.
2. **Wave 1** — the audit target, and the thing the product's claim rests on.
3. **Wave 5's new sources** — drives, displays, user switching. The design shows
   them; the engine cannot produce them; they are cheap and sandbox-safe.

## What is not coming across

- The flat 41-file layout.
- `MythLogAppSupport` as a single 143-file surface.
- Any storage path derived from a bare default config.
- The legacy `.command` installers.
- Binary renames (`mythlogd`). Cosmetic, breaking, unrelated.
