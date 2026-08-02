# Accessibility

MythLog answers one question — *what happened while I was away?* — and that
question does not belong only to people who can see a timeline, hold a mouse
steady, or read 9-point text. This page states what the app does for
accessibility, how each claim was checked, and what is still missing.

## What we claim

MythLog targets **WCAG 2.1 Level AA, as it applies to a native macOS
application**. WCAG is written for the web, so the mapping is: every control
has a programmatic name, role, and value; nothing is conveyed by color alone;
text and controls scale with the system text size; every operation is possible
without a pointing device; and motion respects the user's system preference.

We do **not** claim the app is "100% accessible". That is not a claim anyone can
make honestly. The [Known gaps](#known-gaps) section below is the other half of
this page and is meant to be read with it.

## Supported

### VoiceOver

- **The timeline canvas is one accessibility container.** Its decorative layers
  — the backdrop grid, the spine, the time-axis ticks, and the connector line
  from each node down to the spine — are hidden from VoiceOver, so it never
  lands on chrome that has nothing to say.
- **Traversal is chronological.** Nodes are drawn in a severity-driven z-order
  so critical events float above their neighbours. Reading a timeline in that
  order would be nonsense, so every node carries an explicit sort priority
  derived from its position in time: VoiceOver walks the canvas oldest to
  newest, matching how the events read on screen.
- **Every event node announces a full sentence** — title, detail line, severity
  in words, and full timestamp. For example: *"Terminal. com.apple.Terminal.
  Critical severity. App event at 12 May 2025 at 3:04:05 PM."* An event that is
  visible only because it matches the current search says so as its value.
- **Nodes are buttons** with a hint (*"Opens this event in the inspector"*), a
  selected trait, and an *Open details* custom action.
- **The floating event caption is hidden** — it repeats its own node's title,
  time, and category, so exposing it would double every event.
- **The toolbar is fully named**: recorder health, ledger continuity, category
  filters, time-range presets, zoom stepper and slider, search field, and the
  inspector toggle all have labels, and values where they carry state.

### Dynamic Type

Every text size and control dimension in the viewer is declared with
`@ScaledMetric` relative to the text style it sits beside, so toolbar buttons,
filter chips, tooltips, inspector rows, and badges grow with the system text
size rather than staying pinned to their design values. Fixed-width label
columns (`PID`, `Authorization`, `Records`, the zoom readout) scale with them,
so a heading never truncates before the value it labels.

One deliberate exception is documented in
[Known gaps](#known-gaps): the diameter of a timeline event node.

### Color is never the only signal

- **Severity.** Warning and critical carry distinct badge silhouettes — a
  circle and a triangle — on the canvas and on the inspector's summary icon,
  and the inspector's event list states the severity in words. Debug, info,
  and notice are deliberately unbadged (see [Known gaps](#known-gaps)).
- **Recorder health** and **ledger continuity** use a distinct glyph per state
  instead of a bare colored dot, so *Linked* versus *Chain issue*, and healthy
  versus critical, do not depend on telling blue from red.
- Status text always accompanies the indicator it belongs to.

### Keyboard

Every control that VoiceOver can reach can also be operated without a mouse.
The two controls that were previously mouse-only — the inspector's event list
and the ledger status badge — are now buttons.

Because tabbing across the canvas means stepping through every event in the
window, the Timeline menu carries explicit shortcuts:

| Shortcut | Command |
| --- | --- |
| <kbd>⌥</kbd><kbd>←</kbd> | Select Previous Event |
| <kbd>⌥</kbd><kbd>→</kbd> | Select Next Event |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>←</kbd> | Select Oldest Event |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>→</kbd> | Select Newest Event |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>I</kbd> | Show/Hide Inspector |
| <kbd>⌘</kbd><kbd>+</kbd> / <kbd>⌘</kbd><kbd>-</kbd> | Zoom In / Zoom Out |

With nothing selected yet, stepping backwards starts at the newest event and
stepping forwards starts at the oldest, so the first keypress always lands
somewhere.

Option-arrow is also "move by word" in a text field, and AppKit offers a menu
item its key equivalent before the field editor sees the key. The four
event-selection commands therefore disable themselves while a text field is
being edited, so the search field keeps its word-wise cursor movement.

### Reduce Motion

With **System Settings → Accessibility → Display → Reduce motion** on, node
selection and hover stop springing and scaling, the canvas jumps rather than
sliding when a new event arrives, and the inspector and setup banner cross-fade
instead of travelling. Every state change still happens and nothing becomes
unreachable.

## How this was verified

Two different things, and it matters which is which.

**Automated**, in the project's test runner (`swift run -c debug mythlog-tests`,
part of the standard build gate). Eighteen accessibility tests assert:

- every `AlarmSeverity` case produces a label naming its severity in words —
  adding a severity without wording fails the suite;
- labels carry title, detail, and timestamp, read as complete sentences, and do
  not speak a subtitle that merely repeats the title;
- the search-only dimmed state explains itself as an accessibility value;
- warning and critical do not share a badge silhouette, and each recorder
  health level has its own — the properties that actually survive grayscale;
- the severity tag never puts white text on the two near-white fills;
- accessibility identifiers are unique and well formed;
- traversal priorities strictly descend with chronological position;
- keyboard event stepping walks in order, clamps at both ends rather than
  wrapping, and is a no-op on an empty timeline;
- Reduce Motion removes animation and scale rather than shortening them.

**Manual**, and required before each release: the VoiceOver, Dynamic Type,
grayscale, and keyboard-only passes in
[Release Checklist](RELEASE_CHECKLIST.md). No automated check in this repository
observes the rendered UI, so those four passes are the only evidence that the
app behaves as described above on screen.

## Known gaps

These are open, not hidden.

1. **No automated UI test drives the real interface.** The traversal-order rule
   is asserted at the model level (`TimelineAccessibilityOrder`), not through
   the rendered view. Closing this needs an XCUITest bundle, which needs a host
   application target; the package's Xcode project (`project.yml`) defines only
   the app shell, and the release gate runs SwiftPM rather than
   `xcodebuild test`. The accessibility identifiers added throughout the app are
   the groundwork for that suite. Until it exists, VoiceOver traversal is
   verified by hand.
2. **Timeline event node diameter does not scale with Dynamic Type.** The
   diameter is the same value the layout engine uses to reserve lanes and score
   placements, so growing it at draw time would overlap neighbours the engine
   had scored as clear. The glyph inside stays proportional to the node; the
   event's caption text and its entire VoiceOver description do scale, so no
   information is lost — only the dot is a fixed size.
3. **Debug, info, and notice severities share one visual treatment.** They are
   the un-emphasized band by design and carry no severity badge. The exact word
   is always available from VoiceOver and from the inspector's severity tag, but
   on screen those three are not distinguishable from one another by shape.
4. **Tabbing across the canvas is tedious.** It is not a focus trap — Tab
   continues past the last node — but a window showing hundreds of events has
   hundreds of tab stops. The ⌥-arrow commands above are the intended path.
5. **macOS Full Keyboard Access must be enabled by the user** for Tab to reach
   buttons and other non-text controls anywhere in macOS. That is a system
   setting (**System Settings → Keyboard → Keyboard navigation**); an app cannot
   turn it on. The menu shortcuts above work either way.
6. **English only.** All labels, hints, and values are hardcoded English
   strings; the app is not localized, and VoiceOver will read them in English
   regardless of system language.
7. **Contrast has not been measured instrument-in-hand.** Known color-only and
   low-contrast cases were fixed, but no automated contrast-ratio check runs
   over the palette, and the category tint colors have not been measured
   against every background they appear on.
8. **Increase Contrast and Differentiate Without Color are not read.** The
   non-color cues above are applied unconditionally, which is stronger than
   applying them only under `Differentiate Without Color` — but the app does not
   otherwise adapt when those settings are on.

## Filing an accessibility bug

Accessibility bugs are ordinary bugs and belong in the public tracker: open an
issue at [github.com/JCTec/MythLog/issues](https://github.com/JCTec/MythLog/issues)
using the bug report template.

Please include, as far as you can:

- which assistive technology or setting was in use (VoiceOver, Full Keyboard
  Access, Reduce Motion, a text size, a color filter, Zoom);
- what you expected to hear, see, or reach, and what happened instead;
- where in the app — the timeline canvas, the toolbar, the inspector, or a
  specific sheet.

A VoiceOver transcript or a screen recording helps a great deal. As with any
MythLog issue, please do not paste ledger records, hostnames, file paths, or
tokens into a public issue — see [SECURITY.md](../SECURITY.md). "This is
unusable with VoiceOver" with no further detail is still a valid and welcome
report.
