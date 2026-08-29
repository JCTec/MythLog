# Finish the visual QA pass — build and test until green

A 19-item visual QA pass has been applied to `MythLogPlayground/`. It was written
on a machine with no Swift toolchain, so **it has never been compiled**. Your job
is to get it building and passing, then to check it actually does what it claims.

Nothing here is a fresh design task. The decisions are made and documented in the
code. You are closing the gap between "written" and "known to work".

## Scope — read this before touching anything

- Work **only** inside `MythLogPlayground/`. The shipping app at the repository
  root is read-only for this task. Verify before you finish:
  ```sh
  git status --porcelain | grep -v '^.. MythLogPlayground/' | grep -v '^.. .claude/'
  ```
  That must print nothing but the pre-existing ` M project.yml` and
  `?? "MythLog 2.0 AppStore.html"`.
- **Do not run `git init`.** There is already a repository.
- Do not commit anything unless asked.

## What changed, so you can recognise a regression from a bug

Twenty-two files modified, two added:

- `Sources/Model/DurationLabel.swift` — **new**. `DurationLabel.text(_:)` (two
  largest non-zero units) and `RangeLabel.text(from:to:)` (adds weekdays exactly
  when a range crosses midnight). Everything that prints a duration or a range
  now goes through these.
- `Sources/DesignSystem/Atoms/CoverageGapMark.swift` — **new**. One hatch swatch,
  used by the gap cards and the timeline legend.
- `TimelineEvent.symbol` — per-record glyph derived from the last dotted
  component of `payloadKind`, falling back to `kind.symbol`.
- `EventKind.session.symbol` — was `lock.open`, now `person.crop.circle`.
- `TimelineWindow.label` / `.spanLabel` / `.showsWholeHistory` — rewritten.
- `CoverageGap` — gained `rangeLabel`, `boundsLabel`, `evidenceLabel`,
  `summaryLine`; `durationLabel` delegates to `DurationLabel`.
- `CoverageGapBanner` — rewritten as a one-line card with `isFirst:` controlling
  whether the explanation is expanded by default.
- `FilterBar` — `HStack` replaced with `FlowRow`, grouped with dividers, locked
  sources moved to their own line.
- `TimelineCanvas` — axis ticks snap to round times; gap region label pinned to
  the band's top-left; gap ticks now dashed with a cap.
- `HeaderBar` — split into a title row and a subline.
- `HistoryPositionBar` — thumb is neutral, live edge is a dot-and-tick at the
  right end.
- Plus `FilterChip`, `FilterChip+Locked`, `SeverityFilterMenu`, `ZoomControls`,
  `EventRow`, `EventList`, `InspectorPanel`, `FilterStateBanner`, `MainPage`,
  `Metrics`, `CoverageGapLayout`, `LedgerAnchor`.

## Step 1 — compile

```sh
cd MythLogPlayground
xcodegen generate
xcodebuild -project MythLog.xcodeproj -scheme MythLog \
  -configuration Debug -destination 'platform=macOS' build
```

Expect errors. The likely ones, in rough order of probability — check each
against the real diagnostic rather than assuming:

1. **`FlowRow` as a `Layout` with mixed children.** `FilterBar` now puts a
   `Menu`, `ForEach`, a `Rectangle`, and a `SeverityFilterMenu` into one
   `FlowRow`. If the layout refuses the mix, do **not** revert to `HStack` —
   that reintroduces the truncation this pass exists to remove. Wrap the
   offending children or fix `FlowRow`.
2. **SF Symbol names.** `TimelineEvent.symbol` and `EventKind.symbol` reference
   `person.crop.circle`, `lock.fill`, `lock.open.fill`, `moon.fill`, `sun.max`,
   `display`, `externaldrive.badge.plus`, `externaldrive.badge.minus`,
   `arrow.up.forward.app`, `xmark.app`, `stop.circle`, `play.circle`. These do
   not fail at compile time — they fail at runtime as blank glyphs. Verify each
   exists in the SDK you are building against, and substitute the nearest
   equivalent if not.
3. **`Text.textSelection(.enabled)`** in `InspectorPanel.payload` — availability.
4. **`.accessibilityAction { }`** on `CoverageGapBanner` — check the overload
   resolves without an explicit `.default` kind.
5. **`@State private var isExpanded: Bool?`** in `CoverageGapBanner` — an
   optional `@State` written from a `Button` action.
6. **Swift 6 strict concurrency.** `DurationLabel` and `RangeLabel` are
   stateless enums with static methods and should be clean, but confirm — no
   `DateFormatter`, no shared mutable state, and the project builds with
   `SWIFT_STRICT_CONCURRENCY: complete`.

