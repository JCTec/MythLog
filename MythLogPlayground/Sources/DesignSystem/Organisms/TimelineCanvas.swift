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
    var gaps: [CoverageGap]
    /// Where trustworthy history ends, when part of it does not verify.
    var trustBoundary: TrustBoundary?
    var level: ZoomLevel
    var selected: TimelineEvent?
    var onSelect: (TimelineEvent) -> Void
    var onZoomTo: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space2) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    gapOverlays(width: geo.size.width, height: geo.size.height)
                    untrustedOverlay(width: geo.size.width, height: geo.size.height)

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
    ///
    /// A real ledger has many gaps, not one — every restart after a crash leaves
    /// another. The fixture had exactly one, which is how this ended up
    /// singular.
    private func gapOverlays(width: CGFloat, height: CGFloat) -> some View {
        ForEach(gaps) { gap in
            gapOverlay(gap, width: width, height: height)
        }
    }

    @ViewBuilder
    private func gapOverlay(_ gap: CoverageGap, width: CGFloat, height: CGFloat) -> some View {
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

    /// The span of the timeline that cannot be trusted, and the line where it
    /// begins.
    ///
    /// Drawn *under* the events, not over them: the point is that these records
    /// are still there and still readable — they simply cannot be relied on.
    /// Hiding or dimming them would answer a question nobody asked, and the
    /// altered records are the ones a person most wants to look at.
    ///
    /// Everything after the boundary is untrusted, including records that have
    /// not been written yet, so the region runs to the right-hand edge rather
    /// than stopping at the last event.
    @ViewBuilder
    private func untrustedOverlay(width: CGFloat, height: CGFloat) -> some View {
        if let trustBoundary, let at = trustBoundary.firstUntrustedAt {
            let f = window.fraction(of: at)
            if f < 1 {
                let x = max(0, f) * width
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.untrustedSpan)
                    Rectangle()
                        .fill(Palette.critical.opacity(0.8))
                        .frame(width: 2)
                }
                .frame(width: width - x, height: height - Metrics.timelineAxisInset)
                .offset(x: x)
                .accessibilityHidden(true)
            }
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
