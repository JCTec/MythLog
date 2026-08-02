# Effort: Accessibility (a11y) completion for MythLog

Read this whole prompt before starting. Work on a new branch off the current
default branch, named `a11y/full-accessibility-pass`. Commit after each phase
completes and its gate passes. Never push. Never weaken, skip, or delete an
existing test to make it pass. If you get blocked for more than two attempts
on the same problem, stop and write `BLOCKED.md` at the repo root describing
exactly what you tried and why it's stuck, then move to the next independent
phase instead of guessing.

**Governing principle: NO SILENT GAPS.** Every interactive control in the app
must be reachable, nameable, and operable via VoiceOver and keyboard alone. If
something genuinely cannot be made accessible in this pass (e.g. it depends on
a third-party dependency limitation), it must be explicitly documented as a
known gap in `docs/ACCESSIBILITY.md` — never silently left out. Do not claim
"100% accessible" anywhere in docs or copy; claim conformance against a
concrete standard (WCAG 2.1 AA equivalent for a native macOS app) and list
explicitly what was verified.

**Context**: an audit found: scattered but incomplete `.accessibilityLabel` /
`.accessibilityHint` / `.accessibilityValue` usage on `TimelineEventNode.swift`,
`CategoryFilterButton.swift`, `ToolbarIconButton.swift`,
`TimelineFilterStatePill.swift`; no `.accessibilityElement(children:)`
grouping anywhere; decorative timeline chrome (`TimelineBackdrop`,
`TimeTicks`, `TimelineConnector`) not marked `.accessibilityHidden`; zero
`@ScaledMetric` usage despite hardcoded pixel font sizes in
`TimelineEventNodeIcon.swift`, `TimeTicks.swift`, `TimelineCanvasChrome.swift`,
`TimelineEventLabel.swift`; severity in `AlarmSeverity+TimelineUI.swift`
conveyed by color alone with no shape/icon backup; zero accessibility
identifiers anywhere (blocking future UI testing); zero accessibility
documentation in the repo; zero accessibility-specific tests.

## Phase 1 — VoiceOver structure for the timeline

- Wrap the timeline's decorative layers (`TimelineBackdrop`, `TimeTicks`,
  `TimelineConnector`, axis lines, grid) in `.accessibilityHidden(true)` so
  VoiceOver never lands on them.
- Group the timeline into a single accessibility container using
  `.accessibilityElement(children: .contain)` at the appropriate level so
  VoiceOver traverses events in a predictable left-to-right (or chronological)
  order, not visual z-order.
- Add `.accessibilitySortPriority` where traversal order doesn't naturally
  match chronological order.
- Verify each `TimelineEventNode` label (`eventNodeAccessibilityLabel`) reads
  naturally as a full sentence (category, severity, time) — audit and rewrite
  if terse or ambiguous.
- Add `.accessibilityHint` to event nodes describing what activating them does
  (opens inspector / detail view).
- Add a custom accessibility action (`.accessibilityAction`) for "Open
  details" if activation currently requires a specific gesture VoiceOver
  users can't easily trigger.

## Phase 2 — Dynamic Type support

- Find every hardcoded `.font(.system(size:))` / fixed-pixel font call across
  `Sources/MythLogAppSupport` (start with the files named in the audit) and
  convert to `@ScaledMetric` relative to a sensible base size, or to a
  semantic `Font.TextStyle` where the fixed size was arbitrary rather than
  deliberate (e.g. icon glyphs that must stay a fixed visual size relative to
  their container can stay fixed, but *label/caption text* must scale).
- Confirm the app doesn't clip or truncate text unacceptably at accessibility
  text sizes (XXL) — test at both default and largest Dynamic Type settings.
- Where a fixed size is kept intentionally (e.g. a small glyph inside a
  fixed-size icon badge), leave a code comment explaining why it's exempt.

## Phase 3 — Color is never the only signal

- In `AlarmSeverity+TimelineUI.swift` / `TimelineEventNodeIcon.swift`, add a
  non-color differentiator for severity: e.g. a distinct SF Symbol badge, ring
  thickness, or a small overlay glyph (exclamation for critical, dot for
  warning) so color-blind and grayscale-display users can distinguish
  severity without relying on hue.
- Audit `LedgerStatusBadge.swift` and any other status/health indicators for
  the same color-only pattern; add text or icon backup wherever a bare color
  dot is the only cue.

## Phase 4 — Accessibility identifiers

- Add `.accessibilityIdentifier` to all primary interactive controls (toolbar
  buttons, filter pills, time range selector, search field, timeline event
  nodes, menu items) using a consistent naming scheme (e.g.
  `timeline.event.node`, `toolbar.button.lock`), so a future XCUITest suite
  can target them reliably. This is infrastructure for Phase 6, not
  user-facing.

## Phase 5 — Keyboard navigation

- Confirm every interactive element reachable via VoiceOver is also reachable
  via keyboard-only navigation (Tab/Shift-Tab, arrow keys where appropriate
  for the timeline). Fix any focus traps or unreachable controls. Document
  any keyboard shortcuts in `docs/ACCESSIBILITY.md`.

## Phase 6 — Tests

- Add unit tests verifying accessibility label content stays correct as event
  data changes (e.g. a record with severity `.critical` produces a label
  containing "critical").
- Add a basic UI test (using the new accessibility identifiers from Phase 4)
  that exercises VoiceOver-relevant traversal order isn't broken by future UI
  changes, if the project's custom test runner can support it — if it can't,
  document that gap explicitly rather than skipping silently.

## Phase 7 — Documentation

- Create `docs/ACCESSIBILITY.md`: state what's supported (VoiceOver
  navigation of the timeline and toolbar, Dynamic Type, keyboard navigation,
  non-color severity indicators), what's explicitly out of scope or not yet
  verified, and how to file an accessibility bug.
- Add a short accessibility mention and link to `docs/ACCESSIBILITY.md` from
  `README.md`.
- Update `docs/RELEASE_CHECKLIST.md` with a manual VoiceOver smoke-test step
  before each release.

## Phase 8 — Verify

- Run the full existing lint/format/test gate (same commands as
  `docs/RELEASE_CHECKLIST.md`'s Build Gate section) and confirm nothing
  regressed.
- Grep the diff for any remaining hardcoded font sizes or un-hidden
  decorative views you missed.
- Produce a short summary commit message per phase; do not squash into one
  giant commit.

## Human checklist

Some things can't be verified by an agent. Write `HUMAN_CHECKLIST-A11Y.md` at
the repo root listing, for Juan Carlos to do manually before shipping:

- Turn on VoiceOver (Cmd+F5) and navigate the entire timeline and toolbar
  without a mouse; confirm every control is reachable and makes sense read
  aloud.
- Set Dynamic Type to the largest accessibility size in System Settings and
  confirm no clipped/truncated text.
- Switch display to grayscale (System Settings > Accessibility > Display >
  Color Filters > Grayscale) and confirm severity is still distinguishable.
- Navigate the entire app via keyboard only (no mouse) and confirm nothing is
  a dead end.
