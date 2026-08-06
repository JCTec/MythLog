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
MYTHLOG_CONTAINER=/path/to/a/group/container   # empty means "no install here"
```

`MYTHLOG_CONTAINER` replaces the App Group container this process resolves. The
test scheme sets it, so a test run never reads the ledger and config belonging to
the recorder on this Mac — both because a test suite has no business reading
somebody's history to check its own arithmetic, and because reading another app's
container is TCC-gated: macOS blocks the read behind *"MythLog would like to
access data from other apps"*, and under `xcodebuild test` that dialog has nobody
in front of it. The run then fails as "the test runner hung before establishing
connection", which names neither the permission nor the file.

The app is signed with a real Apple Development identity (`DEVELOPMENT_TEAM` in
`project.yml`) for the same reason: TCC records its answer against the signing
identity, and an ad-hoc signature does not survive a rebuild — so every build
asked again. Building on a machine without those certificates works; pass
`DEVELOPMENT_TEAM=` to `xcodebuild` and it signs ad-hoc.

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

### Gaps are drawn on the same grid as the bars

At Density and Clusters both the bars and the coverage-gap hatching are
positioned by `BucketGrid` — one projection, so hatch edges land on bar edges
rather than near them. Before that, bars were laid out in an `HStack` (a layout
in slot space, not on the time axis) while the overlay used a continuous
fraction of the window, and the two agreed only by accident.

`CoverageGapLayout` then decides what a gap *looks like*, which is not the same
as what it is:

- **A bucket is wholly in a gap or wholly out of one.** A bucket is hatched only
  when it lies entirely inside a gap and draws no bars. **A bucket with a
  non-zero count is never inside a gap** — a gap means nothing was recorded, so
  the two cannot overlap. Asserted over the fixture and over generated ledgers
  in `TimelineGapLayoutTests`.
- **Near-adjacent gaps are coalesced** — merged when they are closer together
  than one bucket, since a division the grid cannot draw is one it should not
  imply. The `CoverageGap` values are carried through untouched: the banner
  cites their real ordinals, and a merged pair is still a pair.
- **A gap too small to hatch becomes a tick, never nothing.** Below one bucket
  the grid cannot support a claim about a *span*, but the data still supports a
  claim about a *point*. A gap is never dropped for being small — that would
  hide exactly the brief interruption someone is looking for.

At Events level there is no grid, so gaps stay continuous: a real timestamp is
the honest position.

### What counts as too quiet

The threshold is three missed heartbeats, from `heartbeat.intervalSeconds` in
the ledger's `config.json`. When there is no config beside the ledger — which is
every ledger opened by hand — that fell back to 60 s, so 180 s of silence, and
that guess fabricates gaps: the shipping fixture's own heartbeats are 1096 s
apart, and its median record spacing is 137 s.

So the ledger gets a say. `CoverageAnalysis` measures the heartbeat cadence the
records actually demonstrate and takes the larger of the two thresholds. The
configured value is never lowered; raising it only ever withdraws a claim the
ledger could not support.

**Known limitation.** A ledger with `heartbeat.enabled: false` has no floor under
legitimate silence at all, so silence proves nothing and gap detection is not
really possible over it — but the configured threshold still applies and will
report ordinary quiet stretches as gaps. `ConfigValidation` warns about the
setting; the analysis does not yet act on it.

Zoom is never gesture-only: ⌘+ / ⌘− / ⌘0, the +/− buttons, the range presets, and
click-a-bar all do it. Gestures are not keyboard-reachable and not operable under
VoiceOver, so they can only ever be an accelerator.

### Panning

The window moves sideways through history at a constant span, at every level.
It is **not** a `ScrollView`: scrolling needs content as wide as the thing being
scrolled, and a two-year history at the Events level is millions of points of
view nobody can render. Panning changes the window and lets the derivation
recompute — the same path zoom takes, including the cancel-before-restart that
keeps a fast sweep off the main thread.

| Input | Does |
| --- | --- |
| Two-finger horizontal scroll | Pan. Vertical scroll passes through to the page; `⌃`/`⌘`-scroll is left for zoom. |
| ← → | Pan by a quarter of the window, while the timeline has focus. |
| ⌥⇧← / ⌥⇧→ | The same, from the Timeline menu — no focus needed. |
| ⌘← / ⌘→ | Beginning of history / now. |
| ⌥← / ⌥→ | Step the **selection**, not the window — as `docs/ACCESSIBILITY.md` documents. |
| Drag the position bar | Pan, coarsely. |

The menu commands stand down while the search field is being edited, so ⌘← stays
"beginning of line" and ⌥← stays "back one word" in a text field. Plain arrows
are deliberately not menu key equivalents — as menu shortcuts they would take the
arrow keys away from every text field in the app — so they are handled by the
focused canvas instead, and the menu carries an unmodified-by-focus equivalent.

**Clamped to history.** The window can never start before the first record or
end after the last, and every panning operation goes through the same
initialiser that already enforced it for zoom.

**The live edge is a state you can read.** A window at the newest end of the
history is where new records arrive; panning away from it is not. The position
bar says which, and re-attaching is one keystroke, one click, or panning back to
the edge. A reload re-pins to the live edge for a reader who was at it, and holds
position for a reader who was not — being moved to now because the recorder wrote
a heartbeat is the failure that prevents.

**Selection survives panning**, because a record you panned away from is usually
one you are still thinking about. The inspector says when the selected record is
outside the visible window and offers the way back, rather than describing a
record with nothing on screen to match it.

## Known gaps

Honest about what is not here.

**Not started.** Waves 5–8: no capture sources, no agent runtime, no
`SMAppService`, no notifiers, no Telegram. The recorder-status pill in the header
is still hard-coded — this app reads ledgers, it does not run one. The config
schema carries those sections and round-trips them untouched, but nothing
interprets them.

**No new anchor destinations.** `AnchorDestination` is a protocol with both
shipped destinations behind it, so new ones are additive — but none has been
added. Telegram, git, OpenTimestamps and a remote server are phases 4–6 in
`docs/ANCHOR_DESTINATIONS.md` and are not built.

**The recorder is not restarted after a config change.** Saving writes
`config.json`; a recorder already running keeps the copy it read at startup until
it restarts, and the page says so rather than pretending otherwise. Restarting it
is launch-agent lifecycle, which is Wave 7. The shipping app does this with
`SMAppService`; this one cannot.

**"A folder you choose" may not be shippable in the App Store edition.** A
security-scoped bookmark held by this viewer grants access to *this viewer*, and
anchors are written by the recorder — a separate process in its own container.
The full analysis, including what would have to change, is in
`docs/CONFIG_OWNERSHIP.md`. It is unresolved and it decides whether that option
can ship sandboxed at all.

**Ledgers are still read-only.** Nothing here appends to a ledger outside tests.

**Multiple simultaneous anchors** (phase 3) are not built, so there is no answer
yet for two destinations disagreeing — which is the interesting case, since stale
and truncated look identical at a glance and mean opposite things.

**Sandboxing.** The app is deliberately unsandboxed, which is why it can read the
App Group container, open any file the user picks, and write to a folder chosen
in the panel. A sandboxed build would need the App Groups entitlement for
auto-detect and security-scoped bookmarks for the picker — and, for anchors,
those bookmarks handed to the recorder rather than kept here. Noted in
`LedgerDiscovery` and `docs/CONFIG_OWNERSHIP.md`.

**Interface.** Pinch (`ctrl`-scroll magnification) is not wired; keyboard and
buttons are. Level changes snap; whether they should cross-fade is an open
question. Light mode is untouched, and Dynamic Type and localisation are
unverified — the four-column row is the hard case.

**Unverified by eye.** Screen capture is not available to the environment these
phases were built in, so the rendering of every state was checked through
previews, tests, and diagnostics rather than by looking at it.
