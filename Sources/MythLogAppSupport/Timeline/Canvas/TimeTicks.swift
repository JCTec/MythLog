import SwiftUI

struct TimeTicks: View {
    let records: [TimelineDisplayRecord]
    let contentWidth: CGFloat
    let spineY: CGFloat

    @ScaledMetric(relativeTo: .caption2) private var overflowBadgeFontSize: CGFloat = 9
    @ScaledMetric(relativeTo: .caption2) private var tickMarkHeight: CGFloat = 11

    private var ticks: [TimelineTickLabel] {
        TimelineTickPlanner(contentWidth: contentWidth).labels(for: records.map(\.timestamp))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(ticks) { tick in
                VStack(spacing: 5) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.32))
                        .frame(width: 1, height: tickMarkHeight)
                    HStack(spacing: 4) {
                        Text(tick.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if tick.count > 1 {
                            Text("+\(tick.count - 1)")
                                .font(.system(size: overflowBadgeFontSize, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                        }
                    }
                    .fixedSize()
                }
                .position(x: tick.x, y: spineY + 24)
            }
        }
        .allowsHitTesting(false)
        // Axis labels restate timestamps each event node already speaks, so they would only add
        // dozens of redundant VoiceOver stops between events.
        .accessibilityHidden(true)
    }
}
