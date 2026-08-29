# MythLog 2.0 — Design Brief

For the designer. This is a brief, not a spec: it describes the product, the
real constraints it lives inside, the flows that need designing, and the open
questions only design can answer. Where a constraint is technical, it is
translated into what it means for the screen rather than for the code.

Companion documents: `docs/TECHNICAL_CAPABILITIES.md` (what macOS actually
permits the app to observe), `docs/ACCESSIBILITY.md` (guarantees the current app
already makes), and `MythLog 2.0.pdf` (the proposed direction being reviewed).

---

## 1. What MythLog is

MythLog records what happened on a Mac while its owner was away, and makes that
record trustworthy.

A background recorder captures meaningful local events — the screen locking and
unlocking, the machine sleeping and waking, apps launching, chosen folders
changing — and writes each one into an append-only ledger where every entry is
cryptographically chained to the one before it. If anything in that history is
altered, removed, or reordered, verification fails and the app says so.

Two things follow, and both matter for design:

**The record is the product, not the feed.** Plenty of apps show recent
activity. MythLog's claim is that its history can be *trusted* — that is the
reason to choose it. Trustworthiness that is never visible is worth nothing, and
trustworthiness that shouts constantly is exhausting. Calibrating that is a
design problem.

**Everything is local.** No account, no server, no analytics. Nothing to sign
into, nothing to sync, no social layer, no sharing. The design has fewer surfaces
than a typical app and should feel calmer for it.

## 2. Who it is for

Someone who shares physical space and wants a dependable answer to "was anyone
on my machine?" — a person in a shared flat or office, a journalist or
researcher, an IT or security professional, someone in an unsafe domestic
situation. They are not necessarily technical. They do open the app *because
something felt off*, which means the moments that matter most are the anxious
ones.

That has a direct consequence: the app is used in two very different moods —
**idle curiosity** (glance, reassure, close) and **active investigation**
(something happened, find it, prove it). The design has to serve both without
making the first feel like work or the second feel like a toy.

---

## 3. The central design problem: two editions

MythLog ships in two forms, and **they can observe genuinely different amounts**.
This is not a licensing decision or a feature gate — it is a hard limit imposed
by how Apple sandboxes App Store software. It cannot be engineered away, and
pretending otherwise would be dishonest.

| | **App Store edition** | **Direct download edition** |
| --- | --- | --- |
| How it arrives | Mac App Store | Signed, notarized `.dmg` from the developer |
| Sandboxed | Yes (Apple requires it) | No |
| Sees screen lock / unlock | Yes | Yes |
| Sees sleep / wake, lid, power | Yes | Yes |
| Sees apps launching / quitting | Yes | Yes |
| Sees chosen folders change | Yes (folders the user grants) | Yes (any path) |
| Sees drives mounted / unmounted | Yes | Yes |
| Sees another user account log in | Yes | Yes |
| **Sees failed unlock attempts** | **No** | **Yes** |
| **Sees permission prompts (camera, mic, screen)** | **No** | **Yes** |
| **Sees screen sharing / remote login** | **No** | **Yes** |
| **Sees USB device identity** | **No** | **Yes** |
| Knows *which app* changed a file | No | No — needs an Apple approval neither edition has today |

The honest one-line framing:

> **App Store edition answers "was someone here, and what did they touch?"
> Direct download edition also answers "did someone try to get in?"**

Both are real products. The App Store edition is not a crippled demo — presence,
session, drive, and file activity is most of what the tagline promises. But the
most emotionally compelling row in the 2.0 mockup — *"Screen unlocked — Password,
2nd attempt"* — is only possible in the direct download edition.

### The flow, edition by edition

**App Store journey.** The user finds MythLog in the App Store, installs it in
one click, opens it. The app explains it needs a background recorder to keep
working after the window closes, and asks permission to install one. macOS shows
its own Background Items approval. From then on the timeline fills. If the user
wants folders watched, they grant them explicitly through a standard file
picker — the sandbox means the app can only see folders the user hands it. Every
update arrives automatically through the App Store. This user never sees a
security warning, never drags anything to Applications, and never thinks about
signing.

**Direct download journey.** The user downloads a `.dmg`, opens it, drags the app
to Applications. Because it is signed and notarized, macOS opens it without a
scary warning, though first launch still asks for confirmation. From here the
recorder install is identical. The difference appears in what starts showing up:
failed unlock attempts, permission prompts, remote-login events. Folder watching
does not require per-folder grants. Updates are manual — the app has to tell the
user when a new version exists.

### What design must resolve

1. **Does a user know which edition they have, and does it matter?** If the two
   look identical until an event type silently never appears, that is a trap.
2. **How does a missing capability read?** A signal the edition cannot observe
   must not look like a quiet night. The app already has a principle here —
   every capability the sandbox forbids fails *loudly and attributably*, never
   silently — and the interface should extend it. Should unavailable sources
   appear as dimmed filter categories? A one-time explanation? A line in the
   event list? Choose, and make it consistent.
3. **How is the difference explained without making the App Store edition feel
   broken?** This is a tone problem more than a layout one.
