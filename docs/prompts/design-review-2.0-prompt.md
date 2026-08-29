# Effort: Design review of MythLog 2.0, grounded in real capability

**This is a review, not an implementation.** Produce a written critique. Do not
write SwiftUI, do not refactor views, do not change the app. The output is one
document: `docs/DESIGN_REVIEW_2.0.md`.

## Read first, in this order

1. **`docs/TECHNICAL_CAPABILITIES.md`** — what macOS actually permits MythLog to
   observe, split into three capability tiers, plus the constraint the hash chain
   places on the event schema. This is the ground truth for the review. A design
   recommendation that contradicts it is invalid regardless of how good it looks.
2. **`MythLog 2.0.pdf`** at the repository root — the proposed redesign: a dense
   event list (TIME / EVENT / DETAIL / SOURCE), a reduced timeline strip, filter
   pills with counts, and an inspector showing payload plus ledger provenance.
3. The shipping implementation in `Sources/MythLogAppSupport/` — `Timeline/`,
   `Inspector/`, `Filters/`, `State/` — and the event model in
   `Sources/MythLogCore/AlarmEvent.swift`.
4. `docs/ACCESSIBILITY.md` — guarantees the current app already makes, which the
   redesign must not silently drop.

## Governing principles

**Design against the capability tiers, not against a wish.** Per
`TECHNICAL_CAPABILITIES.md`, MythLog has three different ceilings depending on
how it is signed: the sandboxed App Store build (Tier A), the unsandboxed
Developer ID build (Tier B), and a hypothetical Endpoint Security build that
requires Apple's approval (Tier C). Any screen you endorse must state which tier
it assumes. A layout that only makes sense with Tier B data is a Developer ID
feature, and the App Store build needs a defined appearance for it.

**Judge against the worst realistic case, never the mockup's happy path.** The
PDF shows fourteen events; its own header reports 5,362 records. That gap is the
review. A layout that is elegant at fourteen rows and unreadable at five thousand
is an illustration, not a design.

**Implementation cost is not grounds for rejection.** If the right answer takes
months, recommend it anyway and say what it costs. Note effort as information,
never as a veto. Prefer a design that survives three years of feature growth over
one that ships a quarter sooner.

**Design for signals that do not exist yet.** `TECHNICAL_CAPABILITIES.md`
enumerates realistic future sources — volume mount, fast user switching, external
display, failed logins, TCC prompts, USB attach, screen sharing. The layout must
absorb new kinds, new severities, and new detail shapes without redesign.
Anything that needs a hand-edit when a source is added is a defect; name it.

## Part 1 — Capability alignment

For every element in the mockup, state which tier it requires and whether it
survives in the App Store build.

Specifically adjudicate:

1. **`SOURCE` column.** The mockup shows `kernel`, `fseventsd`,
   `com.apple.dt.Xcode`, `loginwindow`, `mythlogd`. Check against
   `AlarmEvent.source` and what each event source actually populates today.
   Which of these are real, which are aspirational, and which require Tier B or
   Tier C?
2. **`13:31 Screen unlocked / Password, 2nd attempt`.** Per the capabilities
   doc, failed-attempt detail comes from the system unified log, which is Tier B
   — unavailable in the App Store build. This is arguably the most compelling row
   in the mockup. What does that row look like in Tier A? Decide whether the
   design degrades the cell, hides the row, or shows an explicit
   capability-gap state.
3. **`User: jc · console session`** in the inspector. No user/session field
   exists on `AlarmEvent`. Is this worth a schema change, given the constraint in
   Part 3?
4. **Per-event actor attribution** — "which process changed this file". Tier C
   only, gated behind an Apple approval that may never be granted. Should the
   design reserve space for it, or omit it until the entitlement exists?
5. **The capability-gap state itself.** The app already has the right mechanism
   in `SandboxEnvironment.unavailableReason` and its attributed-failure
   principle. Propose how an unavailable *event source* should read in the list,
   the timeline, and the filters — so a Tier B signal missing from a Tier A build
   is visibly "not available in this build", never silence.

## Part 2 — Density and layout

State for each: **holds** / **degrades acceptably** / **breaks**, with the
specific failure and, where possible, the row count at which it fails.

- 5,000+ events in the 24h view.
- A burst of 300 file events in ten seconds from one `fseventsd` storm — a build,
  a `git checkout`, a dependency install.
- Many events sharing one timestamp to the second.
- Two years of recording, roughly 2M records, in the 7d view: render and scroll
  cost.
