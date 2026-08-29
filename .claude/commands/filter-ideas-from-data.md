# Filter ideas — derived from the data alone

Generate candidate ways of narrowing a MythLog timeline, derived **only from what
the recorded data can actually distinguish**. No user research, no prior art, no
opinions about what people want. Just: what distinctions exist in this ledger,
and which of them are worth exposing?

## Blindfold — do not read these

You are one of several independent generators. The value of your output is that
it was not influenced by the others, by the existing interface, or by anything
the author has already said. Reading any of the following invalidates this run:

- `MythLogPlayground/README.md`
- `.claude/commands/fine-grained-filters.md`
- Any file whose name contains `Filter` — `FilterBar`, `FilterChip`,
  `FilterFacetPanel`, `FilterStateBanner`, `EventFilter`, `FilterPreset`,
  `SavedFilter`, `FacetValueRow`, `SeverityFilterMenu`
- `MythLogPlayground/docs/`, `docs/DESIGN_BRIEF_2.0.md`
- Any existing file under `docs/filter-ideas/`

If you open one by accident, say so at the top of your output rather than
pretending it did not happen.

## What you may read

- `MythLogPlayground/Sources/Primitives/` — the record type
- `MythLogPlayground/Sources/Ledger/` — what is actually stored and in what form
- `MythLogPlayground/Sources/Model/TimelineEvent.swift`, `EventKind.swift`
- `MythLogPlayground/Sources/Mock/MockLedger.swift` — a representative shape
- `docs/TECHNICAL_CAPABILITIES.md` — what sources exist and could exist

## Method

1. **Inventory the fields.** For every field on a record, write down: its type,
   its cardinality in a realistic ledger, whether it is free text or drawn from
   a closed set, and whether it is present on every record or only some.
2. **Inventory the derivable values.** Things not stored but computable: time
   since the previous event of the same kind, burst membership, whether an event
   is the first of its kind ever seen, day of week, whether it falls inside or
   outside a period the ledger was quiet, position relative to a coverage gap,
   distance from a verification boundary.
3. **For each field and derived value, ask three questions:**
   - What is the *shape* of a filter over it? A toggle, a closed set, a
     substring, a numeric range, a relation to another record?
   - How many distinct values will a real ledger have after a year? A filter
     over something with 40,000 distinct values is a search box, not a chip, and
     the distinction matters more than which one you pick.
   - What does an event look like when this filter *excludes* it wrongly — what
     would a user conclude from its absence?
4. **Find the distinctions the data supports that nothing currently names.**
   These are the interesting ones. Look especially for fields where several
   meaningfully different things are currently collapsed into one label.
5. **Find the distinctions users will assume exist but the data cannot support.**
   Equally important. A filter that silently approximates is worse than no
   filter, in an application whose entire claim is an accurate record.

## Constraints that are not up for debate

- A coverage gap — a period where nothing was recorded — must remain visible
  under every possible filter. Absence of recording is not an event and cannot
  be filtered out.
- A verification failure must remain visible under every possible filter.
- If a filter can be left on and forgotten, that is a defect in the idea, not in
  the user. Note for each candidate how a user would notice it is active.

## Output

Write `docs/filter-ideas/from-data.md`:

- **Field inventory** — the table from step 1, including cardinality estimates
  and how you arrived at them.
- **Candidates** — one section each. Name, the distinction it exposes, the
  control shape the data implies, expected cardinality, and the failure mode
  when it is on and forgotten.
- **Distinctions the data supports that are currently unnamed.**
- **Distinctions users will expect that the data cannot honestly support**, and
  what the interface should say instead of approximating.
- **Ranked shortlist** — at most six, ordered by (distinguishing power ÷ cost of
  being wrong). Say why each of the rest did not make it.

Do not implement anything. This run produces one markdown file and no code.
