import Foundation

/// Everything the interface derives from one window over one dataset,
/// recomputed off the main actor and cancellable.
///
/// # Why this is an actor and not a computed property
///
/// It used to be computed properties on `MainPage.Model`, which is
/// `@MainActor`. That is fine over a 340-event fixture and catastrophic over a
/// real ledger: filtering, searching, and counting 250,000 events happens on
/// every window change, and window changes arrive several times a second while
/// a zoom key is held. On the main actor that is a stutter you can see.
///
/// Here the work happens on the actor's executor, the main actor awaits it, and
/// a superseded computation is cancelled rather than finished.
///
/// # Why the results are memoised
///
/// Zoom is reversible and users reverse it. Holding ⌘− and then ⌘+ walks back
/// through windows that were just computed; a bounded LRU turns the return
/// journey into cache hits. See ``Memoized``, and note it never caches a throw —
/// which matters here precisely because the throw is usually `CancellationError`.
actor TimelineDerivation {

    /// Everything a derivation depends on, and nothing else.
    ///
    /// `Hashable`, because it is the cache key. `dataGeneration` is what makes
    /// caching sound across a reload: the events live in a box the key cannot
    /// see, so the generation stands in for them.
    struct Request: Hashable, Sendable {
        var windowStart: Date
        var windowEnd: Date
        var enabledKinds: Set<EventKind>
        var query: String
        var dataGeneration: Int

        init(window: TimelineWindow, enabledKinds: Set<EventKind>, query: String, dataGeneration: Int) {
            self.windowStart = window.start
            self.windowEnd = window.end
            self.enabledKinds = enabledKinds
            self.query = query.trimmingCharacters(in: .whitespaces).lowercased()
            self.dataGeneration = dataGeneration
        }
    }

    struct Result: Equatable, Sendable {
        /// Events inside the window that pass the filters.
        var visibleEvents: [TimelineEvent]
        /// Per-category counts, scoped to the window and *before* the category
        /// filter is applied — a chip has to show what unticking it would bring
        /// back.
        var counts: [EventKind: Int]
        /// Everything in the window, filters ignored.
        var totalInWindow: Int
        /// Gaps overlapping the window. Never filtered: an absence of recording
        /// is not an event, so no filter may hide it.
        var gaps: [CoverageGap]
        var level: ZoomLevel
    }

    /// The events, behind a reference the memoised closure can capture.
    ///
    /// A property wrapper's value is built during `init`, before `self` exists,
    /// so the wrapped closure cannot capture the actor (see ``Memoized``). That
    /// is a useful constraint — it forces the wrapped function to be pure — but
    /// the data has to reach it somehow, and this is the honest way: a box the
    /// closure holds and the actor replaces.
    ///
    /// Not `Sendable`, and it never leaves this actor.
    private final class DataBox {
        var events: [TimelineEvent] = []
        var gaps: [CoverageGap] = []
    }

    private let data = DataBox()
    private var generation = 0

    /// Twelve entries: enough to cover a full zoom-in-and-back-out journey
    /// through the preset spans plus a few intermediate steps.
    @Memoized private var compute: (Request) throws -> Result

    init() {
        let data = self.data
        _compute = Memoized(
            wrappedValue: { request in
                try TimelineDerivation.derive(request, events: data.events, gaps: data.gaps)
            },
            capacity: 12
        )
    }

    /// Points the derivation at new data.
    ///
    /// Everything cached describes a ledger that no longer exists, so the cache
    /// is dropped *and* the generation is bumped: either alone would be enough,
    /// and having both means a mistake in one does not silently serve stale
    /// answers about somebody's history.
    func replace(events: [TimelineEvent], gaps: [CoverageGap]) {
        data.events = events
        data.gaps = gaps
        generation += 1
        _compute.invalidate()
    }

    var dataGeneration: Int { generation }

    /// The derived view of `window`.
    ///
    /// Throws `CancellationError` when the calling task is cancelled, which the
    /// caller treats as "a newer window superseded this one", not as an error.
    func result(
        window: TimelineWindow,
        enabledKinds: Set<EventKind>,
        query: String
    ) throws -> Result {
        try compute(
            Request(
                window: window,
                enabledKinds: enabledKinds,
                query: query,
                dataGeneration: generation
            ))
    }

    /// Cache statistics, so a test can assert the cache is actually working
    /// rather than merely present.
    var cacheStatistics: (hits: Int, misses: Int) { (_compute.hits, _compute.misses) }

    // MARK: - The pure part

    /// `nonisolated static` and pure: it reads only its arguments, which is what
    /// makes memoising it correct.
    private nonisolated static func derive(
        _ request: Request,
        events: [TimelineEvent],
        gaps: [CoverageGap]
    ) throws -> Result {
        var inWindow = [TimelineEvent]()
        var visible = [TimelineEvent]()
        var counts = [EventKind: Int]()

        // One pass. Checking cancellation every 4,096 events keeps the check
        // itself off the hot path while still aborting within a frame — at
        // 250,000 events that is sixty checks, not a quarter of a million.
        for (index, event) in events.enumerated() {
            if index & 0xFFF == 0 { try Task.checkCancellation() }

            // Inclusive at both ends, for the reason on `TimelineWindow.contains`.
            guard event.at >= request.windowStart, event.at <= request.windowEnd else { continue }
            inWindow.append(event)
            counts[event.kind, default: 0] += 1

            guard request.enabledKinds.contains(event.kind) else { continue }
            if !request.query.isEmpty {
                let haystack = "\(event.label) \(event.detail) \(event.source)".lowercased()
                guard haystack.contains(request.query) else { continue }
            }
            visible.append(event)
        }

        try Task.checkCancellation()

        let window = TimelineWindow(
            history: request.windowStart...max(request.windowEnd, request.windowStart.addingTimeInterval(1)),
            centredOn: request.windowStart.addingTimeInterval(
                request.windowEnd.timeIntervalSince(request.windowStart) / 2),
            span: request.windowEnd.timeIntervalSince(request.windowStart)
        )

        return Result(
            visibleEvents: visible,
            counts: counts,
            totalInWindow: inWindow.count,
            gaps: CoverageAnalysis.gaps(gaps, overlapping: window),
            level: ZoomLevel.resolve(window: window, visibleCount: visible.count)
        )
    }
}
