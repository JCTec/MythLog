# MythLog — Playground

A ground-up rebuild of MythLog: the interface, and now the engine behind it.
It reads a real hash-chained ledger written by the shipping app, verifies it,
and renders months of history.

There is still no recorder — this app reads a ledger, it does not write one
outside its tests.

Separate from the shipping app on purpose. Nothing here imports it and nothing
there depends on this.

## Run

```sh
brew install xcodegen        # one-time
cd MythLogPlayground
xcodegen generate
open MythLog.xcodeproj        # Cmd+R
```

`project.yml` pulls in `Sources/` recursively, so new files need no project
edits. Regenerate after adding folders.

It opens on a chooser. If a ledger exists where an install would put one it is
offered there — found, never opened for you, because this app is also used for
screenshots. "Open ledger…" takes any file, which is what the tamper tests in
`HUMAN_CHECKLIST-ENGINE.md` need.

The environment variables still work, and still open immediately, for automation
and for tests that need a deliberately wrong key:

```sh
MYTHLOG_LEDGER=/path/to/events.jsonl
MYTHLOG_HMAC_KEY_HEX=<64 hex characters>
```

Anchor settings are at ⌘, — where the chain head is kept, framed as the question
it actually is.

See `HUMAN_CHECKLIST-ENGINE.md` for what to look at once it is loaded, and
`docs/RESEARCH_NOTES.md` for the concurrency decisions and their sources.

## Gates

```sh
./Scripts/check-layering.sh --self-test    # writes 6 real violations, checks each is caught
xcodebuild -project MythLog.xcodeproj -scheme MythLog \
  -configuration Debug -destination 'platform=macOS' test
```

## Structure — atomic design

Brad Frost's hierarchy, one level per folder. The rule that makes it worth
having: **a thing may only use things below it.** An atom never knows about a
page.

```
Sources/
  Primitives/    AlarmEvent, CanonicalJSON, hex, @Clamped, @Memoized, JSONValue
  Ledger/        the hash chain, streaming, verification, anchors, proof export
  Platform/      sandbox, App Group container, StorageLocations, entitlements
  Config/        schema, validation, lossless round-trip
  Model/         view models — the only layer where the engine meets the UI
  Mock/          MockLedger — a believable day, behind TimelineSource
  DesignSystem/
    Tokens/      Palette, Typography, Metrics — every literal lives here
    Atoms/       StatusDot, PillSurface, HatchFill
    Molecules/   FilterChip, StatusPills, ZoomControls, EventRow
    Organisms/   HeaderBar, FilterBar, TimelineCanvas, EventList,
                 InspectorPanel, CoverageGapBanner, IntegrityBanner,
                 LedgerChooser, PrincipleColumns, AnchorChoiceCard
    Templates/   MainWindowTemplate — layout only, no meaning
    Pages/       RootPage — choose a ledger, then read it
                 MainPage — template + data + intent
                 WelcomePage — first run, and what the app refuses to record
                 AnchorSettingsPage — who are you keeping this away from?
  Previews/      composition roots for the canvas
  App/           MythLogApp — the composition root
```

### Layers

Folders are a convention; nothing stops `Ledger/` importing `DesignSystem/`
except discipline. `Scripts/check-layering.sh` buys back what a multi-module
layout enforced for free.

| Layer | May reference |
| --- | --- |
| `Primitives/` | Foundation |
| `Ledger/` | Primitives, CryptoKit, Darwin (`flock`) |
| `Platform/` | Primitives |
| `Config/` | Primitives, Platform |
| `Model/` | Primitives, Ledger, Platform, Config |
| `DesignSystem/` | Primitives, Model — never the engine directly |
| `App/`, `Previews/` | everything |

The load-bearing rule is the `Ledger/` one. It is the audit target: someone
should be able to read that folder alone and satisfy themselves the chain is
sound.

### Conventions

- Nested types over prefixed ones: `MainPage.Model`, `FilterChip.Locked` — never
  `MainPageViewModel`.
- Files mirror the type path: `Owner.swift`, `Owner+Aspect.swift`. Related files
  sort adjacently, which is the point.
- One primary type per file.
- No `Utils`, `Helpers`, or `Common`. Something without a home is a missing
  concept, not a misc file.
- Every colour, size, and font resolves through `Tokens/`. A literal outside
  that folder is a bug.

## What the mock data exercises

Deliberately not a happy path. `MockLedger` contains the two cases that break
naive layouts, and it carries heartbeats so gap detection over it behaves
exactly as it does over a real ledger:

- **A four-hour coverage gap** (02:04–06:28), in two variants — one with a stop
  record and one without. The one without is the case that matters: a force
  quit, a crash, or a power cut writes nothing at all, so the gap can only be
  found by noticing the silence. Rendered as hatching at every zoom level,
  repeated as prose in the list, and **not hideable by any filter** — an absence
  of recording is not an event.
- **A 312-event burst** in ten seconds at 09:41, from one build. Square-root bar
  scaling keeps the surrounding 3–20 event buckets legible instead of flattening
  them.

## The timeline

One component, three renderers — `TimelineCanvas` plus
`TimelineCanvas+Renderers`. Deliberately not three views:

| Window | Level | Drawn as |
| --- | --- | --- |
| > 12 h | Density | Neutral bars |
| > 90 min | Clusters | Category-stacked bars with counts |
| ≤ 90 min and ≤ 48 events | Events | Individual nodes with glyphs |

The level is chosen from span **and** population, so zooming into a burst stays
clustered rather than exploding into overlap.

Zoom is never gesture-only: ⌘+ / ⌘− / ⌘0, the +/− buttons, the range presets, and
click-a-bar all do it. Gestures are not keyboard-reachable and not operable under
VoiceOver, so they can only ever be an accelerator.

## Known gaps

Honest about what is not here.

**Not started.** Waves 5–8: no capture sources, no agent runtime, no
`SMAppService`, no notifiers, no Telegram. The recorder-status pill in the header
is still hard-coded — this app reads ledgers, it does not run one. The config
schema carries those sections and round-trips them untouched, but nothing
interprets them.

**Anchoring is groundwork only.** `AnchorDestination` is a protocol with both
shipped destinations behind it, so new ones are additive — but no new destination
exists. Telegram, git, OpenTimestamps and a remote server are phases 4–6 in
`docs/ANCHOR_DESTINATIONS.md` and are not built. The settings page shows and
changes the choice in memory; it does not write `config.json`, because the
recorder owns that file.

**Nothing writes config or ledgers outside tests.** Choosing an anchor folder
needs a picker and a config-writing path, and neither exists.

**Multiple simultaneous anchors** (phase 3) are not built, so there is no answer
yet for two destinations disagreeing — which is the interesting case, since stale
and truncated look identical at a glance and mean opposite things.

**Sandboxing.** The app is deliberately unsandboxed, which is why it can read the
App Group container and open any file the user picks. A sandboxed build would
need the App Groups entitlement for auto-detect and security-scoped bookmarks for
the picker. Noted in `LedgerDiscovery`.

**Interface.** Pinch (`ctrl`-scroll magnification) is not wired; keyboard and
buttons are. Level changes snap; whether they should cross-fade is an open
question. Light mode is untouched, and Dynamic Type and localisation are
unverified — the four-column row is the hard case.

**Unverified by eye.** Screen capture is not available to the environment these
phases were built in, so the rendering of every state was checked through
previews, tests, and diagnostics rather than by looking at it.
