import SwiftUI

struct TimelineEventNodeIcon: View {
    let displayRecord: TimelineDisplayRecord
    let prominence: TimelineProminence
    let selected: Bool
    let hovering: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Deliberately not scaled. `prominence.circleSize` is the same value the layout engine used
        // to reserve lanes and score placements off the main thread, so growing the drawn node here
        // would make it overlap neighbours the engine believed were clear. The glyph stays
        // proportional to that node. Everything readable about the event — its label caption, and
        // its full VoiceOver description — does scale.
        let size = max(prominence.circleSize, 16)
        let presentation = displayRecord.presentation

        ZStack {
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: size + 8, height: size + 8)

            Circle()
                .fill(presentation.tintColor.opacity(displayRecord.hiddenBySearch ? 0.62 : prominence.opacity))
                .frame(width: size, height: size)

            Circle()
                .stroke(
                    displayRecord.event.severity.timelineColor.opacity(selected ? 1 : 0.85),
                    lineWidth: displayRecord.event.severity >= .warning ? 2.6 : 1.2
                )
                .frame(width: size + 3, height: size + 3)

            Image(systemName: presentation.symbolName)
                .font(.system(size: max(size * 0.42, 8), weight: .semibold))
                .foregroundStyle(.white)

            if let badgeSymbolName = displayRecord.event.severity.timelineBadgeSymbolName {
                severityBadge(symbolName: badgeSymbolName, nodeSize: size)
            }
        }
        .shadow(color: selected ? presentation.tintColor.opacity(0.38) : .clear, radius: 12, y: 3)
        .scaleEffect(ReducedMotion.scale(selected ? 1.08 : hovering ? 1.04 : 1, reduceMotion: reduceMotion))
        .animation(
            ReducedMotion.animation(.spring(response: 0.24, dampingFraction: 0.78), reduceMotion: reduceMotion),
            value: selected
        )
        .animation(
            ReducedMotion.animation(.easeOut(duration: 0.12), reduceMotion: reduceMotion),
            value: hovering
        )
        .opacity(displayRecord.hiddenBySearch ? 0.7 : 1)
    }

    /// Warning and critical differ only in ring hue, which vanishes on a grayscale display. The badge
    /// gives them distinct silhouettes — a circle and a triangle — that survive any color filter.
    ///
    /// `offset` is a draw-time transform, so the badge overhangs the node rim without changing the
    /// size the layout engine reserved for it.
    private func severityBadge(symbolName: String, nodeSize: CGFloat) -> some View {
        let badgeSize = max(nodeSize * 0.44, 9)

        return Image(systemName: symbolName)
            .font(.system(size: badgeSize, weight: .bold))
            .foregroundStyle(displayRecord.event.severity.timelineColor)
            .background {
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .frame(width: badgeSize + 3, height: badgeSize + 3)
            }
            .offset(x: nodeSize * 0.42, y: -nodeSize * 0.42)
    }
}
