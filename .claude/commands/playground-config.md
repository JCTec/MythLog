---
description: MythLogPlayground — Phase D, write config and pick an anchor folder
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, WebFetch, WebSearch, TodoWrite
---

Make the anchor choice persist, and let a folder actually be chosen.

Today `AnchorSettingsPage` changes the choice **in memory only**. The README says
why: *"it does not write `config.json`, because the recorder owns that file."*
That sentence is the whole phase.

## Read first

- `MythLogPlayground/README.md` — Known gaps
- `MythLogPlayground/docs/ANCHOR_DESTINATIONS.md` — phases 1–2 are done
- `Sources/Config/` — the schema, validation, and the lossless round-trip

## Constraints

**Blast radius.** `MythLogPlayground/` writable, everything else read-only.

```sh
git status --porcelain | grep -v '^.. MythLogPlayground/' | grep -v '^.. .claude/' && echo VIOLATION || echo clean
```

Branch `playground/config`, never push. Gates green before every commit:
`./Scripts/check-layering.sh --self-test` and the test suite. Conventions as in
the README; Swift 6 strict concurrency, zero warnings.

---

## The hard part — decide it, do not drift into it

`config.json` has two potential writers: this app, and the recorder that owns the
install. Get this wrong and a user's config silently reverts, or the recorder
reads a half-written file.

**Research this before choosing** (`developer.apple.com`, `swift.org`), and
record the decision and its reasoning in `docs/CONFIG_OWNERSHIP.md`. Candidate
shapes:

- **Viewer writes atomically; recorder reloads on change.** Simple, but requires
  the recorder to watch and re-read — which does not exist yet.
- **Viewer writes a small pending-change file; recorder merges and deletes it.**
  Survives both processes running, at the cost of a second file and a merge rule.
- **Viewer writes only when no recorder is running.** Honest and trivial, but
  useless exactly when someone is changing a setting.
- **Viewer asks the recorder over IPC.** Correct long-term, far too large now.
  **Do not build IPC in this phase.**

Whatever you choose, the app must **say** which one it is. A setting that might
not have taken effect is worse than a setting that refuses to change.

## What to build

**1. Writing.** Atomic (write-temp-then-rename), mode `0600`, validated *before*
the write — an invalid config could stop a recorder from starting, which for this
product means silently not recording.

**Preserve every key you do not understand.** Wave 3 built a lossless round-trip
for exactly this reason: the schema carries `session`, `filesystem`,
`unifiedLog`, `notifications`, `telegram`, `remoteCheckpoint`, and `rules`, and
this app interprets none of them. A write that drops them is data loss in a
config the recorder depends on. Add a test that proves an unknown key survives a
read-modify-write.

**2. The folder picker.** `NSOpenPanel`, directories only, wired to
`AnchorChoice.chosenFolder`. Show the resolved path, and re-state the visibility
warning at the moment of choosing — *"if this folder syncs, it appears on every
device signed into that account"* — because that is when it matters, not on a
page someone read earlier.

**3. Write down the sandbox problem rather than solving it.**

This app is unsandboxed, so a picked folder just works. **In the sandboxed App
Store build it will not**, and not for the obvious reason: a security-scoped
bookmark held by the *viewer* grants access to the *viewer*. The recorder is a
separate process and gets nothing from it. Anchoring to a user-chosen folder from
a sandboxed build needs the bookmark handed to the recorder through the shared
App Group container, and the recorder resolving it itself.

Do not build that here. Record it in `docs/CONFIG_OWNERSHIP.md` as a known
blocker for the App Store edition, because it decides whether "a folder you
choose" can ship there at all.

**4. Reflect reality in the UI.** If a change was written, say so and say when.
If it was queued for a running recorder, say that. If it could not be written,
say why — never let it look saved when it was not.

## Definition of done

- Choosing a destination or folder persists across a relaunch.
- A config containing unknown sections survives read-modify-write untouched,
  proven by a test.
- Invalid configurations are refused before anything is written, with the reason
  shown.
- `docs/CONFIG_OWNERSHIP.md` records the ownership decision, its reasoning, and
  the sandboxed-bookmark blocker.
- Gates green, `git status` clean outside `MythLogPlayground/`, README "Known
  gaps" updated.

Use TodoWrite to track it.
