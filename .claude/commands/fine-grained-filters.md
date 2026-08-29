---
description: MythLogPlayground — filtering beyond six on/off chips
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, TodoWrite
---

Filtering today is six category chips and a free-text box. That is not enough to
investigate 364 file events, and it will be less enough after Wave 5 adds drives,
displays, and user switching.

Do this before Wave 5: the model should be right before more is poured into it.

## The principle that makes this different

In most apps a forgotten filter is an annoyance. Here it is the **same failure as
a hidden coverage gap** — it makes absence look like safety. Someone opens this
app because they are worried, sees a quiet night, and is reassured. If that quiet
was a filter they set last Tuesday, the app has lied to them about the one thing
it exists to be honest about.

So: **it must be impossible to forget that you are looking at a subset.** Not a
subtle highlight — the filtered state is loud, permanent while active, and says
what is being hidden and how much. Design that first and let the rest follow.

Two rules that are not negotiable:

- **No filter may hide a coverage gap**, at any level, ever. Already true; keep
  it true and keep the test that proves it.
- **No filter may hide a verification failure or an untrusted record.** Same
  reasoning. Filtering is about *what happened*, never about *whether the record
  can be believed*.

## Constraints

`MythLogPlayground/` writable, everything else read-only:

```sh
git status --porcelain | grep -v '^.. MythLogPlayground/' | grep -v '^.. .claude/' && echo VIOLATION || echo clean
```

Branch `playground/filters`, never push. Gates green before each commit:
`./Scripts/check-layering.sh --self-test` and the suite. Conventions per the
README; Swift 6 strict concurrency, zero warnings.

## What exists

`MainPage.Model` holds `enabledKinds: Set<EventKind>` and `query: String`.
`TimelineDerivation` applies both. `AlarmEvent` carries `severity`, `source`, and
a `metadata` dictionary that nothing filters on.

Read the shipping app's `Sources/MythLogAppSupport/Filters/` for its filter
templates and state pills — that model is worth learning from, not copying.

## The worked example — start here

> *"I want to see only screen unlocks on my timeline."*

Today that is impossible. `Session` is one chip covering lock **and** unlock,
and there is no way to separate them — even though the data already does:
`payloadKind` is `session.unlock` or `session.lock`.

So the primary missing dimension is **the event type**, one level below category.
That is a two-level taxonomy already present in every ledger:

```
Session   → session.lock, session.unlock, session.userSwitch
Power     → power.sleep, power.wake, power.display
Apps      → app.launched, app.activated, app.terminated
Files     → file.modify
Drives    → drive.mount, drive.unmount
Health    → health.heartbeat, health.start, health.stop
```

**Derive this from the events in the window, never hardcode it.** Wave 5 adds
kinds that do not exist yet, and a hardcoded list would be wrong the day it
lands.

Build this first: it is the smallest change that makes the example work, and
everything else composes with it.

**Then make it a preset.** "Every time this Mac was unlocked" is not an obscure
query — for someone who came here worried, it is *the* question. It should be one
click, not an expression somebody has to assemble. A small set of named presets
grounded in what people actually ask:

- **Unlocks only** — every time someone got in.
- **Physical access** — unlock, wake, lid, drive mounted, user switched. Anyone
  who was at the machine.
- **Warnings and above** — severity, once that exists.

Presets are a starting point the user can then adjust, not a mode they are stuck
in. Show what a preset expanded to, so it teaches the filter model rather than
hiding it.

Note the pleasant consequence: filtering to unlocks drops the population far
below the Events-level threshold, so the timeline resolves to individual nodes —
a sparse row of marks, which is exactly the right shape for that question.

## Dimensions to add

**Severity.** `AlarmSeverity` exists — debug, info, notice, warning, critical —
and is not filterable at all. "Warning and above" is *the* investigation query
and it is currently impossible. This is the highest-value single addition.

**Source.** `loginwindow`, `fseventsd`, `com.apple.Safari`. Already on every
event.

**Exclusion, not only inclusion.** The 312-event build storm drowns a day.
Excluding `~/Projects/…/.build/` is more useful than including anything, and
subtractive filters are the ones investigators actually reach for.

**Within a category.** Files by path prefix; apps by bundle identifier; drives by
volume name. Derive the offered values from what is actually in the window — do
not hardcode a list that goes stale the moment a new source lands.

## Interaction

Take a position and justify it. A starting proposal, not a mandate:

- A chip stays a chip: click toggles the category, as now.
- A disclosure on the chip opens detail for that category — values present in the
  current window, each includable or excludable.
- The existing search box gains structured tokens for people who want them
  (`severity:>=warning`, `-path:.build`), while remaining a plain substring
  search for people who do not. **A query language must never be the only way to
  express a filter** — this app's audience is explicitly not all technical.

## The counts problem

Chips currently show window-scoped counts. With sub-filters active, "Files 364"
becomes ambiguous: is that all file events, or the ones passing the sub-filter?

Decide and make it unambiguous in the UI. Whatever you choose, the number of
events **hidden** by filtering must be visible somewhere permanent — that is the
mechanism that stops a filter from quietly becoming a lie.

## Saved filters

Named sets — "Overnight", "Security only", "Ignore builds". Persisted.

If a saved filter is active on launch, say so prominently. A filter restored from
last week that the user does not remember setting is exactly the failure this
whole document is about.

## Performance

Filtering runs inside `TimelineDerivation` on every window change, and window
changes arrive several times a second while zooming or panning. String matching
across 250,000 events per frame will not hold.

Measure first on a 100k-record ledger, then decide: precomputed indexes for the
dimensions with few distinct values (severity, source, kind), and matching only
over the window's events for the expensive ones. Keep the cancel-before-restart
behaviour — it is what makes zoom survivable.

## Definition of done

- **"Show me only screen unlocks" takes one click**, and the timeline resolves to
  individual unlock nodes.
- Event-type filtering works for every category, with the types derived from the
  window rather than hardcoded.
- Severity, source, and exclusion filters work, and compose.
- Per-category detail derives its values from the current window.
- Active filtering is impossible to miss, and the hidden count is visible.
- Coverage gaps and verification failures survive every filter, proven by tests.
- Saved filters persist, and an active one announces itself on launch.
- No main-thread stall on 100k records while zooming with filters active.
- Gates green, `git status` clean outside `MythLogPlayground/`.

Previews: nothing filtered; heavy filtering with a large hidden count; a filter
matching nothing; a gap visible while everything else is filtered out.
