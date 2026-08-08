import Observation
import SwiftUI

extension MainPage {
    /// Nested rather than `MainPageViewModel`, so the type reads as what it is:
    /// this page's model, referenced as `MainPage.Model`.
    ///
    /// It *projects* — it owns window, selection, and filters, and everything
    /// else is derived from one dataset. Timeline, list, and counts disagreeing
    /// would be worse than any amount of verbosity in an app whose claim is a
    /// consistent record.
    ///
    /// # What changed when the data became real
    ///
    /// The derived values used to be computed properties on this `@MainActor`
    /// class. Over a 340-event fixture that is free. Over a real ledger it is a
    /// visible stutter: filtering and counting a quarter of a million events
    /// runs on every window change, and window changes arrive several times a
    /// second while a zoom key is held.
    ///
    /// So derivation moved to ``TimelineDerivation``, an actor. This class holds
    /// the *result*, launches the work, and — the part that matters — cancels
    /// the previous computation before starting the next one. Without that,
    /// holding ⌘− queues a dozen full passes over the history and every one of
    /// them runs to completion for a window nobody is looking at any more.
    ///
    /// # What changed when the filter grew past six chips
    ///
    /// One value, ``filter``, holds every constraint. Chips, popovers, presets,
    /// saved filters, and the search box all write to it and nothing else, so
    /// there is exactly one answer to "what am I hiding" and the filter bar can
    /// state it without reconstructing it from four places.
    @MainActor
    @Observable
    final class Model {
        private(set) var snapshot: TimelineSnapshot
        private(set) var derived: TimelineDerivation.Result
        private(set) var isLoading = false
        private(set) var loadStage: String?

        var window: TimelineWindow
        var selected: TimelineEvent?

        /// Everything being hidden, as one value.
        ///
        /// `didSet` rather than an intent method per control: presets, saved
        /// filters, the popovers, and the search box all mutate this, and every
        /// one of them has to re-derive, re-offer the popover's values, and
        /// remember the new state. Routing that through one observer is the only
        /// version where a new control cannot forget a step.
        var filter = EventFilter() {
            didSet { if filter != oldValue { filterChanged() } }
        }

        /// The search box's text. A window onto ``filter`` rather than a second
        /// place the query lives — a `TextField` needs a `Binding`, and two
        /// stored copies of the same string is how a search box ends up
        /// disagreeing with the filter it drives.
        var query: String {
            get { filter.query.text }
            set { filter.query.text = newValue }
        }

        var integrity: IntegrityState { snapshot.integrity }
        var history: ClosedRange<Date> { snapshot.history }

        static let presets: [(label: String, span: TimeInterval)] = [
            ("7d", 7 * 86400), ("24h", 24 * 3600), ("6h", 6 * 3600), ("1h", 3600),
        ]

        private let source: any TimelineSource
        private let request: TimelineLoadRequest
        private let derivation = TimelineDerivation()
        private let filterStore: SavedFilterStore

        /// The in-flight derivation. Cancelled and replaced on every change; see
        /// the note above about what happens without that.
        ///
        /// Unstructured on purpose: it has to outlive the `refresh()` call that
        /// started it and be cancellable by the *next* one, which is precisely
        /// what structured concurrency does not offer. The load is the opposite
        /// case and is structured — see ``load()``.
        private var derivationTask: Task<Void, Never>?
        /// The in-flight facet-value derivation, cancelled the same way. Kept
        /// separate from `derivationTask` because the expensive one must not be
        /// able to cancel the one that draws the timeline.
        private var facetTask: Task<Void, Never>?

        init(
            source: any TimelineSource,
            request: TimelineLoadRequest = TimelineLoadRequest(),
            filterStore: SavedFilterStore = SavedFilterStore()
        ) {
            self.source = source
            self.request = request
            self.filterStore = filterStore
            // Starts empty rather than pretending: the header shows "Verifying…"
            // until a real load says otherwise. `.unverified` is deliberately
            // not `.verified(recordCount: 0)` — a ledger nobody has checked is
            // not a ledger that passed.
            var initial = TimelineSnapshot.empty(origin: source.describedOrigin)
            initial.integrity = .unverified
            snapshot = initial
            derived = .empty
            window = TimelineWindow(showingAllOf: initial.history)
            savedFilters = filterStore.saved()

            // Restored, and therefore announced. See ``SavedFilterStore`` for
            // why restoring at all is defensible only alongside the notice.
            if let active = filterStore.active(), active.filter.isFiltering {
                filter = active.filter
                restored = RestoredFilterNotice(savedAs: active.savedAs, filter: active.filter)
            }
        }

