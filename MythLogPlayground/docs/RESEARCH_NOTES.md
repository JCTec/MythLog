# Research notes — Swift 6 concurrency

Everything below was checked against `developer.apple.com` or `swift.org` on the
date shown. Nothing here rests on a blog post, a Stack Overflow answer, or
recollection. Where a claim could not be verified against those two domains it is
listed under **Unverified** and the design avoids depending on it.

Retrieved via the DocC JSON that backs those sites (`.../data/documentation/…`),
because the rendered pages are client-side applications that return an empty
shell to a fetcher. Same content, same origin.

Toolchain this was written against: Swift 6.3.2 (swiftlang-6.3.2.1.108),
Xcode 26.5. Target: macOS 14.0.

---

## 1. Data isolation and `Sendable`

**Claim.** Isolation is the mechanism, not a convention: mutable state is
reachable from one isolation domain at a time, and a value may move between
domains but may never be touched concurrently from two.

> "Data isolation is the *mechanism* used to protect shared mutable state."
> "Mutable state can only be accessed from one isolation domain at a time."
> "You can pass mutable state from one isolation domain to another, but you can
> never access that state concurrently from a different domain."

Source: swift.org, Swift 6 Concurrency Migration Guide — *Data Race Safety*.
<https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/dataracesafety>
Retrieved 2026-08-05.

**Claim.** Every declaration is non-isolated, isolated to an actor instance, or
isolated to a global actor. Value types are implicitly `Sendable` when their
stored properties are; actors are implicitly `Sendable` regardless of their
properties.

> "A conformance to `Sendable` means the given type is thread safe, and values of
> the type can be shared across arbitrary isolation domains without introducing a
> risk of data races."
> "Value types in Swift are implicitly `Sendable` when all their stored
> properties are also Sendable."
> "…all actor types implicitly `Sendable`, even if their properties are not
> `Sendable` themselves."
> "To make a class `Sendable` it must contain no mutable state and all immutable
> properties must also be `Sendable`."

Same source, same date.

**Claim.** The precise conditions for a *class* to be `Sendable` are three, and
`@MainActor` classes are an exception to all of them.

> A class must "Be marked `final`", "Contain only stored properties that are
> immutable and sendable", and "Have no superclass or have `NSObject` as the
> superclass".
> "Classes marked with `@MainActor` are implicitly sendable, because the main
> actor coordinates all access to its state. These classes can have stored
> properties that are mutable and nonsendable."

Source: developer.apple.com, `Swift/Sendable`.
<https://developer.apple.com/documentation/swift/sendable>
Retrieved 2026-08-05.

**Applied here.** Every model type that crosses a boundary — `AlarmEvent`,
`LedgerRecord`, `LedgerEntry`, `LedgerVerification`, `TimelineEvent`,
`TimelineWindow`, `CoverageGap` — is a value type whose stored properties are all
`Sendable`, so conformance is implicit and free. No engine type is a class that
needed to be argued into `Sendable`.

---

## 2. `@unchecked Sendable` — when it is legitimate

**Claim.** `@unchecked` is for types that *already* synchronise their own state.
It is not a way to quiet the compiler about a type that is not thread-safe.

> "If you have a type that is already doing manual synchronization, you can
> express this to the compiler by marking your `Sendable` conformance as
> `unchecked`."
> "…if a type isn't already thread-safe, attempting to make it `Sendable` should
> not be your first approach."
> "To declare conformance to `Sendable` without any compiler enforcement, write
> `@unchecked Sendable`. You are responsible for the correctness of unchecked
> sendable types, for example, by protecting all access to its state with a lock
> or a queue."

Sources: swift.org *Common Problems*
<https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/commonproblems>
and developer.apple.com `Swift/Sendable`. Retrieved 2026-08-05.

**Decision.** This port contains **zero** `@unchecked Sendable`. The shipping app
has one — `private struct LedgerFileManager: @unchecked Sendable` in
`Sources/MythLogCore/HashChainLedger.swift` — wrapping a `FileManager` so it
could be captured by a detached task. That is the "not already thread-safe"
case the guidance warns about: `FileManager.default` is shared process-wide and
the wrapper asserts a safety property nothing establishes.

It is replaced here by a `sending` parameter (§4): the actor is handed a freshly
constructed `FileManager` that the caller provably no longer holds. Same
behaviour, compiler-checked instead of asserted.

---

## 3. `nonisolated(unsafe)`

