# Filter ideas — from the adversary's side

Generate candidate filtering behaviours by working out **how filtering could be
turned against the person the app is for**, and then designing the mechanisms
that make each attack fail. This is a red-team pass that produces requirements,
not a list of features.

## Blindfold — do not read these

Reading any of the following invalidates this run:

- `MythLogPlayground/README.md`
- `.claude/commands/fine-grained-filters.md`
- Any file whose name contains `Filter`
- `MythLogPlayground/docs/`, `docs/DESIGN_BRIEF_2.0.md`
- Any existing file under `docs/filter-ideas/`

You may read `MythLogPlayground/Sources/Model/TimelineEvent.swift`,
`EventKind.swift`, and `MythLogPlayground/Sources/Ledger/` — the ledger folder
matters here, because what the chain does and does not guarantee bounds every
attack.

## The setting

MythLog records events on a Mac and writes them to a tamper-evident append-only
log. Its users include people who share a home or an office with someone they
have reason to be careful of, and who may not be able to keep that person away
from the machine. The adversary may have physical access to the Mac, may know
the user's password, and may have used the app themselves.

The chain protects the *records*. It does not protect the *view*. That gap is
what this exercise is about.

## Method

Work through these deliberately. For each, write the attack concretely — as
something a person does, in order — then the defence.

1. **The forgotten filter.** The adversary narrows the view to something
   harmless and leaves it that way. Weeks later the user opens the app, sees a
   quiet week, and is reassured. What in the interface has to be true for this
   to fail? Consider: does a filter survive a relaunch at all, and what is
   gained and lost either way?
2. **The plausible filter.** As above, but the filter looks like something the
   user themselves would have set — reasonable, tidy, defensible if challenged.
   Harder than the first. What distinguishes a filter you set from one you did
   not?
3. **The filter that hides a gap.** The adversary's real goal is that a period
   of non-recording — when the app was not running — reads as a quiet period.
   Enumerate every mechanism by which a narrowing could cause that, including
   ones that are not filters in name: zoom level, time range, sort order,
   collapsed groups, a scrolled-away banner, a preset.
4. **The filter that hides a verification failure.** Same exercise for the
   integrity verdict.
5. **The exhausting filter.** No hiding at all — the adversary makes the
   relevant evidence tedious to reach, betting the user gives up. What does a
   filter model owe someone who is frightened and tired?
6. **The misleading count.** A number that is true but which the user will read
   as answering a different question than it does.
7. **The false negative the user reports onward.** The user tells a lawyer, a
   police officer, or a family member "there is nothing there" while a filter
   was on. What does the app owe someone who is about to make a claim based on
   what they see — on screen, and in anything exported?
8. **The adversary who reads the record.** Filtering is also a way to comb
   someone else's log efficiently. Which filter designs make surveillance of the
   user *easier*, and is there anything the interface can do about that, or is
   it out of scope? Say which, honestly.

## For each attack, produce

- The attack, in steps.
- Why the current-generation obvious defence is insufficient, if it is.
- The defence, stated as a **requirement** — a sentence of the form "the
  interface must…" or "no filter may…" that a later design can be checked
  against.
- How you would test the requirement, concretely enough that a person sitting in
  front of the app could carry it out.

## Then

- **Consolidate the requirements** into a numbered list with no duplicates. This
  list is the actual deliverable; the attacks are its justification.
- **Name the conflicts.** Some defences will fight usability or fight each
  other — persistent filters versus forgotten filters, for instance. Present
  each conflict as a choice with consequences on both sides. Do not resolve it.
- **State what is out of scope.** An adversary with root, or with the user's
  cooperation, or with the machine in another country. Being clear about the
  boundary is part of the deliverable.

## Output

Write `docs/filter-ideas/adversarial.md` with the sections above.

Do not implement anything. One markdown file, no code.
