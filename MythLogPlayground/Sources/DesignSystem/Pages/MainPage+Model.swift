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
    @MainActor
    @Observable
    final class Model {
        private(set) var snapshot: TimelineSnapshot
        private(set) var derived: TimelineDerivation.Result
        private(set) var isLoading = false
        private(set) var loadStage: String?

        var window: TimelineWindow
        var enabledKinds: Set<EventKind> = Set(EventKind.allCases)
        var selected: TimelineEvent?
        var query: String = "" {
            didSet { if query != oldValue { refresh() } }
        }

        var integrity: IntegrityState { snapshot.integrity }
        var history: ClosedRange<Date> { snapshot.history }

        static let presets: [(label: String, span: TimeInterval)] = [
            ("7d", 7 * 86400), ("24h", 24 * 3600), ("6h", 6 * 3600), ("1h", 3600),
        ]

        private let source: any TimelineSource
        private let request: TimelineLoadRequest
        private let derivation = TimelineDerivation()

        /// The in-flight derivation. Cancelled and replaced on every change; see
        /// the note above about what happens without that.
        ///
        /// Unstructured on purpose: it has to outlive the `refresh()` call that
        /// started it and be cancellable by the *next* one, which is precisely
        /// what structured concurrency does not offer. The load is the opposite
        /// case and is structured — see ``load()``.
        private var derivationTask: Task<Void, Never>?

        init(source: any TimelineSource, request: TimelineLoadRequest = TimelineLoadRequest()) {
            self.source = source
            self.request = request
            // Starts empty rather than pretending: the header shows "Verifying…"
            // until a real load says otherwise. `.unverified` is deliberately
            // not `.verified(recordCount: 0)` — a ledger nobody has checked is
            // not a ledger that passed.
            var initial = TimelineSnapshot.empty(origin: source.describedOrigin)
            initial.integrity = .unverified
            snapshot = initial
            derived = .empty
            window = TimelineWindow(showingAllOf: initial.history)
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
            self.snapshot = snapshot
            isLoading = false
            loadStage = nil

            window = TimelineWindow(showingAllOf: snapshot.history)
            selected = snapshot.events.last

            await derivation.replace(events: snapshot.events, gaps: snapshot.gaps)
            refresh()
        }

        // MARK: - Derivation

        /// Recomputes everything the window implies, cancelling whatever was
        /// already running.
        func refresh() {
            derivationTask?.cancel()

            let window = self.window
            let kinds = enabledKinds
            let query = self.query
            let derivation = self.derivation

            derivationTask = Task { [weak self] in
                do {
                    let result = try await derivation.result(
                        window: window, enabledKinds: kinds, query: query)
                    guard !Task.isCancelled else { return }
                    self?.derived = result
                } catch {
                    // The only thing `derive` throws is `CancellationError`, and
                    // a superseded window has no result worth showing.
                }
            }
        }

        // MARK: - Intent

        /// Re-runs the load, which re-verifies. The banner's primary action on
        /// every state but `.anchorOffline`.
        func reverify() async {
            await load()
        }

        func toggle(_ kind: EventKind) {
            if enabledKinds.contains(kind) { enabledKinds.remove(kind) } else { enabledKinds.insert(kind) }
            refresh()
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

        private func setWindow(_ new: TimelineWindow) {
            guard new != window else { return }
            window = new
            refresh()
        }

        // MARK: - Presentation

        var canZoomIn: Bool { !window.isFullyZoomedIn }
        var canZoomOut: Bool { !window.isFullyZoomedOut }

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
        var gaps: [CoverageGap] { derived.gaps }
        var level: ZoomLevel { derived.level }
    }
}

extension TimelineDerivation.Result {
    /// Before the first derivation completes. Empty, and honestly so — the
    /// header says "Verifying…" rather than "0 events".
    static let empty = TimelineDerivation.Result(
        visibleEvents: [], counts: [:], totalInWindow: 0, gaps: [], level: .density)
}