        // MARK: - Loading

        /// Loads the history.
        ///
        /// `async` and structured rather than a fire-and-forget `Task`, so
        /// SwiftUI's `.task` modifier owns its lifetime: closing the window
        /// during a two-year read cancels the read. An unstructured task would
        /// keep going, and there is nowhere to cancel it from — `deinit` on a
        /// `@MainActor` class is nonisolated and cannot touch isolated state.
        func load() async {
            isLoading = true
            loadStage = "Reading the ledger"
            defer {
                isLoading = false
                loadStage = nil
            }

            do {
                // Off the main actor: `source` is `Sendable` and `load` is
                // nonisolated, so the read and the mapping happen on the
                // cooperative pool while the interface stays responsive.
                let snapshot = try await source.load(request)
                try Task.checkCancellation()
                await apply(snapshot)
            } catch is CancellationError {
                // Superseded, or the window closed. Nothing to report.
            } catch {
                await apply(
                    .unreadable(
                        origin: source.describedOrigin,
                        reason: (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                    ))
            }
        }

        private func apply(_ snapshot: TimelineSnapshot) async {
            // Read before the snapshot is replaced: both answers describe the
            // window the user was looking at, not the one they are about to get.
            let wasFirstLoad = self.snapshot.isEmpty
            let wasLive = window.isAtEnd
            let previous = window
            let keptOrdinal = selected?.record

            self.snapshot = snapshot
            isLoading = false
            loadStage = nil

            window = nextWindow(for: snapshot, after: previous, wasFirstLoad: wasFirstLoad, wasLive: wasLive)
            // Selection survives a reload when the record does. Matched on the
            // ledger ordinal, not on `id`: a `TimelineEvent`'s identity is a
            // fresh UUID minted during mapping, so the "same" record is a
            // different value every time the ledger is read.
            selected = keptOrdinal.flatMap { ordinal in
                snapshot.events.first { $0.record == ordinal }
            } ?? snapshot.events.last

            // The boundary goes with the data: it is what lets the derivation
            // refuse to let a filter hide a record that failed verification.
            await derivation.replace(
                events: snapshot.events, gaps: snapshot.gaps, trustBoundary: trustBoundary)
            refresh()
        }

        /// Where to put the window when new data arrives.
        ///
        /// Three cases, and the distinction between the last two is the whole
        /// point of having a live edge at all:
        ///
        /// - **First load** — show everything. There is no position to keep.
        /// - **Was live** — pin to the new right edge at the same span, so
        ///   records written since the last read flow in.
        /// - **Was reading history** — hold position. Someone examining a
        ///   Tuesday in March did not ask to be moved to now because the
        ///   recorder wrote a heartbeat.
        private func nextWindow(
            for snapshot: TimelineSnapshot,
            after previous: TimelineWindow,
            wasFirstLoad: Bool,
            wasLive: Bool
        ) -> TimelineWindow {
            guard !wasFirstLoad else { return TimelineWindow(showingAllOf: snapshot.history) }
            if wasLive { return TimelineWindow(history: snapshot.history, mostRecent: previous.span) }
            return TimelineWindow(
                history: snapshot.history,
                centredOn: previous.start.addingTimeInterval(previous.span / 2),
                span: previous.span
            )
        }

        // MARK: - Derivation

        /// Recomputes everything the window implies, cancelling whatever was
        /// already running.
        func refresh() {
            derivationTask?.cancel()

            let window = self.window
            let filter = self.filter
            let derivation = self.derivation

            derivationTask = Task { [weak self] in
                do {
                    let result = try await derivation.result(window: window, filter: filter)
                    guard !Task.isCancelled else { return }
                    self?.derived = result
                } catch {
                    // The only thing `derive` throws is `CancellationError`, and
                    // a superseded window has no result worth showing.
                }
            }

            refreshFacetValues()
        }

        private func filterChanged() {
            refresh()
            filterStore.rememberActive(
                SavedFilterStore.Active(filter: filter, savedAs: activeSavedFilter))
        }

        // MARK: - Intent

        /// Re-runs the load, which re-verifies. The banner's primary action on
        /// every state but `.anchorOffline`.
        func reverify() async {
            await load()
        }

        func toggle(_ kind: EventKind) {
            filter.toggle(kind)
        }

        /// Everything back. The one action every filtered state must offer, from
        /// wherever the user is looking.
        func showEverything() {
            activeSavedFilter = nil
            restored = nil
            presetNotice = nil
            filter = EventFilter()
        }

        func zoomIn() { setWindow(window.zoomed(by: 0.5)) }
        func zoomOut() { setWindow(window.zoomed(by: 2)) }
        func resetZoom() { setWindow(TimelineWindow(showingAllOf: history)) }

        func zoom(to date: Date) {
            setWindow(window.centred(on: date, span: max(TimelineWindow.minimumSpan, window.span / 4)))
        }

        func apply(preset span: TimeInterval) {
            setWindow(TimelineWindow(history: history, mostRecent: span))
        }

        // MARK: - Panning

        /// A quarter of the visible span per keypress.
        ///
        /// Chosen so three-quarters of what you were looking at is still on
        /// screen afterwards. A full window per press is a jump — nothing
        /// carries over, and the eye has to re-find its place from scratch; an
        /// eighth is too little to be worth the keystroke at any span. A
        /// quarter also means four presses cross the window exactly, which is a
        /// rhythm you can feel rather than count.
        static let panFraction = 0.25

        func panEarlier() { setWindow(window.panned(by: -window.span * Self.panFraction)) }
        func panLater() { setWindow(window.panned(by: window.span * Self.panFraction)) }

        /// Panning by a distance measured in points, for the trackpad. The view
        /// converts from points to seconds because only the view knows how wide
        /// it is drawn.
        func pan(bySeconds seconds: TimeInterval) {
            setWindow(window.panned(by: seconds))
        }

        func jumpToStart() { setWindow(window.pannedToStart) }

        /// The "1 new event" affordance: go to the newest record *and* re-attach
        /// to the live edge. Selecting a record the window does not contain
        /// would answer half the request.
        ///
        /// The selection comes from the snapshot rather than from
        /// ``visibleEvents``, which describes the window that is being left.
        func jumpToNewest() {
            selected = snapshot.events.last
            jumpToNow()
        }

        /// Re-attaches to the live edge. The state is visible in
        /// ``HistoryPositionBar``, because "I am watching now" and "I am reading
        /// history" are different situations and an interface that looks the
        /// same in both is lying by omission.
        func jumpToNow() { setWindow(window.pannedToNow) }

        /// Drag on the position bar: put the window's start at `fraction` of the
        /// way through the history.
        func scrub(toFraction fraction: Double) {
            setWindow(window.positioned(atFraction: fraction))
        }

        /// Moves the window until the selected event is inside it, keeping the
        /// span. The way back from "I panned away from what I was reading".
        func revealSelection() {
            guard let selected else { return }
            setWindow(window.centred(on: selected.at, span: window.span))
        }

        // MARK: - Selection stepping

        /// ⌥← / ⌥→ move the *selection*; ← / → move the *window*. They are
        /// deliberately different operations on different things, and the
        /// modifier is what says which: panning changes what you can see,
        /// stepping changes what you are looking at. Neither implies the other —
        /// panning past the selected event does not deselect it, and stepping
        /// the selection does not move the window.
        ///
        /// Stepping walks the events that are actually on screen, in time order,
        /// and clamps at both ends rather than wrapping. With the selection
        /// off-screen — which panning can arrange — the next step lands on the
        /// nearest visible end rather than doing nothing.
        func selectPreviousEvent() { step(by: -1) }
        func selectNextEvent() { step(by: 1) }

        private func step(by offset: Int) {
            let events = visibleEvents
            guard !events.isEmpty else { return }

            guard let current = selected, let index = events.firstIndex(where: { $0.id == current.id }) else {
                selected = offset < 0 ? events.last : events.first
                return
            }
            selected = events[min(max(index + offset, 0), events.count - 1)]
        }

        private func setWindow(_ new: TimelineWindow) {
            guard new != window else { return }
            window = new
            refresh()
        }

        // MARK: - Presentation

        var canZoomIn: Bool { !window.isFullyZoomedIn }
        var canZoomOut: Bool { !window.isFullyZoomedOut }

        var canPanEarlier: Bool { window.canPanEarlier }
        var canPanLater: Bool { window.canPanLater }

        /// True when the window sits at the newest end of the history, which is
        /// where records arriving now would appear.
        var isFollowingLive: Bool { window.isAtEnd }

        /// Whether the selected event is outside the window.
        ///
        /// Panning does not clear the selection — the inspector keeps showing
        /// the record, because a record you panned away from is usually a record
        /// you are still thinking about. It does say so, though: a panel
        /// describing something not on screen, with nothing marking it as such,
        /// is how a user ends up believing they are looking at the wrong record.
        var isSelectionOffscreen: Bool {
            guard let selected else { return false }
            return !window.contains(selected.at)
        }

        var activePreset: String? {
            Self.presets.first { abs($0.span - window.span) < 60 }?.label
        }

        /// Where trustworthy history ends. Derived once, here, so the banner,
        /// the list, the timeline, and the inspector cannot disagree about it.
        var trustBoundary: TrustBoundary? {
            TrustBoundary.resolve(integrity: integrity, events: snapshot.events)
        }

        var visibleEvents: [TimelineEvent] { derived.visibleEvents }
        var counts: [EventKind: Int] { derived.counts }
        var passingCounts: [EventKind: Int] { derived.passingCounts }
        var gaps: [CoverageGap] { derived.gaps }
        var level: ZoomLevel { derived.level }

        /// The categories currently shown, which is the shape the rest of the
        /// app spoke in before facets existed.
        var enabledKinds: Set<EventKind> { filter.enabledKinds }

        /// How many records in this window the filter is hiding.
        var hiddenInWindow: Int { derived.hiddenInWindow }

        /// Records on screen only because they cannot be trusted. Non-zero means
        /// the interface owes the user a sentence, not a silent inconsistency
        /// between the filter and what is drawn.
        var forcedUntrustedCount: Int { derived.forcedUntrustedCount }

        /// The whole filtered state as one line, for VoiceOver.
        var filterSummary: String {
            guard filter.isFiltering else { return "No filter is active. Showing everything in this window." }
            return "\(filter.summarySentence) \(hiddenInWindow.formatted()) of "
                + "\(derived.totalInWindow.formatted()) records in this window are hidden."
        }

        // MARK: - Facet values, on demand

        /// Which category's detail is open, if any.
        private(set) var openCategory: EventKind?
        /// The values that category's events take, derived from the window.
        private(set) var categoryDetail: [FacetValues] = []

        /// Severities present in the window, so the control offers what exists.
        /// Comes off the derivation's own pass — see the note on
        /// ``TimelineDerivation/Result/severityCounts``.
        var severityCounts: [AlarmSeverity: Int] { derived.severityCounts }

        func openDetail(for kind: EventKind) {
            openCategory = openCategory == kind ? nil : kind
            categoryDetail = []
            refreshFacetValues()
        }

        func closeDetail() {
            openCategory = nil
            categoryDetail = []
            facetTask?.cancel()
        }

        /// Re-derives what the open popover offers.
        ///
        /// Called from ``refresh()`` as well as on open, because the window can
        /// move under an open popover and a list of values from a window nobody
        /// is looking at is worse than no list.
        ///
        /// **Only while a popover is open.** This is the expensive derivation —
        /// it builds a subject string from every event in the window — and
        /// running it on every pan for a panel nobody has opened would be a
        /// second full pass over the history for nothing.
        private func refreshFacetValues() {
            facetTask?.cancel()
            guard let kind = openCategory else { return }

            let window = self.window
            let derivation = self.derivation

            facetTask = Task { [weak self] in
                do {
                    let values = try await derivation.values(
                        of: EventFacet.detail, in: kind, window: window)
                    guard !Task.isCancelled else { return }
                    self?.categoryDetail = values
                } catch {
                    // Cancelled by a newer window. The stale list stays until the
                    // new one arrives, which is better than blanking the popover
                    // under the pointer on every pan.
                }
            }
        }

        // MARK: - Facet intent

        func setState(_ state: FacetSelection.ValueState, for value: String, in facet: EventFacet) {
            var selection = filter[facet]
            switch state {
            case .included: selection.include(value)
            case .excluded: selection.exclude(value)
            case .allowed, .notIncluded: selection.clear(value)
            }
            filter[facet] = selection
        }

        func clear(_ facet: EventFacet) {
            filter[facet] = FacetSelection()
        }

        func remove(_ removal: FilterConstraint.Removal) {
            filter.remove(removal)
        }

        var minimumSeverity: AlarmSeverity? {
            get { filter.minimumSeverity }
            set { filter.minimumSeverity = newValue }
        }

        // MARK: - Presets

        /// What the last applied preset expanded to, until something else
        /// changes. Shown so a preset teaches the filter model rather than
        /// hiding it — and so a preset that matched nothing says so instead of
        /// looking like a filter that did nothing.
        private(set) var presetNotice: FilterPreset.Resolution?

        func apply(_ preset: FilterPreset) async {
            let types: FacetValues
            do {
                // A high cap: preset resolution is not a list somebody reads, so
                // truncating it would silently narrow the expansion. The number
                // of distinct event types in any window is small.
                types = try await derivation.values(of: .type, window: window, limit: 1_000)
            } catch {
                return
            }

            let resolution = preset.resolved(against: types)
            presetNotice = resolution
            guard !resolution.foundNothing else { return }

            activeSavedFilter = nil
            restored = nil
            filter = resolution.filter
        }

        func dismissPresetNotice() { presetNotice = nil }

        /// Field names in the search box that are not filters.
        ///
        /// Reported rather than swallowed. `sevrity:>=warning` matches nothing,
        /// and an empty timeline with no explanation is exactly the reading this
        /// app must never invite — see ``FilterQuery``.
        var queryProblems: [String] { filter.query.parsed.unrecognisedFields }

        // MARK: - Saved filters

        private(set) var savedFilters: [SavedFilter] = []
        /// The saved filter the current state came from, when it came from one
        /// and has not been edited since.
        private(set) var activeSavedFilter: SavedFilter?

        func saveCurrentFilter(named name: String) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, filter.isFiltering else { return }
            let saved = SavedFilter(name: trimmed, filter: filter)
            filterStore.save(saved)
            savedFilters = filterStore.saved()
            activeSavedFilter = saved
            filterStore.rememberActive(SavedFilterStore.Active(filter: filter, savedAs: saved))
        }

        func apply(_ saved: SavedFilter) {
            restored = nil
            presetNotice = nil
            // Before `filter` — its `didSet` is what persists the active state,
            // and it has to record this one as named rather than as anonymous.
            activeSavedFilter = saved
            filter = saved.filter
        }

        func delete(_ saved: SavedFilter) {
            filterStore.delete(saved.id)
            savedFilters = filterStore.saved()
            if activeSavedFilter?.id == saved.id { activeSavedFilter = nil }
        }

        // MARK: - The restored-filter notice

        private(set) var restored: RestoredFilterNotice?

        /// "Yes, I know" — the notice goes, the filter stays.
        func acknowledgeRestoredFilter() { restored = nil }
    }
}

extension TimelineDerivation.Result {
    /// Before the first derivation completes. Empty, and honestly so — the
    /// header says "Verifying…" rather than "0 events".
    static let empty = TimelineDerivation.Result(
        visibleEvents: [],
        counts: [:],
        severityCounts: [:],
        passingCounts: [:],
        totalInWindow: 0,
        hiddenInWindow: 0,
        forcedUntrustedCount: 0,
        gaps: [],
        level: .density)
}
