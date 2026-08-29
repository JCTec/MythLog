import SwiftUI

/// The readable history. Slaved to the same window as the timeline — one window
/// drives both, so they can never show different truths.
struct EventList: View {
    var events: [TimelineEvent]
    var window: TimelineWindow
    var gaps: [CoverageGap]
    /// Where trustworthy history ends, when part of it does not verify.
    var trustBoundary: TrustBoundary?
    /// Records in this window a filter is hiding. Stated here as well as in the
    /// banner above the timeline: a reader scrolled halfway down this list has
    /// the banner off screen, and "the newest 60 of 52" must never be the only
    /// number they can see.
    var hiddenByFilter: Int = 0
    var selected: TimelineEvent?
    var newEventTime: String?
    var onSelect: (TimelineEvent) -> Void
    var onJumpToNew: () -> Void

    private let cap = 60

    private var shown: [TimelineEvent] { Array(events.suffix(cap).reversed()) }
    private var isCapped: Bool { events.count > cap }
    /// Gaps that overlap the window. Never filtered — an absence of recording
    /// is not an event, so no filter may hide it.
    private var visibleGaps: [CoverageGap] {
        gaps.filter { $0.end > window.start && $0.start < window.end }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.divider)
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Gaps first, and gaps *always* — including when the filter
                    // has emptied the list. A window whose only content is a
                    // coverage gap is the most important thing this list can
                    // show, and the filter that emptied it must not take it.
                    // Only the first carries the explanation; see
                    // ``CoverageGapBanner``. The rest state the same facts in
                    // one line and expand on request.
                    ForEach(Array(visibleGaps.enumerated()), id: \.element.id) { index, gap in
                        CoverageGapBanner(gap: gap, isFirst: index == 0)
                            .padding(.horizontal, Metrics.space4)
                            .padding(.top, index == 0 ? Metrics.space4 : Metrics.space2)
                            .padding(.bottom, index == visibleGaps.count - 1 ? Metrics.space4 : 0)
                    }
                    if shown.isEmpty { emptyState }
                    ForEach(shown) { event in
                        // The list runs newest first, so the marker goes
                        // immediately *before* the first row that is still
                        // trustworthy — everything above it is not.
                        if let trustBoundary, isFirstTrustedRow(event) {
                            TrustBoundaryMarker(boundary: trustBoundary)
                        }
                        EventRow(
                            event: event,
                            isSelected: selected?.id == event.id,
                            isTrusted: trustBoundary?.trusts(ordinal: event.record) ?? true
                        ) { onSelect(event) }
                    }
                }
            }
        }
        .panelSurface()
    }

    private var header: some View {
        HStack(spacing: Metrics.space3) {
            Text(window.label)
                .font(Typography.rowLabel)
                .foregroundStyle(Palette.textPrimary)

            Text(countLabel)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()

            if hiddenByFilter > 0 {
                Text("· \(hiddenByFilter.formatted()) hidden by filters")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.filtered)
            }

            Spacer()

            if let newEventTime {
                Button(action: onJumpToNew) {
                    HStack(spacing: Metrics.space1) {
                        Image(systemName: "arrow.up").font(.system(size: 10, weight: .semibold))
                        Text("1 new event · \(newEventTime)").font(Typography.caption)
                    }
                    .foregroundStyle(Palette.accent)
                    .pillSurface(fill: Palette.accentDim, stroke: Palette.accentBorder)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("One new event at \(newEventTime). Jump to newest.")
            }
        }
        .padding(.horizontal, Metrics.space4)
        .frame(height: 44)
    }

    /// Nothing to show, and which of the two reasons it is.
    ///
    /// "No records here" and "records here, all of them filtered out" look
    /// identical and mean opposite things. The first is a fact about the
    /// history; the second is a fact about the filter, and an empty list that
    /// does not say which invites the reading this app exists to prevent.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Metrics.space2) {
            if hiddenByFilter > 0 {
                Text("Nothing in this window matches your filter.")
                    .font(Typography.rowLabel)
                    .foregroundStyle(Palette.textPrimary)
                Text(
                    "\(hiddenByFilter.formatted()) record(s) were recorded here and are being hidden. "
                        + "This is not an empty stretch of history."
                )
                .font(Typography.caption)
                .foregroundStyle(Palette.filtered)
            } else {
                Text("No records in this window.")
                    .font(Typography.rowLabel)
                    .foregroundStyle(Palette.textPrimary)
                Text("Nothing was recorded between these two times.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.space4)
    }

    /// The newest row that still verifies — the one the boundary sits above.
    ///
    /// Compared by identity rather than by index so the marker cannot drift if
    /// the row ordering changes.
    private func isFirstTrustedRow(_ event: TimelineEvent) -> Bool {
        guard let trustBoundary else { return false }
        return shown.first { trustBoundary.trusts(ordinal: $0.record) }?.id == event.id
    }

    /// Honest about truncation: never silently drops rows.
    private var countLabel: String {
        // Separated, always. "34396" is a number the eye has to count digits on
        // before it knows whether it is thirty-four thousand or three hundred
        // thousand, and this app's whole scale problem is that those are
        // different situations.
        if isCapped { return "newest \(cap.formatted()) of \(events.count.formatted()) shown" }
        return events.count == 1 ? "1 event" : "\(events.count.formatted()) events"
    }
}
