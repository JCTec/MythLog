# Filter ideas — synthesis

Run **after** all four generators have produced their files. Compare four
independently-formed views, keep what survives, and produce the brief for a
design session.

Requires all of:

- `docs/filter-ideas/from-data.md`
- `docs/filter-ideas/from-situations.md`
- `docs/filter-ideas/from-prior-art.md`
- `docs/filter-ideas/adversarial.md`

If any is missing, stop and say which. Synthesising three of four silently
defeats the point of having run them blind.

## The rule that makes this worth doing

The four generators were blinded from each other precisely so that agreement
between them means something. Treat agreement as evidence and disagreement as
the interesting part — not as noise to be averaged away.

## Method

1. **Build the concordance.** Every candidate from every file, in one table,
   marked with which generators produced it. Match on *substance*, not on name —
   two generators will have named the same idea differently, and one of your
   main jobs is noticing that. When you merge two entries, say so and show both
   original names.
2. **Sort into four groups.**
   - **Converged** — three or four generators, independently. Strong.
   - **Two-source** — worth keeping, but say which two: data + situations is a
     different kind of support than prior-art + situations, and the second is
     weaker because both are about what people expect rather than what is true.
   - **Single-source with a reason** — one generator, but its argument stands on
     its own. Quote the argument.
   - **Single-source without one** — cut, with a line saying why.
3. **Cross-examine.** For every candidate in the first two groups:
   - Does the *data* generator say the underlying distinction actually exists?
     An idea the situations generator loves and the data cannot support is a
     dead end and must be marked as one.
   - Does the *adversarial* generator's requirement list forbid it, or constrain
     its form? A candidate that violates a requirement is either dropped or
     redesigned until it does not — show the redesign.
   - Does the *prior-art* generator report a field that tried it and moved away
     from it?
4. **Surface the disagreements.** Where two generators reached incompatible
   conclusions, write the disagreement up properly: what each concluded, the
   reasoning behind each, and what evidence would settle it. Do not pick a
   winner. These are the items the design session exists to decide.
5. **Separate structure from queries.** Some candidates are dimensions the
   interface should be built around; others are one-off questions that belong to
   search or to a saved query. Getting this wrong in either direction is
   expensive, so state the test you used to sort them.
6. **Write the invariants.** Take the adversarial requirement list, add anything
   the other three produced that is genuinely non-negotiable, and reduce it to
   the shortest list that still covers everything. Aim for under ten. Each must
   be checkable by a person sitting in front of the app.

## Output

Write `docs/filter-ideas/SYNTHESIS.md`:

- **Concordance table** — candidate × generator, with merge notes.
- **Converged**, with the independent arguments for each stated separately.
- **Two-source**, with the pairing and what that pairing does and does not show.
- **Kept on a single strong argument**, quoted.
- **Cut**, one line each.
- **Dead ends** — wanted but not supported by the data, and what to say instead.
- **Open disagreements** — for the session. What each side holds, and what would
  settle it.
- **Invariants** — the numbered non-negotiable list.
- **Session agenda** — the four or five decisions that actually need a human,
  ordered so that the earlier ones unblock the later ones.

Nothing in this file may be presented as settled that a generator disputed. If
you find yourself smoothing over a conflict to make the document read better,
that is the exact failure this command exists to prevent.

Do not implement anything. One markdown file, no code.
