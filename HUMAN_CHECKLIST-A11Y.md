# Human accessibility checklist

For Juan Carlos, before shipping the accessibility work on
`a11y/full-accessibility-pass`.

Everything on this page needs a human. The eighteen automated tests in
`Sources/MythLogTests/AccessibilityTests.swift` check the *rules* — that a
critical event's label contains the word "critical", that warning and critical
do not share a badge silhouette, that traversal priorities descend with time.
No automated check in this repository looks at the rendered interface, so
nothing below has been machine-verified. It is the only evidence that
`docs/ACCESSIBILITY.md` tells the truth.

Run these against a real build with events already in the timeline
(`./scripts/run-viewer-debug.sh`, or the DMG from the release gate). A window
showing an empty timeline will pass every one of these without proving
anything.

---

## 1. VoiceOver

Turn on VoiceOver with <kbd>⌘</kbd><kbd>F5</kbd>. Navigate with
<kbd>⌃</kbd><kbd>⌥</kbd>+arrows. Put the mouse away — genuinely, not just
"mostly".

- [ ] Every toolbar control is reachable and announces a name that means
      something: recorder health, ledger status, each category filter, the
      time-range presets, zoom out / zoom slider / zoom in, the search field,
      and the inspector toggle.
- [ ] The search field is announced as *"Search all events"* **while it already
      has text in it**. This is the specific thing that was broken — a
      placeholder stops being read once a field is non-empty.
- [ ] Entering the timeline announces it as a container ("Event timeline")
      rather than dropping you straight onto a node.
- [ ] Events are read **oldest first**, and that order does not change when you
      select a critical event (which is drawn above its neighbours). This is the
      single most likely thing to have gone wrong.
- [ ] Each event reads as a sentence you would accept from a person, e.g.
      *"Terminal. com.apple.Terminal. Critical severity. App event at 12 May
      2025 at 3:04:05 PM."* Listen for wording that is terse, doubled, or
      robotic.
- [ ] VoiceOver never lands on the background grid, the spine, the time-axis
      tick labels, the connector lines, or the floating event caption.
- [ ] Selecting an event announces it as selected, and the *Open details* custom
      action is offered. (Find the chord for the actions menu in VoiceOver
      Utility — I am not confident of it and would rather not send you chasing a
      wrong one. It is **not** the two-finger rotate you know from iPadOS.)
- [ ] Type something in the search box that matches an event belonging to a
      hidden category. That event should say it is *"Hidden by the current
      category filters, shown because it matches your search."*
- [ ] Open the inspector. Its event list rows are reachable, named, and
      activating one changes the selection.
- [ ] Open **Filter Settings**, **Ledger Integrity**, and **Notifications**.
      Every button in each sheet is reachable and named, and closing returns
      focus somewhere sensible.

## 2. Dynamic Type

**System Settings → Accessibility → Display → Text size**, dragged to the
largest setting. Relaunch MythLog.

- [ ] No text is clipped, truncated with an ellipsis it did not have before, or
      overlapping.
- [ ] Toolbar buttons still show their glyphs and are still tappable — nothing
      is squeezed to zero.
- [ ] The label column headings in the recorder health popover (`PID`, `State`,
      `Ledger`) and in the Ledger Integrity and Notifications grids are fully
      readable, not cut off before their values.
- [ ] Open **Filter Settings** and scroll the *New Filter* editor. The
      **Create** button is reachable — it used to fall off the bottom of that
      fixed-height sheet.
- [ ] Timeline event captions are readable and their boxes have grown with the
      text.
- [ ] Expected, not a bug: the event **dots** themselves stay the same size.
      That is gap 2 in `docs/ACCESSIBILITY.md`. Confirm it looks deliberate
      rather than broken.
- [ ] Set text size back to default and confirm the app looks exactly as it did
      before this branch. The scaled metrics resolve to the original values at
      the default setting, so any visual change here is a bug.

## 3. Color

**System Settings → Accessibility → Display → Color Filters → Grayscale**, on.

- [ ] A warning event and a critical event are distinguishable from each other
      at a glance — look for the circle badge versus the triangle badge, not for
      a shade difference.
- [ ] Both are distinguishable from ordinary events.
- [ ] The recorder health pill is readable as healthy / warning / critical /
      unknown by its glyph. Wait out the five seconds it takes to collapse its
      title, then check again — the glyph is all that is left.
- [ ] The ledger badge distinguishes *Linked* from *Chain issue* without color.
- [ ] Select an event and check the inspector's severity tag: the `DEBUG` and
      `INFO` tags should be legible, not white-on-near-white.
- [ ] Turn grayscale off and confirm the badges do not now look cluttered at
      normal saturation. They are new; they should read as design, not as
      warnings bolted on.

## 4. Keyboard only

**System Settings → Keyboard → Keyboard navigation**, on. Then put the mouse
somewhere you cannot reach.

- [ ] <kbd>⌥</kbd><kbd>←</kbd> and <kbd>⌥</kbd><kbd>→</kbd> step between events
      in time order, and the inspector follows.
- [ ] <kbd>⌥</kbd><kbd>⌘</kbd><kbd>←</kbd> and <kbd>⌥</kbd><kbd>⌘</kbd><kbd>→</kbd>
      jump to the oldest and newest events.
- [ ] Those four shortcuts do **not** fire while you are typing in the search
      field — arrow keys there should move the text cursor.
- [ ] Tab reaches the toolbar controls, the ledger status badge, and the
      inspector rows.
- [ ] Tab is never trapped: from inside the timeline you can keep tabbing and
      eventually leave it.
- [ ] Every sheet can be opened, operated, and dismissed by keyboard —
      <kbd>Esc</kbd> closes Filter Settings.
- [ ] The whole app can be driven from the menu bar alone
      (<kbd>⌃</kbd><kbd>F2</kbd>).

## 5. Reduce Motion

**System Settings → Accessibility → Display → Reduce motion**, on.

- [ ] Selecting an event does not spring or scale.
- [ ] Hovering an event does not scale it.
- [ ] A newly arriving event does not slide the canvas sideways — it may jump,
      which is correct.
- [ ] Opening and closing the inspector cross-fades rather than sliding in from
      the right.
- [ ] The recorder setup banner cross-fades rather than dropping from the top.
- [ ] Turn Reduce Motion off and confirm all the original animation is back.

---

## If something fails

Fix it, or add it to the **Known gaps** section of `docs/ACCESSIBILITY.md`. Do
not quietly drop it — the point of that page is that it is complete. If a gap
listed there turns out to be closed, delete it in the same commit.

Once every box is ticked, this file can be deleted: `docs/ACCESSIBILITY.md` is
the durable document, and the recurring version of these checks now lives in
the *Accessibility Smoke Test* section of `docs/RELEASE_CHECKLIST.md`.