**Claim.** Legitimate only with real external synchronisation.

> "Only use `nonisolated(unsafe)` when you are carefully guarding all access to
> the variable with an external synchronization mechanism such as a lock or
> dispatch queue."

Source: swift.org, *Common Problems*, as above. Retrieved 2026-08-05.

**Decision.** This port contains **zero** `nonisolated(unsafe)`. The shipping app
uses it for four test seams (`SandboxEnvironment.overrideIsSandboxed`,
`SharedContainer.overrideContainerURL` / `overrideForceUnavailable`,
`ProcessEntitlements.overrideNetworkClient`). Each is process-wide mutable state
with no synchronisation at all; the justification given is "only mutated from
single-threaded test setup", which is a convention, not a mechanism — precisely
what the guidance rules out.

Here the same testability is obtained by making the environment an *injected
value* (`SandboxEnvironment` is a `Sendable` struct with a `.current` factory and
an explicit `.sandboxed`/`.unsandboxed` constructor) rather than a global the
tests reach in and mutate. Tests construct the environment they want. No global
mutable state exists to need an escape hatch.

---

## 4. `sending`

**Claim.** Region-based isolation lets the compiler prove a non-`Sendable` value
can safely move between domains; `sending` states that transfer in the signature.

> "Region-based isolation allows the compiler to permit instances of
> non-`Sendable` types to cross isolation domains when it can prove doing so
> cannot introduce data races."
> "The `sending` keyword makes this explicit in function signatures, providing
> guarantees about how parameters can be safely transferred across isolation
> boundaries."

Source: swift.org, *Data Race Safety*, as above. Retrieved 2026-08-05.

