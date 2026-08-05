# Human checklist — engine (Waves 1–4)

Things a machine cannot check for itself. Each item says what to do, what you
should see, and — the part that matters — **what it would look like if it were
broken**, because most of the failures this engine guards against look like
success.

Everything below assumes you are in `MythLogPlayground/` with the project
generated:

```sh
cd MythLogPlayground
xcodegen generate
```

---

## 0. The automated gates, run once by hand

```sh
./Scripts/check-layering.sh --self-test
xcodebuild -project MythLog.xcodeproj -scheme MythLog \
  -configuration Debug -destination 'platform=macOS' test
```

**Expect:** `Self-test passed: 6/6 violations caught`, then
`Layering checks passed`, then 98 tests passing with no warnings.

The self-test matters more than the pass. It writes six real violations into
`Sources/Ledger/`, one per rule, confirms each is rejected, and deletes them. A
gate nobody has watched fail is a gate nobody knows works.

---

## 1. Point the app at a real ledger

The composition root reads two environment variables. With both set the app
reads a real ledger; with either missing it falls back to the fixture.

```sh
# In Xcode: Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments ▸ Environment
MYTHLOG_LEDGER=/path/to/events.jsonl
MYTHLOG_HMAC_KEY_HEX=<64 hex characters>
```

For a real install, the ledger is wherever `StorageLocations` resolves — under
the sandbox that is
`~/Library/Group Containers/S8662L649U.com.jctec.mythlog.shared/Application Support/MythLog/events.jsonl`,
and the key is in the login keychain under the account named by
`secrets.hmacKeyAccount` (`ledger-hmac-key` by default).

### 1a. The history matches what the shipping app shows

Open the shipping MythLog beside this one and compare.

**Expect:** the same record count in the header, the same events at the same
times, and the same record numbers in the inspector.

**Broken looks like:** an empty timeline and "0 records", with no error. That is
the 1.0.0 bug — the viewer resolving a different file from the recorder. If you
see it, check what `StorageLocations.explanation` says about where it looked.

### 1b. The record numbers are cumulative, not per-file

Select any event and read the inspector: `#4629 · chained to #4628`.

**Expect:** numbers that increase monotonically across the whole history, and
that match the shipping app for the same event.

**Broken looks like:** numbers that restart near 1 partway back through the
history. That means ordinals are being taken as line indices within one file
rather than cumulative across rotated segments. Scroll back far enough to cross
at least one rotation — `ls` the ledger directory for `*-rotated-*` files to
confirm there is one to cross.

---

## 2. A failing ledger is reported as failing, not as empty

**This is the single most important item on this list.** Work on a **copy**.

```sh
cp -R "$(dirname "$MYTHLOG_LEDGER")" /tmp/ledger-copy
# Change one character inside one record.
sed -i '' '5s/"host":"[^"]*"/"host":"tampered"/' /tmp/ledger-copy/events.jsonl
```

Point `MYTHLOG_LEDGER` at the copy and run.

**Expect:** the header reads **Verification failed**, and the banner names the
last record that still verifies — "Records #1 – #N verify against the chain and
remain trustworthy" — with the rest of the history still drawn.

**Broken looks like:** an empty timeline, a spinner that never resolves, or a
crash. All three are worse than the tamper itself: they tell the user nothing
happened rather than that something did.

### 2a. A truncated file

```sh
cp -R "$(dirname "$MYTHLOG_LEDGER")" /tmp/ledger-cut
# Chop the last 40 bytes, mid-record — what a power cut leaves behind.
truncate -s -40 /tmp/ledger-cut/events.jsonl
```

**Expect:** verification fails, and the records before the damage are still
shown and still counted.

### 2b. A ledger that cannot be read at all

Point `MYTHLOG_LEDGER` at a file that is not a ledger — `/etc/hosts` will do.

**Expect:** "Ledger unreadable", and a banner that says in as many words *"This
is not an empty history — it is a history that could not be read."*

