# Anchor destinations

Where the chain head is kept, and why that choice is the security feature rather
than a preference.

Nothing here is built yet. It is written down so it can be added a phase at a
time, in an order where each step is useful on its own.

## What an anchor is

Three fields: a record count, the hash of the latest record, and a timestamp.
**No event content.** That is what makes this question tractable — the anchor can
go almost anywhere, because putting it somewhere does not put anyone's history
there.

## Why it needs to leave the machine

Trust stacks in three levels, and each one buys something the previous cannot:

| You hold | You can tell |
| --- | --- |
| Ledger | Nothing. You can read the history; you cannot check it. |
| Ledger + key | That no record was altered or reordered. |
| Ledger + key + anchor | That no record was **removed from the end**. |

The middle level is the trap. Delete the last fifty records and the remaining
chain still verifies perfectly — the evidence of the deletion was the part that
got deleted. Only an outside copy of "there were N records at time T" catches it.

**So an anchor on the same disk, under the same person's control, is worth
nothing.** Whoever truncated the ledger rewrites the anchor in the same motion.
The entire value comes from the anchor living somewhere the adversary cannot
reach.

That reframes the setting. It is not "where do you want to keep a file". It is
**"who are you keeping this away from?"** — and only the user knows the answer.

## What makes a destination good

Four properties, roughly in order of importance:

1. **Outside the adversary's control.** The one that actually matters.
2. **Timestamped by a third party.** Independent corroboration of *when* beats a
   self-reported time.
3. **Deletion is visible.** Append-only, or at least a hole you would notice.
4. **No new infrastructure.** Something the person already has, or the feature
   goes unused.

## The options

### iCloud Drive — shipped

Present today, on by default. Off the machine, syncs, needs nothing new.

Weak on (1) for the specific case that matters most: someone with access to the
Mac often has access to the same Apple account. Fine for the honest-mistake and
opportunistic-snooping cases; thin against a partner who knows the password.

### A folder you choose — shipped

`hashAnchor.destination = directory`. Already supports a USB key, an external
volume, a third-party sync folder.

**Underrated.** A USB stick kept in a bag scores well on (1) and (3), and the
mechanism already exists — what is missing is a UI that explains *why* you would
want this.

### Telegram — plumbing exists

Bot token, approved chat IDs, and `network.client` are all shipped for
notifications. Posting `5,362 · a1b2c3… · 14:00` to your own chat is an anchor.

Good on (2): Telegram stamps the message with its own server time, which is
stronger corroboration than the app's own clock. Good on (4): the account already
exists.

Three caveats, and the last is serious:

- Cloud chats are **not** end-to-end encrypted; only Secret Chats are, and bots
  cannot use them. Anchors carry no event content, but the message stream leaks
  metadata: that MythLog is running, roughly how many events exist, and when the
  machine was active. "Active at 03:00" is itself information.
- Messages can be deleted, so (3) holds only if a missing message is noticed.
- **The adversary may have the phone.** In a domestic situation the person being
  documented often has access to the same Telegram account. This is
  disqualifying as a *default* for that audience, though fine as an option
  someone chooses knowingly.

### A git remote

Commit `anchor-history.jsonl` to GitHub, Codeberg, or any host.

Strong on all four. Commits are themselves hash-chained, so this anchors one
chain inside another; hosts timestamp commits independently; a force-push that
rewrites history is visible in the reflog and in every clone; and it is free.

The cost is comprehension — "put your anchors in a git repo" is not a sentence
most of this audience will act on. Worth building, worth hiding behind an
"Advanced" disclosure.

### A remote server

`RemoteCheckpoint` already exists in the shipping app as outbox-only scaffolding.

Strongest on (1) and (3) if the server is genuinely append-only and not under the
same control. Fails (4) hard: almost nobody in this audience runs a server.

### OpenTimestamps

Anchors a hash into the Bitcoin blockchain. Free, no account, and about as strong
as "this existed before time T" gets — the right answer if a record may one day
have to convince someone hostile.

Fails (4) on comprehension, not on effort — the mechanics are simple, but
explaining them is not.

### A second device

Anchor to a phone or iPad through a shared iCloud container or a Shortcuts
webhook. Scores well on (1) when the second device is not shared, and on (4)
since most people have one.

Least designed of the options here; needs thought before it is scheduled.

## Phases

Ordered so each phase is useful alone and none blocks the next.

### Phase 1 — Make the existing choice legible

No new destinations. Change how the existing two are presented: from a path
setting to a question about *who you are keeping this away from*, with plain
descriptions of what iCloud and a chosen folder each protect against.

Cheapest phase, and probably the largest real-world gain — the USB-key case
already works and nobody knows it.

### Phase 2 — `AnchorDestination` as a protocol

Refactor the two existing destinations behind one small interface: write an
anchor, read the latest, list history. No behaviour change, no new destination.

Everything after this becomes additive.

### Phase 3 — Multiple simultaneous anchors

Let more than one destination be active. Two anchors in different trust domains
is a materially stronger claim than one, and disagreement *between* them is
itself a signal worth surfacing.

Needs a UI answer for "iCloud says 5,410, the USB key says 5,362" — which is not
a failure, it is one of them being stale, and the difference matters.

### Phase 4 — Telegram

Reuse the existing notifier transport. Ship with the phone-access caveat stated
plainly in the UI, not buried in documentation.

### Phase 5 — Git remote

Behind an advanced disclosure. Largest security gain per unit of work for users
who understand it.

### Phase 6 — OpenTimestamps, remote server, second device

Ordered by demand. None is obviously next; revisit once real users have said
what they actually need.

## Open questions

1. **Should anchoring ever be silent?** Today it is on by default and quiet. For
   someone in a hostile situation, an anchor written to a synced folder could be
   *visible to the adversary* — the folder appears on their devices too. That
   deserves a warning the current design does not give.
2. **What happens when destinations disagree?** Stale versus truncated look
   identical at a glance and mean opposite things.
3. **Does the App Store edition ship network anchoring at all?** Telegram and git
   both mean outbound network from a build whose store copy says everything stays
   on your Mac. Either the copy changes or the feature is Developer-ID only.
4. **Can an anchor be verified without MythLog?** A proof bundle someone can
   check with `shasum` and a text editor is worth more than one that needs the
   app that produced it.
