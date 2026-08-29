# Filter ideas — derived from the situations people are in

Generate candidate ways of narrowing a MythLog timeline, derived **only from the
situations that bring someone to open this app**. Start from the person and the
trouble they are in. Arrive at the query last.

## Blindfold — do not read these

You are one of several independent generators, and your output is worth having
only if it was formed without seeing the others or the existing interface.
Reading any of the following invalidates this run:

- `MythLogPlayground/README.md`
- `.claude/commands/fine-grained-filters.md`
- Any file whose name contains `Filter`
- `MythLogPlayground/docs/`, `docs/DESIGN_BRIEF_2.0.md`
- Any existing file under `docs/filter-ideas/`
- **Any source file at all.** You are not designing against an implementation.
  If a situation implies a query the data cannot answer, that is a finding, not
  a mistake — write it down.

You may read `docs/TECHNICAL_CAPABILITIES.md` **only at the very end**, to mark
which situations are answerable, and only after the situations are written.

## What MythLog is, in one paragraph — this is all the context you get

A macOS application that records events about the machine it runs on — the
screen locking and unlocking, the system sleeping and waking, applications
starting and stopping, volumes being mounted, files in watched folders changing
— and writes them to a tamper-evident append-only log. It records nothing about
content: no keystrokes, no screen contents, no network traffic. A user opens it
to find out what happened on their computer while they were not looking at it.

## Method

1. **Write twelve situations**, in prose, before naming a single filter. Each is
   a specific person with a specific worry on a specific day. Push for range:
   - Someone who lives with the person they are worried about.
   - Someone whose worry turns out to be unfounded, and needs to be able to
     conclude that with confidence.
   - Someone building a record for a third party — a lawyer, an employer, an
     insurer — where "I could not find anything" has a cost.
   - Someone who is technical and someone who is not.
   - Someone checking a machine that is not theirs, with permission.
   - Someone who has been using it for eighteen months and opens it out of
     habit.
   - Someone whose machine was physically out of their possession for a week.
   - Someone who is wrong about what the app can see.
   At least two situations should be mundane rather than frightening. An app
   that only serves crises is not one people keep installed.
2. **For each, write the sentence the person would say aloud**, in their words,
   not in the app's. "Was anyone in here on Thursday night." "Did it actually
   stay off the whole time I was away."
3. **Translate each sentence into the narrowing it requires.** Be precise about
   what must be *kept* as well as what is dropped — several of these are about
   confirming an absence, and an absence is only meaningful if you know the
   record was complete over that period.
4. **Cluster the narrowings.** Which recur across unrelated situations? Those
   are dimensions. Which appear once? Those are one-off queries and probably
   belong to search rather than to structure.
5. **Note where the sentence and the narrowing come apart.** "Was anyone in
   here" is not a filter over event types — it is a question about physical
   presence that several unrelated event types bear on. Cases like this are the
   most valuable thing you will produce; look for them deliberately.

## The trap to avoid

Filters that answer questions nobody asks, expressed in vocabulary only the
implementation uses. If a candidate can only be described using a word that
appears in the source code and nowhere in step 2, mark it as such.

## The constraint that is not up for debate

Several of these situations turn on confirming that *nothing* happened. That
only works if the person can tell the difference between "nothing happened" and
"nothing was recorded". Every candidate must be checked against that: does it
risk making a period of non-recording look like a period of quiet?

## Output

Write `docs/filter-ideas/from-situations.md`:

- **The twelve situations**, in full prose. Do not compress them into a table —
  the detail is the substance.
- **Sentence → narrowing** for each.
- **Dimensions** that recurred, with the situations that produced them.
- **Questions that are not filters** — the ones from step 5, and what they would
  need instead.
- **Answerable / not answerable** — only now consult
  `docs/TECHNICAL_CAPABILITIES.md`, and mark each situation. For the
  unanswerable ones, say what the app should tell the person.
- **Ranked shortlist** — at most six, ordered by how many distinct situations
  each serves.

Do not implement anything. One markdown file, no code.
