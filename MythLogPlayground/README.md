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
    Atoms/       StatusDot, PillSurface, HatchFill, FlowRow
    Molecules/   FilterChip, FacetValueRow, FilterConstraintPill,
                 SeverityFilterMenu, StatusPills, ZoomControls, EventRow
    Organisms/   HeaderBar, FilterBar, FilterFacetPanel, FilterStateBanner,
                 TimelineCanvas, EventList, InspectorPanel,
                 CoverageGapBanner, IntegrityBanner, LedgerChooser,
                 PrincipleColumns, AnchorChoiceCard
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

| Population | Window | Level | Drawn as |
| --- | --- | --- | --- |
| ≤ 48 visible | any | Events | Individual nodes with glyphs |
| > 48 visible | > 12 h | Density | Neutral bars |
| > 48 visible | ≤ 12 h | Clusters | Category-stacked bars with counts |

**Population decides first.** The span thresholds only ever existed as a proxy
for population — the thing they prevent is thousands of nodes overlapping into a
smear — and once the population is known directly the proxy is not needed.
Twelve events spread over a fortnight have nothing to overlap with.

That matters most under a filter. "Show me only screen unlocks" over a week
leaves five events, and the whole reason for asking is to see them individually.
With span deciding first, that window resolved to Density and the answer arrived
as five indistinguishable bars.

Above the limit the span still decides, and the old reasoning stands: zooming
into a burst stays clustered rather than exploding into overlap.

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

## Filtering

Six on/off chips could not investigate 364 file events, and would have been less
able to after Wave 5 adds drives, displays, and user switching. The model is
deeper now, and one rule governs the whole of it.

### It must be impossible to forget you are looking at a subset

In most applications a forgotten filter is an annoyance. Here it is **the same
failure as an undrawn coverage gap** — it makes absence look like safety.
Somebody opens this app because they are worried, sees a quiet night, and is
reassured; if that quiet was a filter they set last Tuesday, the app has lied to
them about the one thing it exists to be honest about.

So the filtered state is stated in four places at once, and none of them is
subtle or dismissible:

- **A band above the timeline**, permanent while a filter is active. It leads
  with the *hidden* count — "312 of 364 records in this window are hidden" —
  because "52 records" reads as an answer and "312 hidden" reads as a warning.
  Every active constraint is a removable pill beside it, and "Show everything" is
  always one click.
- **A pill in the timeline header**, so a screenshot of the drawing carries the
  qualification with it.
- **A line in the event list's header**, still on screen when the band is not.
- **Two numbers on every chip** — see below.

An empty result is never allowed to look like an empty stretch of history. Both
the timeline and the list say which of the two they are showing.

### Two rules no filter may break

Both are enforced in `TimelineDerivation`, which is the only layer that knows
about either, and both are asserted in `FilterInvariantTests` over generated
ledgers under 120 randomly-built filters rather than one hand-picked case.

- **No filter may hide a coverage gap.** An absence of recording is not an event.
- **No filter may hide a record that failed verification.** Filtering answers
  *what happened*; it must never answer *whether the record can be believed*. A
  record past the trust boundary is shown whatever the filter says, and the band
  says how many are there for that reason.

### The dimensions

`EventFacet` is one type rather than four sets of fields, so the interface is
generic over it: a facet added for Wave 5 needs no new view.

| Facet | Value | Matching |
| --- | --- | --- |
| Category | the six chips | exact |
| Event type | `session.unlock`, `file.modify` | exact |
| Source | `loginwindow`, `fseventsd` | exact |
| Subject | the folder, app, or volume | **prefix** |

Each has an **include** set and an **exclude** set. An empty include set means
"no opinion", never "nothing" — that is what stops a filter saved today from
hiding an event type that lands next month. Exclusion beats inclusion, because
subtraction is the more specific statement.

Subject matching is by prefix on purpose: excluding `~/Projects/…/.build/` has to
take everything underneath it, or a 312-event build storm has to be excluded one
object file at a time. Subtractive filters are the ones investigators actually
reach for.

**Severity is deliberately not a facet.** `AlarmSeverity` is `Comparable` and the
question people have is ordered — *at least* a warning. Five tick boxes would
express "notice but not warning", which nobody wants, and would need re-ticking
when a sixth severity is added. It is a threshold.

