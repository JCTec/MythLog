# Filter ideas — derived from prior art

Generate candidate ways of narrowing a MythLog timeline by studying **how other
serious tools let people narrow a long sequence of timestamped things**. Not to
copy interfaces, but to find the models that were arrived at independently by
several fields — those are the ones that reflect something about the problem
rather than about a company's taste.

## Blindfold — do not read these

Reading any of the following invalidates this run:

- `MythLogPlayground/README.md`
- `.claude/commands/fine-grained-filters.md`
- Any file whose name contains `Filter`
- `MythLogPlayground/docs/`, `docs/DESIGN_BRIEF_2.0.md`
- Any existing file under `docs/filter-ideas/`

You may read `MythLogPlayground/Sources/Model/TimelineEvent.swift` and
`EventKind.swift` to know what a record contains, and nothing else in the
source.

## Sources

Primary documentation only — the vendor's or project's own reference, not blog
posts, not tutorials, not aggregator summaries. Cite every claim with a URL.
Where a tool is not documented publicly in enough depth, say so and drop it
rather than reconstructing it from memory.

Study at least eight, from at least five different fields. Suggested starting
set, and you should add to it:

- **System log viewers** — Console.app and the `log` command's predicate
  filtering; `journalctl`'s field matching.
- **Packet analysis** — Wireshark's display-filter language, and specifically
  the relationship between its filter expressions and its colouring rules.
- **Observability** — how a trace or metrics explorer distinguishes filtering
  from grouping from aggregating.
- **Photo libraries** — faceted browsing over a corpus organised primarily by
  time, where the user's mental model is "the day I was at the beach".
- **Digital audio workstations and video editors** — narrowing a timeline where
  the timeline itself is the primary object and cannot be reordered.
- **Email** — search folders, saved searches, and the failure mode of a rule
  that silently files things away.
- **Version control** — `git log`'s path, author, date and content filters, and
  the fact that its filters compose.
- **Aviation or medical event recorders** — where the record is evidentiary and
  filtering has consequences.

## What to extract from each

1. **The model, not the widget.** What is the unit of filtering — a predicate, a
   facet, a saved query, a scope, a lens? Where does the tool draw the line
   between filtering (hiding) and highlighting (not hiding)?
2. **How it composes.** What happens with two constraints — AND, OR, or a
   sequence of narrowings? How is that shown?
3. **How it tells you it is on.** Every one of these tools has faced the problem
   of a user who forgot they were filtered. Record what each does, precisely.
   This is the single most transferable thing in the study.
4. **Where it distinguishes "no results" from "nothing there".** Note which
   tools get this right and how, and which do not.
5. **What it deliberately refuses to let you filter**, if anything, and why.

## Convergence analysis

After the survey, and only then:

- Which models appear in **four or more** fields? Those are load-bearing.
- Which appear in exactly one? Those are field-specific and probably do not
  transfer — say why.
- Where do two fields solve the same problem **incompatibly**? Those are real
  design forks and should be presented as such, with the trade-off named rather
  than resolved.

## The application whose problem this is

A tamper-evident record of what happened on a Mac. Its defining property is that
periods where nothing was recorded are visible and are *not* the same as periods
where nothing happened. Judge every borrowed model against that: highlighting
tools transfer well to it; tools that hide rows transfer badly and need a story.

## Output

Write `docs/filter-ideas/from-prior-art.md`:

- **Survey** — one section per tool, with citations, covering points 1–5.
- **Convergence table** — model × field, showing what appears where.
- **Load-bearing models** — the four-or-more group, with what each would look
  like here.
- **Design forks** — the incompatible pairs, stated as choices.
- **Does not transfer** — with reasons.
- **Ranked shortlist** — at most six.

Do not implement anything. One markdown file, no code.
