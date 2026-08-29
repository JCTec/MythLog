---
description: MythLogPlayground — pan the timeline horizontally through history
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, TodoWrite
---

Let the timeline be moved sideways through history, at every zoom level — bars
and nodes alike.

## The shape of it

**This is panning the window, not scrolling a view.** Do not reach for
`ScrollView`. The canvas shows a `TimelineWindow` over the history; moving
sideways means translating that window at constant span. A scroll view would
need content as wide as the entire history — unrenderable at two years, and it
would fight the derivation that already exists.

Panning is the same operation as zooming with a different axis: change the
window, let `MainPage.Model.refresh()` recompute, and the existing
cancel-before-restart machinery handles the rest. Reuse it rather than inventing
a second path.

## Constraints

`MythLogPlayground/` writable, everything else read-only:

```sh
git status --porcelain | grep -v '^.. MythLogPlayground/' | grep -v '^.. .claude/' && echo VIOLATION || echo clean
```

Branch `playground/timeline-panning`, never push. Gates green before committing:
`./Scripts/check-layering.sh --self-test` and the test suite. Conventions per the
README; Swift 6 strict concurrency, zero warnings.

## Inputs

Follow the rule already established for zoom: **a gesture may never be the only
way.** Gestures are not keyboard-reachable and not operable under VoiceOver, and
`docs/ACCESSIBILITY.md` makes a public promise this must not break.

- **Two-finger horizontal scroll** — pan. Note the existing mapping: `ctrl`/`⌘`
  plus scroll is zoom, so plain horizontal scroll is free and is what every
  comparable timeline uses.
- **Arrow keys ← →** — pan by a useful fraction of the window (a quarter is a
  reasonable starting point; justify whatever you choose).
- **⌥← / ⌥→** already step between events. Make sure the two do not collide, and
  say in a comment how they differ: one moves the *window*, one moves the
  *selection*.
- **⌘← / ⌘→** — jump to the beginning of history and to now.
- Optionally drag-to-pan on the canvas. If you add it, it must not swallow
  click-to-select or click-a-bar-to-zoom.

## Rules

**Clamp to history.** The window can never start before the first record or end
after the last. At the edges, stop — do not let the window slide into emptiness
and imply a history that is not there.

**Re-attach to live at the right edge.** The "1 new event" affordance exists
because the view holds position when events arrive. Panning fully to the right
edge should re-attach, so new events flow in again, and that state should be
visible — a user must be able to tell "I am watching now" from "I am reading
history".

**Selection survives.** Panning does not change what is selected, and the
inspector does not clear because the selected event scrolled out of view. Decide
and document whether an off-screen selection is indicated.

**Do not fight the page.** A horizontal gesture over the canvas must not scroll
any ancestor, and a vertical gesture over the canvas should still scroll the page
normally. Getting this wrong makes the whole window feel broken.

**Panning is not zooming.** Span is invariant under pan. Add a test.

## Performance

Panning fires window changes as fast as a trackpad emits them — the same
pressure zoom already creates. Confirm on a ledger of at least 100,000 records
that a fast two-finger sweep does not stall the main thread, and that superseded
derivations are cancelled rather than queued. If they are not, that is the bug to
fix first.

## Worth considering, your call

A position indicator — where the current window sits within the whole history —
becomes much more useful once panning exists, because it is now possible to be
lost. A thin bar under the axis would do it. Argue for or against; do not add it
silently.

## Definition of done

- Panning works at Density, Clusters, and Events, by gesture and by keyboard.
- The window clamps to history at both ends.
- Panning to the right edge re-attaches to live, visibly.
- Span is unchanged by panning, proven by a test.
- Coverage-gap hatching stays aligned to the bucket grid while panning — the
  `BucketGrid` work must not regress.
- No main-thread stall on a 100k-record ledger during a fast sweep.
- Gates green, `git status` clean outside `MythLogPlayground/`.
