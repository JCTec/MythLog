# Effort: fix the facet popover collapsing to a sliver

Read this whole prompt before writing code.

Work from the repository root — the `Logging System/` directory. That is the git
root, so branching and committing only work from there.

Two trees matter:

| Path | Role | Access |
| --- | --- | --- |
| `MythLogPlayground/` | The app you are fixing | **Read and write** |
| Everything else at the root (`Sources/`, `docs/`, `scripts/`, `Xcode/`, …) | The shipping app | **Read only** |

**The read-only rule is absolute and is verified, not trusted.** Before
committing, run:

```sh
git status --porcelain | grep -v '^.. MythLogPlayground/' && echo "VIOLATION" || echo "clean"
```

If anything outside `MythLogPlayground/` is modified, revert it before
committing. The shipping app is live, on the App Store, and being fixed on its
own track.

Work on a branch named `fix/facet-panel-height` (`git switch -c` carries the
uncommitted working-tree changes with it, which is what you want — see below).
Never push. Never weaken a gate, delete a test, or silence a warning to get
green. If blocked twice on the same problem, write `BLOCKED.md` at the
repository root with exactly what you tried, then stop.

---

## The defect

Open any category chip's disclosure (the chevron on `Session`, `Files`, …).
The popover that appears — `FilterFacetPanel` — presents a couple of rows tall:
the header fits, and the first facet row is sliced in half. The list inside is
fine; the panel around it has almost no height.

**Broken looks like:** a popover roughly the height of its own header, with
`session.unlock` clipped mid-glyph. **Fixed looks like:** a panel exactly as
tall as its content for short lists, and `Metrics.facetPanelMaxHeight` tall,
scrolling, for long ones.

## Why it happens

A popover sizes itself to its content's *ideal* size. A `ScrollView` does not
have a useful one — it is fully flexible, so its ideal height collapses to
almost nothing — and the panel's `.frame(maxHeight: Metrics.facetPanelMaxHeight)`
was a ceiling on a value that had already collapsed. A cap cannot raise a
height; the popover presented at the collapsed ideal and clipped.

## Required end state

In `Sources/DesignSystem/Organisms/FilterFacetPanel.swift`:

- The scroll view has a **definite** height: the measured natural height of its
  content, capped at `Metrics.facetPanelMaxHeight`. A category with two values
  gets a panel two values tall; a category with sixty scrolls at the cap and
  still shows the "N less common … not listed" line.
- Width stays `Metrics.facetPanelWidth`. The `facetValues.isEmpty`
  ("Reading this window…") branch is unchanged.
- No behaviour of the rows, sections, or the never-a-silent-cap rule changes.

## A candidate fix is already in the working tree

`FilterFacetPanel.swift` has an **uncommitted** change that measures the scroll
content with `onGeometryChange(for:of:action:)` into `@State` and applies
`.frame(height: min(max(contentHeight, Metrics.facetRowHeight), Metrics.facetPanelMaxHeight))`.

Review it critically rather than assuming it is right. Keep it, improve it, or
replace it — the end state above is what matters, not the authorship. Two facts
already checked, so you do not have to re-litigate them: `onGeometryChange` is
macOS 13+ per the DocC data for the symbol (verified 2026-08-10; deployment
target here is 14.0, so no availability guard), and its `transform` must be
`@Sendable` while its `action` runs in the view's isolation, which is what lets
it write `@State` cleanly under strict concurrency.

## House rules that bind this change

- Swift 6 strict concurrency, complete. **Zero warnings.** No
  `@unchecked Sendable`, no `nonisolated(unsafe)`, no `@preconcurrency`.
- Every dimension resolves through `Tokens/` — use the existing
  `Metrics.facetPanel*` and `Metrics.facetRowHeight` tokens; if you genuinely
  need a new one, it goes in `Metrics.swift` with a doc comment saying why.
- `DesignSystem/` may reference `Primitives/` and `Model/` only.
- If you add any file, re-run `xcodegen generate` (the project pulls `Sources/`
  recursively). A comment-only change needs nothing.

## Verify

All of these, in order:

```sh
cd MythLogPlayground
./Scripts/check-layering.sh --self-test
xcodebuild -project MythLog.xcodeproj -scheme MythLog \
  -configuration Debug -destination 'platform=macOS' test
```

Expect `Self-test passed: 6/6 violations caught`, then `Layering checks
passed`, then the full suite green with no warnings.

**Then verify the fix visually, not by faith** — this bug shipped precisely
because nothing looked at the rendered popover:

- Extend `Tests/RenderShots.swift` with the panel at both extremes: once with a
  category holding ≤3 values, once with enough values to exceed the cap. Host
  the panel with `.fixedSize()` inside the shot so the PNG height reflects the
  measured height, run with `MYTHLOG_RENDER_SHOTS=/tmp/mythlog-shots`, and
  check the two PNGs (`sips -g pixelHeight`): the short one hugs its content,
  the tall one stops at the cap. If hosting a self-sizing view under
  RenderShots' fixed-size window proves genuinely awkward, previews in
  `Sources/Previews/FilterPreviews.swift` showing both extremes are an
  acceptable fallback — but say in the commit body which you did and why.
- Run the app (`open MythLog.xcodeproj`, Cmd+R is not scriptable — use
  `xcodebuild build` plus launching the product if you need a live check) and,
  if a human is available, have them click a chip's chevron.

## Commit

One commit on `fix/facet-panel-height`, containing the panel fix and whatever
verification you added, nothing else. After the read-only check above:

```
Fix facet popover collapsing to a sliver

A popover sizes itself to its content's ideal size, and a ScrollView's
ideal height is nothing like its content's: it is fully flexible, so
.frame(maxHeight:) capped a value that had already collapsed, and the
panel presented a couple of rows tall with the first row clipped.

The scroll content's height is now measured (onGeometryChange, macOS 13+,
no guard needed at this target) and the scroll view is given exactly that
height up to Metrics.facetPanelMaxHeight: a category with two values gets
a panel two values tall; a category with sixty scrolls at the cap and
still says how many values it did not show.
```

Do not push.
