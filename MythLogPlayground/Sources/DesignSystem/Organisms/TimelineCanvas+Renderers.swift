import SwiftUI

extension TimelineCanvas {
    /// A bucket of events, shared by the density and cluster renderers.
    struct Bucket: Identifiable {
        var id: Int
        var start: Date
        var count: Int
        var byKind: [EventKind: Int]
    }

    /// Buckets sized so roughly 30 fit the window, snapped to sane steps.
    var buckets: [Bucket] {
        let steps: [TimeInterval] = [60, 120, 300, 600, 900, 1800, 3600, 7200]
        let step = steps.first { window.span / $0 <= 30 } ?? 7200
        let base = (window.start.timeIntervalSince1970 / step).rounded(.down) * step
        var out: [Bucket] = []
        var index = 0
        var t = base
        while t < window.end.timeIntervalSince1970 {
            let s = Date(timeIntervalSince1970: t)
            let e = Date(timeIntervalSince1970: t + step)
            let inBucket = events.filter { $0.at >= s && $0.at < e }
            var byKind: [EventKind: Int] = [:]
            for event in inBucket { byKind[event.kind, default: 0] += 1 }
            out.append(Bucket(id: index, start: s, count: inBucket.count, byKind: byKind))
            index += 1
            t += step
        }
        return out
    }

    /// Square-root scaling. A 312-event burst next to 3-event buckets would
    /// flatten everything else to nothing on a linear scale; √ keeps the small
    /// bars legible while the spike still reads as a spike.
    private func barHeight(_ count: Int, max: Int, available: CGFloat) -> CGFloat {
        guard count > 0, max > 0 else { return 0 }
        return Swift.max(6, (sqrt(Double(count)) / sqrt(Double(max))) * available)
    }

    // MARK: - Density

    @ViewBuilder
    func density(size: CGSize) -> some View {
        let list = buckets
        let peak = list.map(\.count).max() ?? 1
        let available = size.height - Metrics.timelineAxisInset - Metrics.space2
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(list) { bucket in
                Button { onZoomTo(bucket.start) } label: {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.textQuiet.opacity(0.75))
                        .frame(height: barHeight(bucket.count, max: peak, available: available))
                        .frame(maxWidth: .infinity, alignment: .bottom)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(bucket.count) events at \(bucket.start.clockText)")
            }
        }
        .frame(height: size.height - Metrics.timelineAxisInset, alignment: .bottom)
    }

    // MARK: - Clusters

    @ViewBuilder
    func clusters(size: CGSize) -> some View {
        let list = buckets
        let peak = list.map(\.count).max() ?? 1
        let available = size.height - Metrics.timelineAxisInset - 18
        HStack(alignment: .bottom, spacing: Metrics.clusterBarGap) {
            ForEach(list) { bucket in
                VStack(spacing: 3) {
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
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .accessibilityLabel("\(bucket.count) events at \(bucket.start.clockText)")
            }
        }
        .frame(height: size.height - Metrics.timelineAxisInset, alignment: .bottom)
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
