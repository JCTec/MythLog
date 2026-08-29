---
description: MythLogPlayground — fix coverage-gap alignment and the gap/bucket contradiction
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, TodoWrite
---

The coverage-gap overlay is misaligned and visually noisy at Clusters and
Density. Diagnose it properly before changing anything — there are three
separate faults here and one of them is a data bug, not a drawing bug.

## What was observed

At `Clusters·4 h`, on a real ledger:

- Hatched gap regions do **not** line up with the bars. Their edges fall
  mid-bar, so bars are half-hatched.
- Roughly five separate hatched blocks appear with visible seams between them,
  where one continuous region was intended.
- **Bars are drawn inside the hatched regions** — buckets showing counts of 3,
  3, 1, 2, 2, 2, 1 sit within spans marked "no coverage".

That last one is a contradiction, not a cosmetic problem: a coverage gap means
nothing was recorded. A bucket cannot both contain events and be a gap.

## Constraints

`MythLogPlayground/` writable, everything else read-only:

```sh
git status --porcelain | grep -v '^.. MythLogPlayground/' | grep -v '^.. .claude/' && echo VIOLATION || echo clean
```

Branch `playground/gap-alignment`, never push. Gates green before committing:
`./Scripts/check-layering.sh --self-test` and the test suite. Conventions per the
README; Swift 6 strict concurrency, zero warnings.

## Fault 1 — two different grids

Suspected cause, to be confirmed by reading the code rather than assumed:

Bars snap to bucket boundaries from the step ladder in
`TimelineCanvas+Renderers` (`bSteps`: 60, 120, 300, 600, 900, 1800, 3600, 7200).
The gap overlay in `TimelineCanvas` positions itself with
`window.fraction(of: gap.start)` — a continuous fraction of the window. Two
coordinate systems over the same axis, so they can only line up by accident.

**Fix:** at Density and Clusters, quantise gap rectangles to the same bucket
grid the bars use. A bucket is either wholly in a gap or wholly out of one.

At **Events** level keep the gap continuous — there is no grid there to snap to,
and a real timestamp is the honest position.

## Fault 2 — adjacent gaps drawn separately

Several near-adjacent gaps each render their own rectangle, producing seams and
inconsistent widths that read as noise rather than as one absence.

**Fix:** coalesce gaps in the derivation before drawing. Merge any two whose
separation is smaller than one bucket at the current level. Merging is a
presentation concern — the underlying `CoverageGap` values must not be mutated,
because the list banner cites their real record numbers.

## Fault 3 — the one that matters

Buckets containing events overlap spans marked as gaps. Gaps and buckets are
evidently computed independently and composited, with nothing reconciling them.

Investigate in this order, and **report what you find before fixing**:

1. **Is gap detection over-firing?** Check what `gapThreshold` actually resolved
   to against the heartbeat interval in the ledger's `config.json`. A threshold
   that is too tight turns ordinary quiet stretches into "gaps". If that is the
   cause, the visual fix alone would only make wrong data look tidy — fix the
   threshold first.
2. **Or is the overlap real?** If a genuine gap can contain events, the gap
   boundaries are being computed from the wrong endpoints — for example
   including the restart record's own timestamp.

Then enforce the invariant in the derivation: **a bucket with a non-zero count
is never inside a gap.** Add a test asserting it over the fixture and over a
generated ledger with several short silences.

## Fault 4 — sliver gaps (design decision, take a position)

At wide zoom a short gap becomes a two- or three-pixel hatched sliver, which is
noise rather than information.

Decide, and write the reasoning in a doc comment: below some minimum width, does
a gap render as a marker or tick instead of a hatched region? It must remain
visible — **a gap may never be dropped for being small**, since that would hide
exactly the brief interruption someone is looking for. But it may change
representation.

## Definition of done

- Gap edges align exactly with bucket edges at Density and Clusters; continuous
  at Events.
- Adjacent gaps render as one region.
- No bucket with events is drawn inside a gap, proven by a test.
- Root cause of the overlap identified and stated — threshold, boundary
  arithmetic, or both.
- Short gaps stay visible at every zoom level.
- Gates green, `git status` clean outside `MythLogPlayground/`.

Add previews covering: one long gap, several short gaps close together, a gap at
the window edge, and a gap narrower than one bucket.
