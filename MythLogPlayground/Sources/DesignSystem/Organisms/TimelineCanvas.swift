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
    /// Records in this window a filter is hiding, so an empty canvas can say
    /// which kind of empty it is.
    var hiddenByFilter: Int = 0
    var onSelect: (TimelineEvent) -> Void
    var onZoomTo: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space2) {
            GeometryReader { geo in
                // Derived once and handed to both the bars and the hatching.
                // Two computations of the same grid is how they drift apart, and
                // it also spared thirty passes over the window's events.
                let grid = BucketGrid(window: window)
                let buckets = level == .events ? [] : grid.buckets(over: events)

                ZStack(alignment: .topLeading) {
                    gapOverlays(marks: gapMarks(grid: grid, buckets: buckets, width: geo.size.width), size: geo.size)
                    untrustedOverlay(width: geo.size.width, height: geo.size.height)

                    switch level {
                    case .density: density(size: geo.size, grid: grid, buckets: buckets)
                    case .clusters: clusters(size: geo.size, grid: grid, buckets: buckets)
                    case .events: nodes(size: geo.size)
                    }

                    if events.isEmpty { emptyNotice(size: geo.size) }

                    axisLine(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(height: Metrics.timelineHeight)

            axisLabels
        }
    }

    // MARK: - Shared chrome

    /// What to draw for the gaps at this level.
    ///
    /// The decision lives in ``CoverageGapLayout`` rather than here because it
    /// is arithmetic over dates and buckets, and arithmetic that decides whether
    /// the interface contradicts itself belongs somewhere a test can reach it
    /// without a renderer.
    ///
    /// At Density and Clusters the marks are quantised to the same grid the bars
    /// are drawn on. At Events there is no grid, so a real timestamp is the
    /// honest position and the gap stays continuous.
    private func gapMarks(
        grid: BucketGrid, buckets: [BucketGrid.Bucket], width: CGFloat
    ) -> [CoverageGapLayout.Mark] {
        switch level {
        case .density, .clusters:
            return CoverageGapLayout.marks(for: gaps, on: grid, buckets: buckets)
        case .events:
            return CoverageGapLayout.marks(
                for: gaps,
                in: window,
                minimumWidth: Double(Metrics.timelineGapMinimumWidth / max(1, width))
            )
        }
    }

    /// Drawn beneath every level and never filterable. An absence of recording
    /// is not an event, so no filter may hide it.
    ///
    /// A real ledger has many gaps, not one — every restart after a crash leaves
    /// another. The fixture had exactly one, which is how this ended up
    /// singular.
    private func gapOverlays(marks: [CoverageGapLayout.Mark], size: CGSize) -> some View {
        ForEach(marks) { mark in
            gapOverlay(mark, width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    private func gapOverlay(_ mark: CoverageGapLayout.Mark, width: CGFloat, height: CGFloat) -> some View {
        let height = height - Metrics.timelineAxisInset

        switch mark.form {
        case .region:
            let x = mark.start * width
            let w = (mark.end - mark.start) * width
            ZStack {
                HatchFill()
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Palette.textQuiet.opacity(0.7))
                if w > 150 {
                    Text(mark.label)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Metrics.space3)
                        .frame(height: 22)
                        .background(Capsule().fill(Palette.surface))
                        .overlay(Capsule().strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                }
            }
            .frame(width: w, height: height)
            .offset(x: x)
            .accessibilityLabel(mark.label)

        case .tick:
            // Solid, not hatched: three points of diagonal lines is a smudge.
            // The mark has to survive being small, which is the entire reason it
            // is a mark and not a region. See `CoverageGapLayout.Mark.Form`.
            RoundedRectangle(cornerRadius: 1)
                .fill(Palette.textQuiet.opacity(0.75))
                .frame(width: Metrics.timelineGapTickWidth, height: height)
                .offset(x: mark.start * width - Metrics.timelineGapTickWidth / 2)
                .accessibilityLabel(mark.label)
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

    /// An empty timeline, saying which kind of empty.
    ///
    /// Drawn over the gap hatching rather than instead of it, because a window
    /// containing nothing but a coverage gap must still show the gap: the
    /// hatching is the answer, and this only explains the space around it.
    ///
    /// "Nothing happened" and "you are hiding everything that happened" produce
    /// identical pixels otherwise, and only one of them is true.
    private func emptyNotice(size: CGSize) -> some View {
        VStack(spacing: Metrics.space1) {
            Text(hiddenByFilter > 0 ? "Everything here is filtered out" : "Nothing recorded in this window")
                .font(Typography.chip)
                .foregroundStyle(hiddenByFilter > 0 ? Palette.filtered : Palette.textTertiary)
            if hiddenByFilter > 0 {
                Text("\(hiddenByFilter.formatted()) record(s) are hidden")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.horizontal, Metrics.space3)
        .padding(.vertical, Metrics.space2)
        .background(Capsule().fill(Palette.surface.opacity(0.9)))
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: Metrics.hairline))
        .frame(width: size.width, height: size.height - Metrics.timelineAxisInset)
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