**Broken looks like:** a clean, empty, calm-looking window.

### 2c. The wrong key

Change one character of `MYTHLOG_HMAC_KEY_HEX`.

**Expect:** verification fails against every record, and the history is still
drawn and still counted.

---

## 3. Coverage gaps appear for a force-quit, not only a clean stop

The reason this item exists: a graceful stop writes a record, and a force-quit,
crash, or power cut writes nothing at all. An implementation that pairs stop
records with start records is blind to exactly the case a worried user is
looking at.

### 3a. Make a real one

With the shipping recorder running:

```sh
# Force-quit it. Not "Quit" — SIGKILL, so it has no chance to write anything.
pkill -9 -f mythlog
sleep 400          # more than three heartbeats
# Start it again however you normally would.
```

Then open the viewer over that period.

**Expect:** hatched "no coverage" bands on the timeline, a banner in the list,
and the banner's wording is the **unexplained** variant: *"the ledger does not
say why — nothing was written at all. That is what a force quit, a crash, or a
power cut leaves behind."*

**Broken looks like:** an ordinary quiet stretch with no hatching. That is a
stop/start implementation, and it means the app is silently reassuring about the
one period the user should be asked about.

### 3b. Compare against a clean stop

Quit the recorder normally, wait the same amount of time, restart.

**Expect:** hatching again, but the banner now says the recorder wrote a stop
record and cites its number — the reassuring variant.

Both bands must appear. If only the graceful one does, see above.

### 3c. Without leaving your desk

Two previews in `Sources/Previews/MainPagePreviews.swift` show both variants
over the fixture. Open the canvas and compare the banner text. Use this to check
the wording; use 3a to check the detection.

---

## 4. Zooming stays smooth over a real history

Load a ledger with at least 100,000 records — three months at a 60-second
heartbeat is about 130,000.

Hold ⌘− until fully zoomed out, then ⌘+ back in. Do it fast.

**Expect:** the timeline keeps up; the level chip moves through Density →
Clusters → Events; the counts in the filter bar change on every step; the window
never inverts or collapses.

**Broken looks like:** a beachball, or counts that lag a step behind the
timeline. Both mean derivation is running on the main actor or superseded
computations are not being cancelled.

Watch it in Instruments' Time Profiler if you want certainty: the main thread
should be nearly idle while a zoom is in flight.

### 4a. Both cases visible at once

**Expect:** at Density, at least one hatched band (a gap) and at least one
conspicuously tall bar (a burst). Zoom into the tall bar.

**Expect:** it stays at Clusters rather than exploding into overlapping nodes,
because the level is chosen from span *and* population.

---

## 5. Things worth a look while you are here

- **The header when history was truncated by the retention cap.** Load with a
  small `retainedEventLimit` and confirm the header says "newest since …" rather
  than "since …". Showing the newest slice as though it were everything is the
  same class of lie as an undrawn gap.
- **Ordinal sidecars.** After a load, `ls` the ledger directory: you should see
  `*.jsonl.ordinals.json` beside each rotated segment. Delete them and reload —
  the record numbers must be identical. They are a cache, never a source of
  truth.
- **Sidecars where you cannot write.** Load a ledger from a read-only volume or
  a directory you do not own. It must load correctly and just be slower on the
  second launch.
- **Two copies at once.** Open two instances against the same ledger while the
  recorder is running. Nothing should stall for more than a moment; the shared
  `flock` is taken non-blocking with a two-second ceiling.

---

## What is deliberately not here

Waves 5–8. There is no capture, no agent runtime, no `SMAppService`, no
notifiers, and no Telegram. The app reads a ledger; it does not write one except
in tests.

The config schema *carries* the sections those waves need — `session`,
`filesystem`, `unifiedLog`, `notifications`, `telegram`, `remoteCheckpoint`,
`rules` — and round-trips them untouched, but nothing interprets them yet.