Fix the cause, never the symptom. If a fix would undo one of the nineteen
decisions, stop and say so instead.

## Step 2 — tests

```sh
xcodebuild -project MythLog.xcodeproj -scheme MythLog \
  -configuration Debug -destination 'platform=macOS' test
```

Two existing tests touch changed behaviour and should still pass unmodified:

- `CoverageGapTests` expects `gap.durationLabel == "1 h"`. `DurationLabel.text`
  must still produce that for exactly 3600 seconds.
- `TimelineGapLayoutTests` expects a coalesced mark's label to contain
  `"4 interruptions"`. That string now goes through `RangeLabel`.

If either fails, the new formatter is wrong — not the test.

## Step 3 — tests the pass earned

Add these. They are cheap, they are the parts most likely to rot, and none of
them needs a renderer:

7. **`DurationLabel`** — 0, 59 s, 60 s, 3600 s, 3660 s, 86,399 s, 86,400 s,
   90,000 s, and a negative interval (must clamp to `"0 min"`, not print a sign).
   Assert at most two units ever appear.
8. **`RangeLabel`** — a range inside one day has no weekday; a range crossing
   midnight has two; 23:59 → 00:01 crosses (one minute, two days); a reversed
   range is normalised rather than printed backwards.
9. **`TimelineCanvas.axisStep(for:)`** — for spans from ten minutes to two years,
   assert the resulting tick count lands in 3...10, and that every step divides
   evenly into a day for all sub-day steps.
10. **Axis ticks land on round times.** For a handful of window starts including
    deliberately awkward ones (12:37, 23:59), assert every returned tick has
    `second == 0` and is a whole multiple of the step past midnight.
11. **The axis loop terminates.** It is bounded at 128 iterations; assert a
    ten-minute window at 23:50 returns a small number of marks and does not hit
    the bound.
12. **`TimelineWindow.showsWholeHistory`** — true for `init(showingAllOf:)`,
    false after any pan or zoom that moves either edge.
13. **`TimelineEvent.symbol`** — `session.lock` and `session.unlock` differ;
    `agent.agent.heartbeat` and `agent.heartbeat` agree; an unknown payload kind
    falls back to its category's symbol.
14. **`CoverageGap.summaryLine`** — contains the duration, both bounding
    ordinals, and says `no stop record` for `.unexplained`.

Run the layering gate too, including its self-test:

```sh
./Scripts/check-layering.sh --self-test
```

## Step 4 — look at it

This is the part that has never been done for any of this app, and it is the
reason the pass exists. Build, run against the fixture, and check the acceptance
criteria by looking:

- **No truncated labels anywhere at default window width** (1420×900). Then
  shrink the window to its minimum, 1240 wide, and confirm the filter band
  *wraps* rather than ellipsizing. This is criterion one and the whole reason
  `FlowRow` is there.
- **Exactly one filled/emphasis control per band.** In the filter band that is
  "Ask", unless a saved filter or a severity floor is active — both of those
  legitimately take a wash when they are doing something.
- **The gap explainer appears once.** Load a window containing two or more gaps.
  The first is expanded; the rest are one line each and expand on click.
- **All counts carry thousands separators.**
- **The axis sits on round hours**, and the labels stay still while you pan.
- **The zoom pill matches the visible span**, including for a window spanning
  several days — the case that used to read `Density · 6 d` beside
  `12:37 – 21:59`.
- **The position bar does not look like a progress bar.** Full-history view is
  the test: the thumb is neutral and full width, and the only green is the live
  edge dot at the right.
- **The payload block wraps.** Select a record with a long path —
  `~/Projects/mythlog/.build/artifact-311.o` — and confirm nothing is clipped
  inside its quotes.

Capture a screenshot of each state you check. If screen capture is unavailable
in your environment, say so plainly rather than reporting these as verified —
the README already carries that admission for the earlier phases and adding a
false one would be worse than adding another honest one.

## Step 5 — report

- What failed to compile and why, one line each.
- Anything you fixed differently from what the code intended, and the reasoning.
- Any of the nineteen items you believe is now wrong, or was wrong to begin with.
- Which acceptance criteria you verified **by looking** versus by inference.
- Anything you noticed while looking that is not on the list. That is the most
  valuable thing you can bring back — the list was written from one screenshot.

## Two things not to do

- Do not undo a decision to make a build error go away. Every one of the
  nineteen has a reason written next to it in the code; if the reason is wrong,
  argue with it in your report rather than deleting it.
- Do not add new features. Wave 5 and the filtering exploration are separate
  work and must not arrive inside a QA pass.
