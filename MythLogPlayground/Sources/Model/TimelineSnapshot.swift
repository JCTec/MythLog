import Foundation

/// Everything the interface needs about a ledger, as one value.
///
/// # Why this exists
///
/// Until now `MainPage.Model` reached directly for `MockLedger`, which meant the
/// page could only ever render mock data and the design system knew the name of
/// a fixture. `Scripts/check-layering.sh` fails that: `DesignSystem/` may
/// reference `Primitives/` and view models, and nothing else.
///
/// The snapshot is the seam. The page renders a `TimelineSnapshot` and does not
/// know or care where it came from; `MockLedger` produces one for previews and
/// design work, and the real loader produces one from a ledger on disk. Neither
/// is privileged, and swapping them is a change at the call site in
/// `MythLogApp` rather than an edit inside the page.
///
/// A `Sendable` value type, so it can be built off the main actor — which is
/// where reading a two-year ledger has to happen — and handed to the main actor
/// whole, with no partially-populated intermediate state the UI could render.
struct TimelineSnapshot: Equatable, Sendable {
    /// Every event in the loaded span, oldest first.
    var events: [TimelineEvent]

    /// A span with no recording at all. Never mistakable for a quiet period, and
    /// never hideable by a filter.
    var gap: CoverageGap

    /// The full extent of the history — the outermost the window may zoom.
    var history: ClosedRange<Date>

    /// Records in the whole ledger, which is not the same as `events.count`:
    /// the ledger holds more than the interface loads.
    var totalRecords: Int

    /// "since Jun 12" — how far back the record goes, for the header.
    var since: String

    /// What verification concluded. `.verified` is not a default to fall back on;
    /// a ledger that has not been checked yet is not a verified one.
    var integrity: IntegrityState

    var isEmpty: Bool { events.isEmpty }
}