- Zero events — a new install before the recorder runs.
- A machine closed nine days: one wake, one unlock, nothing between.
- A filter combination matching nothing.
- A file path long enough to fill DETAIL three times over.
- An app with only a bundle identifier because no display name resolved.
- German and French running 30–40% longer than English.
- A `CUSTOM` event whose detail is arbitrary user text, including newlines and
  emoji.
- **Maximum Dynamic Type.** The hard one: fixed columns cannot reflow the way
  prose does. Say concretely what happens to TIME / EVENT / DETAIL / SOURCE at
  the largest accessibility size, and whether the answer is horizontal scrolling,
  column collapse, or a different row structure entirely.
- Split-screen at half a 13" display; and an ultra-wide display.
- Light mode — the mockup is dark-only.
- Grayscale, given severity currently leans on colour.
- VoiceOver across table + timeline + inspector: is the reading order coherent?
- Live events arriving while scrolled into history — does the view jump, and who
  wins?

## Part 3 — The data model

`HashChainLedger.computeHash` HMACs the canonical JSON of the whole `AlarmEvent`,
and `verify()` re-encodes stored records to recheck them. Therefore **adding a
non-optional field retroactively breaks verification of every existing ledger**;
new fields must be `Optional`, defaulting to `nil`. See
`TECHNICAL_CAPABILITIES.md` §4.

Given that:

- List every field the 2.0 design needs that `AlarmEvent` lacks.
- For each, say whether it can be `Optional`-added safely, or needs a versioned
  ledger migration.
- The inspector shows structured JSON, but `metadata` is `[String: String]`.
  Decide: encoded string in `metadata`, or a new optional structured field?
- Confirm whether any proposed change requires re-verifying or migrating ledgers
  users already have. A design that silently invalidates a user's tamper-evidence
  history is unacceptable — that history is the product.

## Part 4 — Integrity states

The mockup only shows the happy path (`Ledger verified`, `Verified`). These are
the states the product exists for, and the design has no answer for them yet.

- Verification **fails** at record #3,201. How do the list, timeline, and
  inspector show what is before, at, and after the break? This is the single most
  important screen in the app and the PDF does not contain it.
- The ledger was truncated and the iCloud anchor disagrees with the local head.
- The recorder was stopped for six hours: a **coverage gap**, not a quiet period.
  These must never look the same.
- Anchoring fails because iCloud is signed out.
- History spans multiple rotated ledger segments.

## Part 5 — Direct questions

Answer each with a recommendation, not a survey.

1. **The double-sided timeline.** The current app places nodes above and below
   the axis; it reads well when sparse and is suspected not to survive density.
   Confirm or refute with a row count. If it should go, name the replacement —
   density histogram, one lane per category, heatmap strip — and say why that
   scales.
2. **Timeline as hero, or timeline as scrubber?** The PDF reduces the canvas to a
   strip and lets the list dominate. Commit to one, and say which better serves
   "what happened while I was away?"
3. **Is a fixed four-column table viable** under Dynamic Type and localization,
   or should rows be a composed layout that reflows? Take a position.
4. **Where does ledger provenance live** — inspector only, a per-row indicator,
   or a dedicated verification view? Weigh putting cryptographic detail in front
   of users who did not ask for it against the product's core claim.
5. **Binary naming.** The mockup shows `mythlogd` and `mythlog-cli`; the shipping
   binaries are `mythlog-agent` and `mythlogctl`. Is the rename worth a breaking
   change to existing installs, configs, and docs?
6. **Should the App Store and Developer ID builds present as one product or
   two?** Given they have materially different observational ceilings, is a
   single UI with capability gaps honest and coherent, or does it make the App
   Store build feel broken?

## Deliverable

`docs/DESIGN_REVIEW_2.0.md`:

- Capability alignment table: every mockup element mapped to its required tier.
- A verdict per density/layout scenario, with the specific failure.
- Schema changes required, each marked safe-additive or needs-migration.
- Proposed treatment for each integrity state.
- Direct answers to the six questions.
- Three highest-risk assumptions — the ones that mean rework if wrong.
- What to cut to ship sooner, and what must not be cut.

## Rules

- Cite real files, types, and line numbers for claims about current behaviour.
  Verify by reading code; never infer from a name.
- No hedging. "May be a concern at scale" is not a finding — give the number of
  rows, or say you could not determine it and why.
- If a scenario cannot be evaluated without running the app, say so plainly.
- Do not soften a conclusion because the fix is expensive.
- If something in `TECHNICAL_CAPABILITIES.md` is marked as inferred and your
  recommendation depends on it, flag that the assumption needs a hardware test
  before the work is scheduled.
