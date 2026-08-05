import Foundation

/// Reads a real ledger from disk into a ``TimelineSnapshot``.
///
/// # This is the milestone
///
/// Everything in `Primitives/`, `Ledger/`, `Platform/`, and `Config/` exists to
/// make this one function trustworthy. It is also the only place the engine and
/// the interface meet, which is why it lives in the view-model layer and why
/// `DesignSystem/` is forbidden from naming it.
///
/// # Streaming, and what streaming does and does not buy
///
/// The read is a `for try await` over ``LedgerRecordSequence``, so at no point
/// is more than one line of the ledger in memory. That is what makes a two-year
/// history openable at all.
///
/// It does not bound what is *retained*. So the newest
/// ``TimelineLoadRequest/retainedEventLimit`` events are kept in a ring buffer
/// and everything older is counted and dropped, with the count reported in
/// ``TimelineSnapshot/omittedOlderRecords``. Memory is a function of the cap,
/// not of the history.
///
/// # Cancellation is real
///
/// `Task.checkCancellation()` runs in the read loop, and the sequence checks
/// again before each element. Pointing the app at a different ledger while a
/// two-year load is in flight must stop that load, not wait it out.
///
/// # A ledger that cannot be read is never reported as an empty one
///
/// Failures become ``IntegrityState/unreadable(reason:)``, which the banner
/// renders as a loud failure. The one thing this must never do is return an
/// empty snapshot on error: "nothing was recorded" and "I could not tell you
/// what was recorded" are different sentences, and only one of them is true.
struct LedgerTimelineSource: TimelineSource {
    let store: LedgerStore
    let describedOrigin: String

    init(store: LedgerStore, describedOrigin: String) {
        self.store = store
        self.describedOrigin = describedOrigin
    }

    /// Convenience for the composition root: build a store for a ledger at
    /// `locations`, with the key and rotation size the config asks for.
    static func installed(
        locations: StorageLocations,
        hmacKey: Data,
        config: EngineConfig
    ) throws -> LedgerTimelineSource {
        let store = try LedgerStore(
            ledgerURL: locations.ledgerURL,
            hmacKey: hmacKey,
            maxFileBytes: config.storage?.maxLedgerFileBytes
        )
        return LedgerTimelineSource(store: store, describedOrigin: locations.ledgerURL.path)
    }

    func load(_ request: TimelineLoadRequest) async throws -> TimelineSnapshot {
        do {
            return try await read(request)
        } catch is CancellationError {
            // Cancellation is not a failure to report to the user; the caller
            // superseded this load and will render the next one.
            throw CancellationError()
        } catch {
            Diagnostics.timeline.error(
                "Ledger load failed: \(String(describing: error), privacy: .public)")
            return .unreadable(
                origin: describedOrigin,
                reason: (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            )
        }
    }

    private func read(_ request: TimelineLoadRequest) async throws -> TimelineSnapshot {
        var retained = RetainedEvents(limit: request.retainedEventLimit)
        var total = 0

        for try await entry in try await store.entries() {
            // Checked here as well as inside the sequence: mapping is the
            // expensive half, and a superseded load must not pay for it.
            try Task.checkCancellation()
            total += 1
            retained.append(LedgerEventMapping.timelineEvent(from: entry))
        }

        // # Ledger order is append order, which is not time order
        //
        // The chain is ordered by when a record was *written*. That is usually
        // also when the event happened, and it is not the same thing:
        //
        // - A `ledger.rotated` record is stamped when rotation occurs, which can
        //   fall between two events recorded from a spool moments earlier.
        // - An event ingested from the spool carries the time it was observed,
        //   not the time the recorder got round to it.
        // - A clock adjustment moves `Date.now` under a running recorder.
        //
        // The timeline is a *time* axis, so it has to be sorted by time. This
        // was found the hard way: over a 130,000-record ledger with 3,044
        // rotations, gap analysis on append order reported 3,045 coverage gaps
        // instead of 2 — every out-of-order stamp read as a jump forward, and
        // every jump forward read as a silence.
        //
        // Ties break on the ordinal, so records sharing a timestamp keep their
        // ledger order and the result is deterministic. Swift's `sort` is
        // explicitly documented as *not* guaranteed stable, so relying on
        // stability here would be relying on an implementation detail — and a
        // burst writes hundreds of records inside one second.
        let events = retained.events.sorted {
            $0.at == $1.at ? $0.record < $1.record : $0.at < $1.at
        }

        let integrity = request.verify ? try await verifyChain(recordCount: total) : .unverified

        try Task.checkCancellation()

        // Synchronous: a single pass over an array already in memory.
        let gaps = CoverageAnalysis.gaps(in: events, threshold: request.gapThreshold)

        guard let first = events.first, let last = events.last else {
            return .empty(origin: describedOrigin)
        }

        // A history of zero length would make every fraction a division by zero.
        // One record is a real history; it just needs a window to sit in.
        let upper = max(last.at, first.at.addingTimeInterval(TimelineWindow.minimumSpan))

        Diagnostics.timeline.info(
            """
            Loaded \(total, privacy: .public) record(s), retained \(events.count, privacy: .public), \
            \(gaps.count, privacy: .public) coverage gap(s)
            """)

        return TimelineSnapshot(
            events: events,
            gaps: gaps,
            history: first.at...upper,
            totalRecords: total,
            omittedOlderRecords: retained.omitted,
            firstRetainedAt: first.at,
            integrity: integrity,
            origin: describedOrigin
        )
    }

    /// Verification, and the anchor comparison it cannot do on its own.
    private func verifyChain(recordCount: Int) async throws -> IntegrityState {
        let verification = try await store.verify()

        guard verification.isValid else {
            return .failed(
                lastTrustedOrdinal: verification.lastTrustedOrdinal,
                issueCount: verification.issues.count,
                recordCount: verification.recordCount
            )
        }
        return .verified(recordCount: verification.recordCount)
    }
}

/// The newest `limit` events, in order, with everything older counted.
///
/// # Why a ring buffer rather than "load then suffix"
///
/// `Array(all.suffix(limit))` requires `all` to exist first, which is the whole
/// problem. This keeps exactly `limit` elements no matter how long the stream
/// runs, so peak memory is the cap.
///
/// A `struct`, so it lives in the loading function's own storage and needs no
/// isolation of its own.
private struct RetainedEvents {
    private let limit: Int
    private var buffer: [TimelineEvent] = []
    /// Index of the oldest element once the buffer is full.
    private var head = 0
    private(set) var omitted = 0

    init(limit: Int) {
        self.limit = max(1, limit)
        buffer.reserveCapacity(min(self.limit, 8192))
    }

    mutating func append(_ event: TimelineEvent) {
        if buffer.count < limit {
            buffer.append(event)
            return
        }
        buffer[head] = event
        head = (head + 1) % limit
        omitted += 1
    }

    /// Oldest first, unwrapped from the ring.
    var events: [TimelineEvent] {
        guard omitted > 0 else { return buffer }
        return Array(buffer[head...]) + Array(buffer[..<head])
    }
}
