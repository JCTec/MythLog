import SwiftUI

/// The readable history. Slaved to the same window as the timeline — one window
/// drives both, so they can never show different truths.
struct EventList: View {
    var events: [TimelineEvent]
    var window: TimelineWindow
    var gaps: [CoverageGap]
    /// Where trustworthy history ends, when part of it does not verify.
    var trustBoundary: TrustBoundary?
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
                    ForEach(visibleGaps) { gap in
                        CoverageGapBanner(gap: gap).padding(Metrics.space4)
                    }
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
        if isCapped { return "newest \(cap) of \(events.count) shown" }
        return events.count == 1 ? "1 event" : "\(events.count) events"
    }
}
