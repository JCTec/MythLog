# Who owns `config.json`

Two processes can plausibly write the installed configuration: this viewer, and
the recorder that owns the install. Getting it wrong means a user's setting
silently reverts, or the recorder reads a half-written file and fails to start —
which for this product means silently not recording.

This is the decision, the evidence behind it, and the one thing it cannot solve.

---

## The decision

**The viewer writes `config.json` directly and atomically. It is the only writer
at runtime. A recorder that is already running keeps its own in-memory copy until
it restarts, and the interface says so in as many words.**

Three outcomes, and the interface distinguishes all three:

| Outcome | What it means | What the user sees |
| --- | --- | --- |
| Written | Saved, and no recorder is running, so it is already in effect. | "Saved at 14:32." |
| Written, pending restart | Saved to disk. A recorder is running with the previous copy in memory. | "Saved at 14:32 — the recorder is running and still using the previous settings. It will pick this up when it next starts." |
| Refused | Validation failed or the write failed. **Nothing on disk changed.** | The reason, and what to fix. |

There is deliberately no fourth state in which the app is unsure.

---

## Why, and the evidence

The candidate shapes were: write atomically and have the recorder reload; write a
pending-change file the recorder merges; write only when no recorder is running;
or ask the recorder over IPC. Choosing between them turns on one question that
can be answered by reading the shipping app rather than by guessing.

### The recorder never writes the config

`Sources/MythLogAgent/main.swift:27` loads the config once at startup and hands
it to `MythLogAgentRuntime(config:)`, which holds it as a `let`
(`Sources/MythLogCore/MythLogAgentRuntime.swift:5,17-18`). Nothing in the runtime
re-reads it and nothing writes it back.

The writers of `config.json` in the shipping app are:

- `mythlogctl` — user-driven, in the foreground.
- `LaunchAgentInstallPreparation` — once, at install.
- **`Sources/MythLogAppSupport/State/TelegramSettingsStore.swift:86`** — the
  viewer app, doing exactly the read-modify-write this phase needs.

So there is no write/write race to design around. The only hazard is a *torn
read*: the recorder starting at the instant the viewer is part-way through a
write.

### Atomic replacement removes the torn read

`Data.WritingOptions.atomic` is documented as "An option to write data to an
auxiliary file first and then replace the original file with the auxiliary file
when the write completes."
(<https://developer.apple.com/documentation/foundation/nsdata/writingoptions/atomic>,
retrieved 2026-08-05.)

A reader therefore opens either the old file or the new one, never a partial one.
That is the whole of the concurrency problem here, and it is solved by a flag.

**Caveat, from observation rather than documentation:** an atomic write replaces
the file, so the *new* file does not inherit the original's permissions. The
shipping app compensates by `chmod`-ing afterwards — see
`Sources/MythLogCore/AgentStatus.swift:186-188`, which writes with `.atomic` and
then calls `chmod(…, S_IRUSR | S_IWUSR)`. The atomic-option documentation says
nothing about attribute preservation either way, so this port does the same thing
and sets `0600` after every write rather than assuming.

### Why not a pending-change file

Attractive on paper: the viewer writes `config.pending.json`, the recorder merges
and deletes it, and both can run at once.

Rejected because **the merging half does not exist and cannot be built here.**
The recorder lives in the shipping app, which is read-only for this work. Writing
a pending file that nothing consumes produces a file that looks like a mechanism
and is not one — the user is told their change is queued, and it is queued
forever. That is precisely the class of failure this product exists to prevent:
something that looks like it is working.

It stays the right answer *later*, and nothing here blocks it. Adding a fourth
outcome is additive.

### Why not "only write when no recorder is running"

Correct, trivial, and useless exactly when somebody is changing a setting —
which is while the recorder is running, because that is nearly always. Since the
recorder does not write the config, refusing buys nothing that atomic writing
does not already give.

The running recorder still matters, but as a *staleness* fact rather than a
*safety* one: it has an old copy in memory. That is what the second outcome says.

### Why not IPC

Correct long-term and far too large now. Explicitly out of scope for this phase.

### Why not `NSFileCoordinator`

Considered, and not used. It "coordinates the reading and writing of files and
directories among multiple processes and objects in the same process" and works
by notifying registered `NSFilePresenter` objects
(<https://developer.apple.com/documentation/foundation/nsfilecoordinator>,
retrieved 2026-08-05).

The value is in the presenter notifications — and the recorder registers none, so
coordination would be one-sided: this app would take a lock that the other party
does not participate in. Atomic replacement already gives the reader an
all-or-nothing view, which is the only guarantee actually needed. If the recorder
ever becomes a file presenter and reloads on change, coordination becomes worth
adding at the same time.

---

## Which install, and a bug found while wiring this up