**Verification gap, stated honestly.** The Swift book's *Declarations* chapter
(<https://docs.swift.org/swift-book/documentation/the-swift-programming-language/declarations>,
retrieved 2026-08-05) does **not** document `sending`; I could not find a
normative statement of its exact caller-side obligation ("the caller may not use
the value after the call") on either permitted domain. The design therefore does
not lean on any property beyond what the sentence above states, and correctness
is left to the compiler: if the transfer were not provable, the build would fail.

**Applied here.** `LedgerStore.init(…, fileManager: sending FileManager)`. The
call sites pass `FileManager()` — a fresh instance, in its own region, never
reachable again by the caller. This is the honest description of what happens and
it is the direct replacement for the `@unchecked Sendable` wrapper in §2.

---

## 5. Actors

**Claim.** Actors serialise access to their own state and are themselves
`Sendable`; cross-actor access is asynchronous.

> "All actor types implicitly conform to `Sendable` because actors ensure that
> all access to their mutable state is performed sequentially."
> "By default, actors execute tasks on a shared global concurrency thread pool."

Sources: developer.apple.com `Swift/Sendable` and `Swift/Actor`.
<https://developer.apple.com/documentation/swift/actor> Retrieved 2026-08-05.

**Applied here.** `LedgerStore` is an `actor`. It owns the file URLs, the HMAC
key, the `FileManager`, and the per-segment ordinal cache. Concurrent readers
serialise on it with no lock in the Swift code at all — the only locking left is
`flock(2)`, which exists for *other processes* (the shipping recorder), not for
other threads in this one.

The shipping app instead hand-built a serial queue *inside* an actor: an
`ioTail: Task<Void, Never>` chain in `HashChainLedger.runSerializedIO`. That
re-implements what actor isolation already provides, and it does so with detached
tasks that escape the actor's isolation and priority. It is not carried across.

---

## 6. Cancellation

**Claim.** Cancellation is cooperative; a task must check.

> "Swift concurrency uses a cooperative cancellation model. Each task checks
> whether it has been canceled at the appropriate points in its execution, and
> responds to cancellation appropriately."

Source: docs.swift.org, TSPL — *Concurrency*.
<https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency>
Retrieved 2026-08-05.

**Claim.** `Task.checkCancellation()` "Throws an error if the task was canceled",
and the error "is always an instance of `CancellationError`."

Source: developer.apple.com, `Swift/Task/checkCancellation()`.
<https://developer.apple.com/documentation/swift/task/checkcancellation()>
Retrieved 2026-08-05.

**Applied here.** `Task.checkCancellation()` is called inside every unbounded
loop: the record decode loop in `LedgerStore`, the per-segment verify loop, and
the bucket/count aggregation loop in `TimelineDerivation`. Zoom fires rapidly and
the store cancels the in-flight derivation before starting the next one; without
the check, a superseded 100k-record aggregation would run to completion and burn
a core for nothing.

---

## 7. Task groups

**Claim.** A task group always awaits its children, propagates cancellation to
them, and schedules them in any order; child results must be `Sendable`.

> "A task group **always** waits for all child tasks to complete before it's
> destroyed."
> "Because a `TaskGroup` is a structured concurrency primitive, cancellation is
> automatically propagated through all of its child-tasks (and their child
> tasks)."
> "Tasks added to a task group execute concurrently, and may be scheduled in any
> order."
> "When a parent task is canceled, each of its child tasks is also automatically
> canceled."

Sources: developer.apple.com `Swift/TaskGroup`
<https://developer.apple.com/documentation/swift/taskgroup> and docs.swift.org
TSPL *Concurrency*. Retrieved 2026-08-05.

**Applied here.** `LedgerStore.verify()` fans out one child task per rotated
segment with `withThrowingTaskGroup`. Each child verifies a segment's *internal*
chain — recomputing every HMAC and checking record-to-record linkage — which is
independent of every other segment. Because results arrive in any order, each
child returns a `SegmentVerification` carrying its own segment index, and the
parent sorts by that index before checking the seams (`segment[n].lastHash ==
segment[n+1].firstPreviousHash`) serially. The seam check is the only part that
is inherently ordered, and it is O(segments), not O(records).

---

## 8. `AsyncSequence` and `AsyncStream`

**Claim.** `AsyncSequence` yields elements as they become available rather than
requiring them all up front.

> "an `AsyncSequence` may have all, some, or none of its values available when
> you first use it. Instead, you use `await` to receive values as they become
> available."
> "A `for`-`await`-`in` loop potentially suspends execution at the beginning of
> each iteration, when it's waiting for the next element to be available."

Sources: developer.apple.com `Swift/AsyncSequence`
<https://developer.apple.com/documentation/swift/asyncsequence> and docs.swift.org
TSPL *Concurrency*. Retrieved 2026-08-05.

**Claim.** `FileHandle.AsyncBytes` exposes a file as an async byte sequence, and
`.lines` gives "An asynchronous sequence of newline-separated `Strings` decoded
as UTF8".

Source: developer.apple.com `Foundation/FileHandle/AsyncBytes`.
<https://developer.apple.com/documentation/foundation/filehandle/asyncbytes>
Retrieved 2026-08-05.

**Claim.** `AsyncStream`'s continuation "conforms to Sendable, which permits
calling it from concurrent contexts external to the iteration of the
`AsyncStream`", and the stream buffers, unbounded by default
(`bufferingPolicy` defaults to `Int.max`).

Source: developer.apple.com `Swift/AsyncStream`.
<https://developer.apple.com/documentation/swift/asyncstream>
Retrieved 2026-08-05.

**Decision — `AsyncSequence`, not `AsyncStream`, for ledger records.**
Both were considered.

- `AsyncStream` would be the natural bridge if records arrived from a callback.
  They do not: the source is a file, which is already pull-shaped. Worse, the
  default unbounded buffer means a producer that reads faster than the UI
  consumes would materialise the whole two-year ledger in the buffer — the exact
  failure the streaming requirement exists to prevent. Bounding it correctly
  would mean picking a policy with no principled value.
- `FileHandle.AsyncBytes.lines` is genuinely demand-driven: the file is read only
  as far as the consumer has pulled. `LedgerRecordSequence` is a thin
  `AsyncSequence` over it that decodes one line per element and assigns the
  cumulative ordinal.

`AsyncStream` is still used once, where it is the right tool: `LedgerLoader`
turns a load into a sequence of `LoadProgress` values for the UI, because
progress genuinely is a push-shaped callback stream and dropping intermediate
progress is correct (`.bufferingNewest(1)`).

---

## 9. Property wrappers and Observation

**Claim.** `@Observable` "declares and implements conformance to the `Observable`
protocol to the type at compile time", tracks only properties read inside
`withObservationTracking`, and provides `@ObservationIgnored` to exclude a
property.

Source: developer.apple.com, Observation framework.
<https://developer.apple.com/documentation/observation> Retrieved 2026-08-05.

**Unverified.** Apple's Observation documentation says nothing about applying a
custom property wrapper to a stored property of an `@Observable` type. I could
not find any statement on either permitted domain about whether the macro's
rewriting of stored properties into accessors composes with an arbitrary
`@propertyWrapper`, nor about the observation semantics if it does.

**Decision.** Treat it as unknown and do not build on it. Both property wrappers
in this port are applied to types that are *not* `@Observable`:

- `@Clamped` is used in `TimelineWindow`, a `struct`.
- `@Memoized` is used in `TimelineDerivation`, an `actor`.

`MainPage.Model` remains `@MainActor @Observable` with plain stored properties,
exactly as it is today. If the interaction is later documented, nothing here has
to be unwound.

**Rejected wrapper.** The brief offered a file-backed configuration wrapper "*if*
it reads better than a plain `load`/`save`". It does not, and it is not built.
A wrapper would have to hide a throwing, possibly-slow disk read behind a
non-throwing synchronous property access, so a failure to read the config would
either trap or silently yield defaults. Silently yielding defaults is the exact
shape of the 1.0.0 bug this port exists to prevent: a container that could not be
resolved reading as "nothing recorded". `EngineConfig.load(from:)` throws, and
callers handle it.

---

## 10. `@preconcurrency`

**Claim.** Two meanings — on a declaration it stages diagnostics for clients; on
an import it downgrades errors from an unmigrated dependency.

> On imports it "Downgrades errors to warnings (Swift 6) … for unmigrated
> dependencies."
> When applied to a `@MainActor` class it "marks the isolation as conditional on
> the client module also having complete checking enabled".

Sources: swift.org *Common Problems* and *Incremental Adoption*.
<https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/incrementaladoption>
Retrieved 2026-08-05.

**Decision.** Not used. Its purpose is interoperating with code that has not been
migrated. Every dependency here is Foundation, CryptoKit, OSLog, and SwiftUI from
the current SDK, and there is no source-compatibility obligation to a client
module — this target *is* the client. Reaching for it would only mask a real
diagnostic.

---

## Summary of decisions that could have gone the other way

| Decision | Chosen | Alternative | Why |
| --- | --- | --- | --- |
| Serialising ledger I/O | `actor` isolation | Task-chain queue, as shipping | Isolation is the language's own mechanism (§5); the task chain re-implements it and leaks detached tasks |
| `FileManager` into the actor | `sending` parameter | `@unchecked Sendable` wrapper, as shipping | Compiler-proven vs. asserted (§2, §4) |
| Streaming records | `AsyncSequence` over `FileHandle.AsyncBytes.lines` | `AsyncStream` | Default unbounded buffer defeats streaming (§8) |
| Progress reporting | `AsyncStream` `.bufferingNewest(1)` | `AsyncSequence` | Progress is push-shaped and stale values are worthless (§8) |
| Test seams | Injected `Sendable` value | `nonisolated(unsafe)` global, as shipping | No synchronisation exists to justify the escape hatch (§3) |
| Property wrappers on the observable model | Avoided | `@Clamped` on `MainPage.Model` | Interaction with `@Observable` is undocumented (§9) |
| Reading the active segment | Shared `flock` held for the whole stream | Lock-free read | A torn final line would be reported as corruption; blocking one append is the correct trade for a viewer whose claim is an accurate record |
| Loading the interface's data | Structured (`.task { await load() }`) | Unstructured `Task` + `deinit` cancel | `deinit` on a `@MainActor` class is nonisolated and cannot touch isolated state, so there is nowhere to cancel from; SwiftUI's `.task` owns the lifetime instead |
| Superseding a derivation | Unstructured `Task`, cancelled by the next `refresh()` | Structured | It has to outlive the call that started it and be cancellable by the *next* one, which structured concurrency does not offer |

---

## Measured, not assumed

Numbers from this machine (Apple Silicon, Xcode 26.5, **Debug** build), against a
133,893-record ledger written by the shipping engine across 3,044 rotated
segments:

| | |
| --- | --- |
| Warm load (read + verify + gap analysis) | ~6.9 s |
| Resident memory, fully loaded | ~176 MB |
| CPU once idle | 0.0% |
| Coverage gaps found | 2 — one force-quit, one graceful, correctly distinguished |
| Ordinal sidecars written | 3,043 (one per rotated segment) |

`ps -o %cpu` was misleading here and is worth noting: on macOS it reports an
average over the process's lifetime, so a process that has just done seven
seconds of work reads as ~99% busy while being completely idle. The figures
above are instantaneous samples from `top -l 2`.
