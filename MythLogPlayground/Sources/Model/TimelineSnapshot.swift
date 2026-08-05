import Foundation

/// Everything the interface needs about a ledger, as one value.
///
/// # Why this exists
///
/// `MainPage.Model` used to reach directly for `MockLedger`, which meant the
/// page could only ever render mock data and the design system knew the name of
/// a fixture. `Scripts/check-layering.sh` fails that: `DesignSystem/` may
/// reference `Primitives/` and view models, and nothing else.
///
/// The snapshot is the seam. The page renders a `TimelineSnapshot` and does not
/// know where it came from; ``MockTimelineSource`` produces one for previews and
/// ``LedgerTimelineSource`` produces one from a ledger on disk. Neither is
/// privileged, and swapping them is a change in `MythLogApp` rather than an edit
/// inside the page.
///
/// A `Sendable` value type, so it is built off the main actor — which is where
/// reading a two-year ledger has to happen — and handed over whole. There is no
/// partially-populated intermediate state the UI could render, which matters:
/// a half-loaded history is indistinguishable from a short one.
struct TimelineSnapshot: Equatable, Sendable {
    /// Every retained event, oldest first.
    var events: [TimelineEvent]

    /// Spans with no recording at all, derived from absence. See
    /// ``CoverageAnalysis``.
    var gaps: [CoverageGap]

    /// The extent of the retained history — the outermost the window may zoom.
    var history: ClosedRange<Date>

    /// Records in the whole ledger, which is not `events.count`: the ledger
    /// holds more than the interface retains.
    var totalRecords: Int

    /// Records older than ``history`` that were counted but not kept, because
    /// of ``TimelineLoadRequest/retainedEventLimit``. Surfaced in the header:
    /// showing the newest slice as though it were everything would be the same
    /// class of lie as an undrawn gap.
    var omittedOlderRecords: Int

    /// The first event actually retained, for "since …" in the header.
    var firstRetainedAt: Date?

    /// What verification concluded. `.unverified` is not a synonym for healthy.
    var integrity: IntegrityState

    /// Where this came from, for diagnostics and the human checklist.
    var origin: String

    var isEmpty: Bool { events.isEmpty }

    /// "since 12 Jun", or the honest alternative when nothing was loaded.
    var since: String {
        guard let firstRetainedAt else { return "no records" }
        let prefix = omittedOlderRecords > 0 ? "newest since " : "since "
        return prefix + firstRetainedAt.formatted(.dateTime.day().month(.abbreviated))
    }

    /// An empty history that is *known* to be empty, as opposed to one that
    /// could not be read. The distinction is the point.
    static func empty(origin: String, at now: Date = .now) -> TimelineSnapshot {
        TimelineSnapshot(
            events: [],
            gaps: [],
            history: now.addingTimeInterval(-3600)...now,
            totalRecords: 0,
            omittedOlderRecords: 0,
            firstRetainedAt: nil,
            integrity: .verified(recordCount: 0),
            origin: origin
        )
    }

    /// A history that could not be read. Renders as a loud failure, never as
    /// "nothing happened".
    static func unreadable(origin: String, reason: String, at now: Date = .now) -> TimelineSnapshot {
        TimelineSnapshot(
            events: [],
            gaps: [],
            history: now.addingTimeInterval(-3600)...now,
            totalRecords: 0,
            omittedOlderRecords: 0,
            firstRetainedAt: nil,
            integrity: .unreadable(reason: reason),
            origin: origin
        )
    }
}