4. **A compliance caution.** Apple restricts apps from steering users toward
   alternative distribution channels. Neutrally describing what an edition can
   and cannot see is defensible; an in-app pitch to go download the other version
   is likely not. Design the honesty, not the upsell — and flag anything that
   feels close to the line so it can be checked before submission.

---

## 4. Flows and states to design

### 4.1 First run
Nothing recorded yet, recorder not installed. The single most important screen
for conversion, and currently the weakest. It should explain what will be
recorded and what never will be — no keystrokes, no screen contents, no
microphone — because the app is asking to watch, and trust is earned here or
not at all.

### 4.2 Installing the recorder
Includes a macOS-owned approval step the app cannot style or control. Design for
the possibility that the user dismisses it, approves it late, or approves it
in System Settings minutes later. **A known bug worth designing away:** the app
previously kept prompting "install the recorder" after a successful install.
Whatever replaces it must make "installed and running" unmistakable.

### 4.3 The glance
Opened out of idle curiosity. Answer "is it working, and was anything unusual?"
in under two seconds, without reading a table.

### 4.4 The investigation
Something felt wrong. Find the moment. Filter, scan, search, select, inspect,
and understand a single event in full — including where it sits in the chain.

### 4.5 Integrity states — the missing screens
The 2.0 mockup shows only success (`Ledger verified`). These are the states the
product exists for and none are designed:

- **Verification fails at record #3,201.** What is trustworthy, what is not, and
  what does the user do now? This is the most important screen in the app.
- **Truncation** — the local history is shorter than the iCloud anchor says it
  should be. Someone removed entries.
- **A coverage gap** — the recorder was stopped for six hours. Nothing was
  recorded, which is *not* the same as nothing happening. A gap must never look
  like a peaceful evening.
- **Anchoring unavailable** — iCloud signed out, so tamper-evidence is weaker
  than usual. Inform without alarming.

### 4.6 Proof export
The user needs to give someone else — a partner, an employer, a lawyer — evidence
they can check without MythLog installed.

### 4.7 Live arrival
An event lands while the user is scrolled into history. Something has to give;
decide what.

---

## 5. Hard constraints

**Density is the defining constraint.** The mockup shows fourteen rows; its own
header reports 5,362 records. A normal machine produces thousands of events a
day, and a single build or dependency install can emit **300 file events in ten
seconds**. Two years of recording is roughly two million records. Any layout must
be judged at those numbers, not at fourteen. The current double-sided timeline —
events above and below a centre axis — reads beautifully when sparse and is
believed to collapse under real density; confirming or replacing it is part of
this work.

**The event list must survive large text.** The app already supports Dynamic
Type, and a fixed four-column table is the hardest possible thing to keep
working at the largest accessibility sizes, because columns cannot reflow the way
prose can. If the answer is that rows become a composed, reflowing layout rather
than a strict grid, say so — that is a legitimate outcome.

**Accessibility is already shipped and must not regress.** VoiceOver reads the
timeline in chronological order and skips decoration; every control is reachable
by keyboard; severity never depends on colour alone; Reduce Motion is respected.
A new table, a new inspector, and a new timeline each need this designed in, not
retrofitted.

**Light mode exists.** The mockup is dark-only.

**Localisation.** German and French run 30–40% longer than English. Labels that
fit in the mockup will not fit everywhere.

**New event types will keep arriving.** Drive mounts, user switching, external
displays, and more are all realistic near-term additions. Any element that needs
hand-editing each time a source is added — a fixed legend, a hardcoded colour
list, a bespoke row layout per type — is a design defect.

**Some data does not exist and cannot be invented.** The mockup implies per-event
user attribution and knowledge of which process touched a file. Neither is
available today; the second requires an Apple approval the project does not have.
Design around what is real, or clearly mark a proposal as depending on data that
must be added first.

---

## 6. Deliverables

- The full set of screens for flows 4.1–4.7, including empty, sparse, dense,
  loading, and failure states for each.
- Both editions wherever they differ, plus the treatment for an unavailable
  capability.
- Light and dark.
- Default and largest accessibility text size, for at least the event list and
  the inspector — the two hardest.
- A component inventory: row, event type indicator, severity treatment, filter
  pill, timeline element, inspector section, integrity banner — each defined so a
  new event type can be added without new design.
- A short rationale for the six open questions below.

## 7. Open questions for design to answer

1. Is the timeline the hero, with the list supporting it — or has the list become
   the product, with the timeline reduced to a scrubber? Both are defensible;
   pick one deliberately.
2. Does the double-sided timeline survive real density? If not, what replaces it
   — a density histogram, one lane per category, a heatmap strip?
3. Fixed columns, or reflowing rows?
4. Where does cryptographic provenance live — always visible per row, in the
   inspector only, or in a dedicated verification view? How much proof does
   someone need to *feel* the record is trustworthy, versus how much is noise?
5. How is a coverage gap drawn so it can never be mistaken for a quiet period?
6. Do the two editions present as one product with visible gaps, or as two
   clearly different things?

## 8. Explicitly out of scope

No account, login, or onboarding sequence beyond first-run explanation and
recorder install. No social, sharing, or collaboration features. No cloud
dashboard. No keystroke, screen-content, camera, or microphone capture — these
are excluded by product principle, not merely unimplemented, and the design
should be comfortable saying so out loud.