The settings page writes the **installed** config — the one the recorder reads —
not the config beside whatever ledger happens to be open. Changing the anchor
destination for a copy of a ledger in `/tmp` would save successfully and mean
nothing.

Finding that install turned out to be wrong in a way worth recording.
`StorageLocations.resolve(environment:…)` answers *"where do my files go"*, which
is the right question for a process reading its own state and the wrong one for a
process looking for somebody else's install. This playground is unsandboxed, so
`resolve` returns `~/Library/Application Support/MythLog`. The recorder people
actually have is the App Store build, which **is** sandboxed and writes to the
App Group container. On the machine this was developed on,
`~/Library/Application Support/MythLog` does not exist and
`~/Library/Group Containers/S8662L649U.com.jctec.mythlog.shared/Application Support/MythLog`
has a live install in it — so auto-detect found nothing and the settings page
would have reported "no install on this Mac".

That is the 1.0.0 bug pointed the other way. Not a wrong path taken for a right
one, but a right path never looked at; the symptom is the same, a viewer
confidently reporting an absence that is not there.

`StorageLocations.installedCandidates(container:home:)` now returns every
plausible location, App Group container first because a sandboxed recorder is the
shipping configuration, and `firstInstalled(containing:)` picks the first that
actually holds the marker file. An unsandboxed process can resolve the App Group
container path without holding the entitlement, which is what makes this possible
at all. Both the ledger chooser and the settings page use it.

## Detecting a running recorder

From `runtime/status.json`, which the recorder writes and this app only reads. A
recorder counts as running when the status file exists, its `state` is `running`
or `starting`, and its `generatedAt` is recent relative to the configured
heartbeat interval.

Staleness is judged against the heartbeat rather than a constant because that is
what determines how often the file is refreshed — the same reasoning as
`CoverageAnalysis`. A force-quit recorder leaves a stale status file behind, and
a stale file must read as "not running" rather than as "running", or the app
would report a pending restart that is never coming.

This is a *hint*, and is treated as one. Being wrong in either direction costs a
sentence of UI copy, never a lost write.

---

## The blocker for the App Store edition

**"A folder you choose" may not be shippable in the sandboxed build**, and not
for the obvious reason.

The obvious reason — a sandboxed app cannot read arbitrary paths — is solved:
`NSOpenPanel` grants access to what the user picks, and
`URL.bookmarkData(options: .withSecurityScope)` persists it. The documentation
for `withSecurityScope` says it "provides a security-scoped URL allowing
read/write access to a file-system resource" and is "For use in an app that
adopts App Sandbox"
(<https://developer.apple.com/documentation/foundation/nsurl/bookmarkcreationoptions/withsecurityscope>,
retrieved 2026-08-05).

The real problem is *who* the grant is for. `startAccessingSecurityScopedResource()`
"makes the resource pointed to by a security-scoped URL available to the app…
by way of adding its location to your app's sandbox"
(<https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource()>,
retrieved 2026-08-05).

**But anchors are written by the recorder, not the viewer.** They are a
consequence of appending records, and the recorder is a separate process in its
own sandbox container. A bookmark the viewer resolved and started accessing does
nothing for it.

So a sandboxed "folder you choose" needs, at minimum:

1. The `com.apple.security.files.bookmarks.app-scope` entitlement on both
   binaries.
2. The viewer writing the bookmark **data** into the shared App Group container
   alongside the config, rather than a bare path.
3. The recorder resolving that bookmark itself and calling
   `startAccessingSecurityScopedResource()` in its own process, balanced with
   `stopAccessingSecurityScopedResource()` — the documentation is explicit that
   failing to balance them "leaks kernel resources".
4. A schema change: `hashAnchor.directory` is a `String`. Bookmark data is not a
   path and cannot live in that field, so this is an additive optional field, not
   an edit to the existing one.

**Unverified, and load-bearing.** Apple's documentation on the pages above
describes the grant as applying to "your app" without stating whether the scope
is per-process, per-bundle-ID, or per-team, and I could not find a normative
statement on `developer.apple.com` or `swift.org`. Point 3 assumes the recorder
must resolve the bookmark itself. If that assumption is wrong the plan gets
simpler, not harder — but it should be confirmed before anyone schedules the
work, because it decides whether the feature can ship in the App Store edition at
all or has to be Developer-ID only.

Until then: this build is unsandboxed, a picked folder is a plain path, and it
works. The interface does not pretend otherwise.

---

## What this phase does not do

- Restart the recorder so it re-reads. The shipping viewer does exactly this
  after writing (`TelegramSettingsStore.applyRecorderChangesIfActive()` →
  `installer.restartLaunchAgent()`), but launch-agent lifecycle is Wave 7 and is
  not built here. The interface therefore reports the pending restart rather than
  performing it.
- Write anything other than the anchor section. Every other key is preserved
  byte-for-byte, including the seven sections this build does not model at all.
- Merge concurrent edits. There is one writer.