**Every offered value is derived from the window**, never from a list. Wave 5
brings event types this build has never heard of, and a written-down list would
be wrong the day they land — offering filters for what the ledger no longer
contains and none for what it does. A capped list always says how many values it
did not show.

### Presets

"Every time this Mac was unlocked" is not an obscure query; for someone who came
here worried it is *the* question. It is one click, and it is **not a mode**: it
writes an ordinary filter, and the band shows exactly what it expanded to. So the
preset answers the question and, on the way, teaches the model that answered it.

A preset cannot hardcode `session.unlock`, because that is not what every ledger
calls it — this build's fixture writes `session.unlock` and the shipping recorder
writes `session.screen.unlocked`, and Wave 5 will write a third. So a preset
carries *tokens* matched against the components of the types the window actually
holds, by prefix: `unlocked` begins with `unlock`, and `unmounted` does not begin
with `mount`, so "drive mounted" never quietly drags in "drive unmounted".

A preset that matches nothing **refuses and says so**. Silently applying an
unresolved type preset would produce a filter with no type constraint at all —
showing *more* than before, the exact opposite of what was asked.

### The search box is still a search box

Typing `lease` searches for "lease", as it always did. Tokens are additive:

```text
kind:session   type:unlock   source:fseventsd   path:.build
severity:>=warning           -path:.build      "screen unlocked"
```

Tokens match loosely; a value ticked in a popover matches exactly. They are
different tools and the difference is deliberate — one is a search, the other is
a selection.

**No filter is expressible only as a token.** Every field above also has a
control beside the chips. This app's audience is people worried about their own
Mac, not people who write queries, and a filter reachable only through a syntax
is one most of them cannot undo.

A word that looks like a field and is not — `sevrity:>=warning` — is searched as
plain text **and reported**. Swallowed, it would empty the timeline and give the
user every reason to read that as "there were no warnings".

### The counts problem

With sub-filters active, "Files 364" is ambiguous: all the file events, or the
ones passing the sub-filter? So:

- **Chips only** → one number: everything of that category in the window.
- **Any sub-filter** → `passing / total`. The denominator never moves, which is
  what makes two numbers legible while the numerator changes under your hands.

A chip whose passing count is below its window count is marked, and that is
computed from the counts rather than from the filter's shape — attributing a
source or a subject back to a category would be guessing.

### Saved filters, and the one that is dangerous

Filters can be named and kept, and the active one is restored on launch. That is
the dangerous feature in this whole document: a filter from last week that nobody
remembers setting is precisely the lie described at the top.

Starting unfiltered every launch is worse in its own way — somebody who set up
"Ignore builds" gets the noise back every morning and stops opening the app. So
the filter is restored **and announced**, in the alarm colour, naming it and the
day it was saved, and it stays until acknowledged or cleared. The announcement is
not a nicety; it is what makes restoring defensible at all.

Contrast `OpenedLedgerMemory`, which deliberately does *not* reopen. The asymmetry
is intentional: reopening a ledger puts somebody's history on a screen in front of
whoever is in the room, while restoring a filter only risks concealing — which an
announcement can address and a closed window cannot.

### Performance

Filtering runs on every window change, and window changes arrive several times a
second while zooming or panning. Measured on 100,000 records, with every
dimension active:

- **The window is found by binary search.** The scan it replaced compared every
  event in the ledger on every window change — a quarter of a million comparisons
  to find the sixty inside a one-hour window. The array is time-ordered, which is
  what makes that sound; sortedness is checked once per load, and an unsorted
  array falls back to a full scan rather than returning a quietly short slice.
- **One pass, and only one.** Category counts, severity counts, passing counts,
  and the visible slice all come out of the same loop.
- **The expensive facet is on demand.** Counting distinct subjects means building
  a folder string from every event in the window; that runs when somebody opens a
  popover, not on every pan.
- **The query is parsed once per derivation**, not once per event, and substring
  matching never builds a lowercased copy of the haystack.
- Cancel-before-restart is unchanged. It is what makes a fast sweep survivable.

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

**Filtering has no time dimension.** "Overnight" is the filter people would most
obviously want to name, and it is the one that cannot be expressed: the window is
the time control, and a saved filter carries neither a span nor a time of day.
Saving one called "Overnight" today would store everything *except* the hours it
is named for — which is why nothing in this build offers it as an example.

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
