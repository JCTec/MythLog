import Observation
import SwiftUI

extension MainPage {
    /// Nested rather than `MainPageViewModel`, so the type reads as what it is:
    /// this page's model, referenced as `MainPage.Model`.
    ///
    /// It *projects* — it owns window, selection, and filters, and derives
    /// everything else from one source. It does not load data independently,
    /// because timeline, list, and counts disagreeing would be worse than any
    /// amount of verbosity in an app whose claim is a consistent record.
    ///
    /// The data arrives as a ``TimelineSnapshot`` from outside. The page has no
    /// idea whether it came from a fixture or from a ledger on disk, which is
    /// what lets the design work stay deterministic while the app reads real
    /// history — and what `Scripts/check-layering.sh` enforces.
    @MainActor
    @Observable
    final class Model {
        private(set) var snapshot: TimelineSnapshot
        var window: TimelineWindow
        var enabledKinds: Set<EventKind> = Set(EventKind.allCases)
        var selected: TimelineEvent?
        var query: String = ""

        var integrity: IntegrityState { snapshot.integrity }

        static let presets: [(label: String, span: TimeInterval)] = [
            ("24h", 24 * 3600), ("6h", 6 * 3600), ("1h", 3600), ("15m", 900),
        ]

        init(snapshot: TimelineSnapshot) {
            self.snapshot = snapshot
            window = TimelineWindow(start: snapshot.history.lowerBound, end: snapshot.history.upperBound)
            selected = snapshot.events.last
        }

        // MARK: - Derivation

        /// Everything below is a projection of one window over one dataset.
        var eventsInWindow: [TimelineEvent] {
            snapshot.events.filter { window.contains($0.at) }
        }

        var visibleEvents: [TimelineEvent] {
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            return eventsInWindow.filter { event in
                guard enabledKinds.contains(event.kind) else { return false }
                guard !q.isEmpty else { return true }
                return "\(event.label) \(event.detail) \(event.source)".lowercased().contains(q)
            }
        }

        /// Window-scoped, so counts recompute on every zoom — they describe what
        /// is on screen, not a static total.
        var counts: [EventKind: Int] {
            var out: [EventKind: Int] = [:]
            for event in eventsInWindow { out[event.kind, default: 0] += 1 }
            return out
        }

        var level: ZoomLevel {
            ZoomLevel.resolve(window: window, visibleCount: visibleEvents.count)
        }

        var activePreset: String? {
            Self.presets.first { abs($0.span - window.span) < 60 }?.label
        }

        // MARK: - Intent

        func toggle(_ kind: EventKind) {
            if enabledKinds.contains(kind) { enabledKinds.remove(kind) } else { enabledKinds.insert(kind) }
        }

        var history: ClosedRange<Date> { snapshot.history }

        var canZoomIn: Bool { window.span > TimelineWindow.minimumSpan }
        var canZoomOut: Bool {
            window.span < history.upperBound.timeIntervalSince(history.lowerBound)
        }

        func zoomIn() { window = window.zoomed(by: 0.5, limit: history) }
        func zoomOut() { window = window.zoomed(by: 2, limit: history) }

        func resetZoom() {
            window = TimelineWindow(start: history.lowerBound, end: history.upperBound)
        }

        func zoom(to date: Date) {
            window = TimelineWindow.centred(
                on: date,
                span: max(TimelineWindow.minimumSpan, window.span / 4),
                limit: history
            )
        }

        func apply(preset span: TimeInterval) {
            window = TimelineWindow.centred(
                on: history.upperBound.addingTimeInterval(-span / 2),
                span: span,
                limit: history
            )
        }
    }
}
