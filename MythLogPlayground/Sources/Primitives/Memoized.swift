import Foundation

/// A pure function behind a bounded least-recently-used cache.
///
/// # Why this earns its place
///
/// Bucket aggregation is the hot path behind continuous zoom. Every window
/// change re-buckets every event in the window — at the density level that is
/// the entire visible history — and zoom changes arrive in bursts: press and
/// hold ⌘− and the window changes several times a second, each step passing
/// through windows the user already saw on the way in. The reverse direction is
/// the same set of windows in reverse order. A small LRU turns a zoom-out
/// following a zoom-in into cache hits for every step but the first.
///
/// Written by hand that is a dictionary, a recency list, an eviction rule, and a
/// key type, repeated once per derived quantity — buckets, per-category counts,
/// the visible-event slice. Three copies of an eviction bug. The wrapper is the
/// one place that logic lives, and the call site reads exactly like calling the
/// function it wraps:
///
/// ```swift
/// @Memoized(capacity: 12) private var histogram = TimelineHistogram.compute
/// ...
/// let bars = try histogram(request)   // computed, or not, transparently
/// ```
///
/// # The compiler enforces that the wrapped function is pure
///
/// A property wrapper's value is established during initialisation, before
/// `self` exists, so the wrapped closure *cannot* capture `self` — Swift rejects
/// `lazy` alongside a wrapper precisely to close that door. That falls out as a
/// safety property rather than an inconvenience: memoising a function that reads
/// mutable instance state would return stale answers, and here it is not
/// expressible. Anything the computation needs must be in the key.
///
/// # Why a `final class`, and why that is safe
///
/// Memoisation is a write on read: `wrappedValue` must be able to record a miss.
/// A `struct` wrapper would need `mutating get`, which makes the wrapper
/// unusable through a `let` and forces copy-in/copy-out at every access — which
/// on a wrapper whose whole point is a shared cache would copy the dictionary
/// and defeat it.
///
/// So this is a reference type, and deliberately **not** `Sendable`. That is the
/// safety property, not a gap in it: the compiler will refuse to let an instance
/// escape the isolation domain that holds it. In this codebase the only instance
/// is a stored property of the `TimelineDerivation` actor, so every access is
/// already serialised by actor isolation and no lock is needed or wanted. If
/// someone later tries to hoist it to a global or capture it in a detached task,
/// that is a compile error rather than a data race.
///
/// # Cancellation
///
/// `compute` is throwing, and a throw is **never** cached. This matters more
/// than it looks: the aggregation calls `Task.checkCancellation()`, so a
/// superseded zoom step throws `CancellationError` part-way through. Caching
/// that would poison the entry for a window the user is about to look at.
@propertyWrapper
final class Memoized<Key: Hashable, Value> {
    private let compute: (Key) throws -> Value
    private let capacity: Int

    private var entries: [Key: Value] = [:]
    /// Least-recently-used first. Linear scans are correct here because
    /// `capacity` is a handful of entries; a linked list would be more code to
    /// be wrong in.
    private var recency: [Key] = []

    private(set) var hits = 0
    private(set) var misses = 0

    init(wrappedValue compute: @escaping (Key) throws -> Value, capacity: Int = 8) {
        precondition(capacity > 0, "A cache that cannot hold an entry is a slower function.")
        self.compute = compute
        self.capacity = capacity
    }

    /// The memoised function. Calling it is indistinguishable from calling the
    /// function it wraps, apart from being faster on a repeat.
    var wrappedValue: (Key) throws -> Value {
        { [self] key in try value(for: key) }
    }

    /// The wrapper itself, so tests can assert that the cache is actually being
    /// hit rather than merely present.
    var projectedValue: Memoized<Key, Value> { self }

    private func value(for key: Key) throws -> Value {
        if let cached = entries[key] {
            hits += 1
            touch(key)
            return cached
        }

        // Computed before touching any state: if this throws — cancellation,
        // most often — the cache is left exactly as it was.
        let value = try compute(key)

        misses += 1
        entries[key] = value
        recency.append(key)
        evictIfNeeded()
        return value
    }

    private func touch(_ key: Key) {
        guard let index = recency.firstIndex(of: key) else { return }
        recency.remove(at: index)
        recency.append(key)
    }

    private func evictIfNeeded() {
        while recency.count > capacity {
            let evicted = recency.removeFirst()
            entries[evicted] = nil
        }
    }

    /// Drops everything. Called when the underlying data changes, since every
    /// cached answer describes a ledger that no longer exists.
    func invalidate() {
        entries.removeAll(keepingCapacity: true)
        recency.removeAll(keepingCapacity: true)
        hits = 0
        misses = 0
    }
}
