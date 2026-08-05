# MythLog — Playground

A ground-up rebuild of MythLog's interface: design system plus visual
implementation, driven by mock data. No recorder, no ledger, no I/O — this
exists to make the design real enough to judge.

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

## Structure — atomic design

Brad Frost's hierarchy, one level per folder. The rule that makes it worth
having: **a thing may only use things below it.** An atom never knows about a
page.

```
Sources/
  DesignSystem/
    Tokens/      Palette, Typography, Metrics — every literal lives here
    Atoms/       StatusDot, PillSurface, HatchFill
    Molecules/   FilterChip, StatusPills, ZoomControls, EventRow
    Organisms/   HeaderBar, FilterBar, TimelineCanvas, EventList,
                 InspectorPanel, CoverageGapBanner
    Templates/   MainWindowTemplate — layout only, no meaning
    Pages/       MainPage — template + data + intent
  Model/         EventKind, TimelineEvent, TimelineWindow, ZoomLevel
  Mock/          MockLedger — a believable day
  App/           MythLogApp
```

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
naive layouts:

- **A four-hour coverage gap** (02:04–06:28). Rendered as hatching at every zoom
  level, repeated as prose in the list, and **not hideable by any filter** — an
  absence of recording is not an event.
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

- Pinch (`ctrl`-scroll magnification) is not wired; keyboard and buttons are.
- Level changes snap. Whether they should cross-fade is an open design question.
- First run, integrity banners, and the truncated / anchor-offline states are
  modelled in `IntegrityState` but have no page yet.
- Light mode is untouched. Dynamic Type and localisation are unverified — the
  four-column row is the hard case.
