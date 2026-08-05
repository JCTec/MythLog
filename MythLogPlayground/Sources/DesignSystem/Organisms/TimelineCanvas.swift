import SwiftUI

/// The timeline. It never disappears — it changes what it is made of.
///
/// One component with three renderers, deliberately not three components:
/// selection, the window, and the coverage-gap overlay must behave identically
/// at every level. Splitting them is how the gap hatching and selection drift
/// apart.
struct TimelineCanvas: View {
    var events: [TimelineEvent]
    var window: TimelineWindow
    var gap: CoverageGap
    var level: ZoomLevel
    var selected: TimelineEvent?
    var onSelect: (TimelineEvent) -> Void
    var onZoomTo: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space2) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    gapOverlay(width: geo.size.width, height: geo.size.height)

                    switch level {
                    case .density: density(size: geo.size)
                    case .clusters: clusters(size: geo.size)
                    case .events: nodes(size: geo.size)
                    }

                    axisLine(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(height: Metrics.timelineHeight)

            axisLabels
        }
    }

    // MARK: - Shared chrome

    /// Drawn beneath every level and never filterable. An absence of recording
    /// is not an event, so no filter may hide it.
    @ViewBuilder
    private func gapOverlay(width: CGFloat, height: CGFloat) -> some View {
        let l = window.fraction(of: gap.start)
        let r = window.fraction(of: gap.end)
        if r > 0, l < 1 {
            let x = max(0, l) * width
            let w = (min(1, r) - max(0, l)) * width
            ZStack {
                HatchFill()
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Palette.textQuiet.opacity(0.7))
                if w > 150 {
                    Text(gap.label)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Metrics.space3)
                        .frame(height: 22)
                        .background(Capsule().fill(Palette.surface))
                        .overlay(Capsule().strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                }
            }
            .frame(width: w, height: height - Metrics.timelineAxisInset)
            .offset(x: x)
            .accessibilityLabel(gap.label)
        }
    }

    private func axisLine(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Palette.divider)
            .frame(height: 1)
            .offset(y: height - Metrics.timelineAxisInset)
            .accessibilityHidden(true)
    }

    private var axisLabels: some View {
        HStack(spacing: 0) {
            ForEach(ticks, id: \.self) { tick in
                Text(tick.clockText)
                    .font(Typography.axisLabel)
                    .foregroundStyle(Palette.textQuiet)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }

    private var ticks: [Date] {
        let count = 5
        return (0..<count).map { window.start.addingTimeInterval(window.span * Double($0) / Double(count)) }
    }
}
