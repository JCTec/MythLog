import SwiftUI

/// The readable history. Slaved to the same window as the timeline — one window
/// drives both, so they can never show different truths.
struct EventList: View {
    var events: [TimelineEvent]
    var window: TimelineWindow
    var gap: CoverageGap
    var selected: TimelineEvent?
    var newEventTime: String?
    var onSelect: (TimelineEvent) -> Void
    var onJumpToNew: () -> Void

    private let cap = 60

    private var shown: [TimelineEvent] { Array(events.suffix(cap).reversed()) }
    private var isCapped: Bool { events.count > cap }
    private var gapVisible: Bool {
        window.fraction(of: gap.end) > 0 && window.fraction(of: gap.start) < 1
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.divider)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if gapVisible { CoverageGapBanner(gap: gap).padding(Metrics.space4) }
                    ForEach(shown) { event in
                        EventRow(event: event, isSelected: selected?.id == event.id) { onSelect(event) }
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

    /// Honest about truncation: never silently drops rows.
    private var countLabel: String {
        if isCapped { return "newest \(cap) of \(events.count) shown" }
        return events.count == 1 ? "1 event" : "\(events.count) events"
    }
}
