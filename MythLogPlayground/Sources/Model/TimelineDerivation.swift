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
///
/// # What no filter may do
///
/// Two exemptions are enforced here rather than in ``EventFilter``, because this
/// is the only layer that knows about coverage gaps and about the trust
/// boundary:
///
/// 1. **Gaps survive every filter.** They are derived from ``CoverageGap``
///    values that the filter never touches. An absence of recording is not an
///    event.
/// 2. **Untrusted records survive every filter.** A record past the trust
///    boundary is emitted whatever the filter says, and counted in
///    ``Result/forcedUntrustedCount`` so the interface can explain why it is on
///    screen. Filtering answers "what happened"; it must never be able to answer
///    "can this be believed".
actor TimelineDerivation {

    /// Everything a derivation depends on, and nothing else.
    ///
    /// `Hashable`, because it is the cache key. `dataGeneration` is what makes
    /// caching sound across a reload: the events live in a box the key cannot
    /// see, so the generation stands in for them — and the trust boundary lives
    /// in that same box, so it is covered by the same generation.
    struct Request: Hashable, Sendable {
        var windowStart: Date
        var windowEnd: Date
        var filter: EventFilter
        var dataGeneration: Int

        init(window: TimelineWindow, filter: EventFilter, dataGeneration: Int) {
            self.windowStart = window.start
            self.windowEnd = window.end
            self.filter = filter
            self.dataGeneration = dataGeneration
        }
    }

    struct Result: Equatable, Sendable {
        /// Events inside the window that pass the filters, plus any that the
        /// trust exemption forced through.
        var visibleEvents: [TimelineEvent]
        /// Per-category counts, scoped to the window and *before* any filter is
        /// applied — a chip has to show what unticking it would bring back.
        var counts: [EventKind: Int]
        /// Records at each severity in the window, before any filter.
        ///
        /// Computed in the same pass rather than by a second one. The severity
        /// control needs it on every window change to offer only the levels the
        /// window contains, and a separate pass would have doubled the cost of
        /// panning over a quarter of a million records to count five buckets off
        /// a stored enum.
        var severityCounts: [AlarmSeverity: Int]
        /// Per-category counts *after* every filter. Paired with ``counts`` this
        /// is what a chip shows as "52 / 364"; see ``FilterChip``.
        var passingCounts: [EventKind: Int]
        /// Everything in the window, filters ignored.
        var totalInWindow: Int
        /// Records in the window that the filter is hiding right now.
        ///
        /// The number that must never stop being visible: it is the difference
        /// between "a quiet night" and "a quiet night, because you asked for
        /// one".
        var hiddenInWindow: Int
        /// Records shown despite failing the filter, because they fall past the
        /// trust boundary.
        var forcedUntrustedCount: Int
        /// Gaps overlapping the window. Never filtered: an absence of recording
        /// is not an event, so no filter may hide it.
        var gaps: [CoverageGap]
        var level: ZoomLevel

        var isFilteringAnythingOut: Bool { hiddenInWindow > 0 }
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

        /// The first ordinal that does not verify, or `nil` when everything
        /// does. Held here rather than in the request because it is a property
        /// of the loaded ledger, so a reload's generation bump already covers it.
        var untrustedFromOrdinal: Int?

        /// Whether ``events`` is in ascending time order, checked once per load.
        ///
        /// The window is found by binary search, which is only correct on sorted
        /// input — and being wrong about it would not look like a crash, it would
        /// look like events missing from a window. Both producers sort
        /// (``LedgerTimelineSource`` explicitly, for reasons its own comments
        /// give), so this should always be true; when it is not, the search falls
        /// back to a full scan rather than quietly dropping history.
        var isSorted = true
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
                try TimelineDerivation.derive(
                    request,
                    events: data.events,
                    gaps: data.gaps,
                    untrustedFromOrdinal: data.untrustedFromOrdinal,
                    isSorted: data.isSorted
                )
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
    func replace(events: [TimelineEvent], gaps: [CoverageGap], trustBoundary: TrustBoundary? = nil) {
        data.events = events
        data.gaps = gaps
        data.untrustedFromOrdinal = trustBoundary?.firstUntrustedOrdinal
        // One pass per load, not per frame. Cheap next to the read that produced
        // the array, and it is what licenses the binary search below.
        data.isSorted = zip(events, events.dropFirst()).allSatisfy { $0.at <= $1.at }
        generation += 1
        _compute.invalidate()
    }

    var dataGeneration: Int { generation }

    /// The derived view of `window`.
    ///
    /// Throws `CancellationError` when the calling task is cancelled, which the
    /// caller treats as "a newer window superseded this one", not as an error.
    func result(window: TimelineWindow, filter: EventFilter) throws -> Result {
        try compute(Request(window: window, filter: filter, dataGeneration: generation))
    }

    /// Cache statistics, so a test can assert the cache is actually working
    /// rather than merely present.
    var cacheStatistics: (hits: Int, misses: Int) { (_compute.hits, _compute.misses) }

    // MARK: - The facet catalogue

    /// How many distinct values a popover offers before it starts saying "and
    /// N more". Chosen to fill a scrolling list without becoming one nobody
    /// reads; the remainder is always stated.
    static let defaultValueLimit = 60

    /// The values `facet` takes in `window`, optionally within one category.
    ///
    /// # Why this is a separate call and not part of ``Result``
    ///
    /// Because it is the expensive half. Counting distinct subjects means
    /// deriving a folder from every event's detail line, and over a
    /// whole-history window that is a quarter of a million string operations —
    /// affordable once, when somebody opens a popover, and not affordable
    /// several times a second while they pan.
    ///
    /// So the hot path computes only what it needs to draw, and this runs on
    /// demand. It is still cancellable, and it still only ever touches the
    /// window's own events.
    func values(
        of facet: EventFacet,
        in kind: EventKind? = nil,
        window: TimelineWindow,
        limit: Int = defaultValueLimit
    ) throws -> FacetValues {
        try values(of: [facet], in: kind, window: window, limit: limit)[0]
    }

    /// Several facets in one pass over the window.
    ///
    /// Opening a chip's disclosure asks for the event types, the sources, and
    /// the subjects of one category at once. Three calls would be three passes
    /// over the same slice for no reason.
    func values(
        of facets: [EventFacet],
        in kind: EventKind? = nil,
        window: TimelineWindow,
        limit: Int = defaultValueLimit
    ) throws -> [FacetValues] {
        var counts = [[String: Int]](repeating: [:], count: facets.count)

        for (offset, event) in slice(from: window.start, to: window.end).enumerated() {
            if offset & 0xFFF == 0 { try Task.checkCancellation() }
            guard kind == nil || event.kind == kind else { continue }
            for (index, facet) in facets.enumerated() {
                let value = facet.value(of: event)
                guard !value.isEmpty else { continue }
                counts[index][value, default: 0] += 1
            }
        }

        try Task.checkCancellation()
        return facets.enumerated().map {
            FacetValues(facet: $1, kind: kind, counts: counts[$0], limit: limit)
        }
    }

    private func slice(from start: Date, to end: Date) -> ArraySlice<TimelineEvent> {
        TimelineDerivation.slice(of: data.events, from: start, to: end, isSorted: data.isSorted)
    }

    // MARK: - The pure part

    /// The events inside `start...end`, inclusive at both ends.
    ///
    /// # Why this is a binary search
    ///
    /// The scan it replaces touched every event in the ledger on every window
    /// change — 250,000 date comparisons several times a second while panning,
    /// to find the few hundred inside a one-hour window. It was survivable while
    /// the filter was one set membership and one substring; with facets,
    /// severity, and a token query it is the difference between a filter that
    /// keeps up with a trackpad and one that does not.
    ///
    /// The array is append-ordered by time (see ``LedgerTimelineSource``), which
    /// is what makes this sound. When it is not — which `isSorted` records at
    /// load time — this falls back to the full range rather than returning a
    /// wrong slice, because a slice that is quietly short is a history with
    /// invisible holes in it.
    nonisolated static func slice(
        of events: [TimelineEvent], from start: Date, to end: Date, isSorted: Bool
    ) -> ArraySlice<TimelineEvent> {
        guard isSorted else { return events[...] }
        let lower = firstIndex(in: events) { $0.at >= start }
        let upper = firstIndex(in: events) { $0.at > end }
        return events[lower..<max(lower, upper)]
    }

    /// The first index whose element satisfies `predicate`, which must be false
    /// for a prefix of the array and true for the rest — `events.count` when
    /// none does.
    private nonisolated static func firstIndex(
        in events: [TimelineEvent], where predicate: (TimelineEvent) -> Bool
    ) -> Int {
        var low = 0
        var high = events.count
        while low < high {
            let middle = low + (high - low) / 2
            if predicate(events[middle]) { high = middle } else { low = middle + 1 }
        }
        return low
    }

    /// `nonisolated static` and pure: it reads only its arguments, which is what
    /// makes memoising it correct.
    private nonisolated static func derive(
        _ request: Request,
        events: [TimelineEvent],
        gaps: [CoverageGap],
        untrustedFromOrdinal: Int?,
        isSorted: Bool
    ) throws -> Result {
        var visible = [TimelineEvent]()
        var counts = [EventKind: Int]()
        var severities = [AlarmSeverity: Int]()
        var passing = [EventKind: Int]()
        var total = 0
        var forcedUntrusted = 0

        // Parsed once per derivation rather than once per event. Over a window
        // holding a quarter of a million records that is the entire cost of the
        // token syntax.
        let query = request.filter.query.parsed
        let filter = request.filter

        let inWindow = slice(of: events, from: request.windowStart, to: request.windowEnd, isSorted: isSorted)

        // Checking cancellation every 4,096 events keeps the check itself off
        // the hot path while still aborting within a frame — at 250,000 events
        // that is sixty checks, not a quarter of a million.
        for (offset, event) in inWindow.enumerated() {
            if offset & 0xFFF == 0 { try Task.checkCancellation() }

            // The slice is only trustworthy when the array was sorted; when it
            // was not it is the whole array, so the bounds still have to be
            // checked. Inclusive at both ends, for the reason on
            // `TimelineWindow.contains`.
            guard event.at >= request.windowStart, event.at <= request.windowEnd else { continue }

            total += 1
            counts[event.kind, default: 0] += 1
            severities[event.severity, default: 0] += 1

            if filter.allows(event, query: query) {
                visible.append(event)
                passing[event.kind, default: 0] += 1
                continue
            }

            // Filtered out — unless it cannot be trusted, in which case it is
            // shown anyway. A filter may decide what happened is uninteresting;
            // it may not decide that a record which fails verification is.
            if let untrustedFromOrdinal, event.record >= untrustedFromOrdinal {
                visible.append(event)
                passing[event.kind, default: 0] += 1
                forcedUntrusted += 1
            }
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
            severityCounts: severities,
            passingCounts: passing,
            totalInWindow: total,
            hiddenInWindow: total - visible.count,
            forcedUntrustedCount: forcedUntrusted,
            gaps: CoverageAnalysis.gaps(gaps, overlapping: window),
            level: ZoomLevel.resolve(window: window, visibleCount: visible.count)
        )
    }
}
