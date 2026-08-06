import SwiftUI

extension TimelineCanvas {

    /// Square-root scaling. A 312-event burst next to 3-event buckets would
    /// flatten everything else to nothing on a linear scale; √ keeps the small
    /// bars legible while the spike still reads as a spike.
    private func barHeight(_ count: Int, max: Int, available: CGFloat) -> CGFloat {
        guard count > 0, max > 0 else { return 0 }
        return Swift.max(6, (sqrt(Double(count)) / sqrt(Double(max))) * available)
    }

    /// Where a bucket's bar is drawn, in points.
    ///
    /// Every bar position in this file comes from here, and here comes from
    /// ``BucketGrid/slot(_:)`` — the same projection the gap overlay uses. That
    /// is what makes hatch edges land on bar edges instead of near them.
    ///
    /// The bars used to be laid out in an `HStack` of equal slots, which is a
    /// layout in *slot* space rather than in time. See ``BucketGrid`` for what
    /// that cost.
    private func bar(_ index: Int, grid: BucketGrid, width: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let slot = grid.slot(index)
        let left = slot.lowerBound * width
        let full = (slot.upperBound - slot.lowerBound) * width
        // The gutter is taken out of the slot, half from each side, so the bar
        // stays centred on its own span of time.
        return (left + Metrics.clusterBarGap / 2, max(1, full - Metrics.clusterBarGap))
    }

    // MARK: - Density

    @ViewBuilder
    func density(size: CGSize, grid: BucketGrid, buckets: [BucketGrid.Bucket]) -> some View {
        let peak = buckets.map(\.count).max() ?? 1
        let available = size.height - Metrics.timelineAxisInset - Metrics.space2

        ZStack(alignment: .bottomLeading) {
            ForEach(buckets) { bucket in
                let frame = bar(bucket.id, grid: grid, width: size.width)
                Button { onZoomTo(bucket.start) } label: {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.textQuiet.opacity(0.75))
                        .frame(
                            width: frame.width,
                            height: barHeight(bucket.count, max: peak, available: available)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: frame.x)
                .accessibilityLabel("\(bucket.count) events at \(bucket.start.clockText)")
            }
        }
        .frame(width: size.width, height: size.height - Metrics.timelineAxisInset, alignment: .bottomLeading)
    }

    // MARK: - Clusters

    @ViewBuilder
    func clusters(size: CGSize, grid: BucketGrid, buckets: [BucketGrid.Bucket]) -> some View {
        let peak = buckets.map(\.count).max() ?? 1
        let available = size.height - Metrics.timelineAxisInset - 18

        ZStack(alignment: .bottomLeading) {
            ForEach(buckets) { bucket in
                let frame = bar(bucket.id, grid: grid, width: size.width)
                VStack(spacing: 3) {
                    // Constrained to the bar's own width rather than
                    // `.fixedSize()`: the clock-aligned grid makes the two edge
                    // buckets narrow, and a count that refused to shrink would
                    // sit on top of its neighbour's.
                    Text(bucket.count > 0 ? "\(bucket.count)" : "")
                        .font(Typography.clusterCount)
                        .foregroundStyle(Palette.textQuiet)
                    Button { onZoomTo(bucket.start) } label: {
                        VStack(spacing: 0) {
                            ForEach(EventKind.allCases.filter { (bucket.byKind[$0] ?? 0) > 0 }) { kind in
                                Rectangle()
                                    .fill(kind.hue)
                                    .frame(
                                        height: barHeight(bucket.count, max: peak, available: available)
                                            * CGFloat(bucket.byKind[kind] ?? 0) / CGFloat(Swift.max(1, bucket.count))
                                    )
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .frame(width: frame.width)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: frame.width)
                .offset(x: frame.x)
                .accessibilityLabel("\(bucket.count) events at \(bucket.start.clockText)")
            }
        }
        .frame(width: size.width, height: size.height - Metrics.timelineAxisInset, alignment: .bottomLeading)
    }

    // MARK: - Events

    /// Individual nodes, all above the axis. Stem heights alternate so adjacent
    /// events stay separable without a second axis to read.
    @ViewBuilder
    func nodes(size: CGSize) -> some View {
        let axisY = size.height - Metrics.timelineAxisInset
        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
            let x = window.fraction(of: event.at) * size.width
            let lift = [0.42, 0.68, 0.30, 0.55][index % 4]
            let y = axisY * (1 - lift)
            let isSelected = selected?.id == event.id

            ZStack(alignment: .top) {
                Rectangle()
                    .fill(event.kind.hue.opacity(0.35))
                    .frame(width: 1, height: axisY - y)
                    .offset(y: Metrics.nodeDiameter / 2)

                Button { onSelect(event) } label: {
                    Image(systemName: event.kind.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(event.kind.hue)
                        .frame(width: Metrics.nodeDiameter, height: Metrics.nodeDiameter)
                        .background(Circle().fill(Palette.surfaceRaised))
                        .overlay(
                            Circle().strokeBorder(
                                isSelected ? Palette.selectionBorder : event.kind.hue.opacity(0.6),
                                lineWidth: isSelected ? 2 : 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(event.label), \(event.detail)")
            }
            .frame(width: Metrics.nodeDiameter)
            .offset(x: x - Metrics.nodeDiameter / 2, y: y)
        }
    }
}
