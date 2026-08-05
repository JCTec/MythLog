import SwiftUI

/// Identity, liveness, scale, and the trust claim — the four things that must be
/// true at a glance before anything else is worth reading.
struct HeaderBar: View {
    var edition: String
    var integrity: IntegrityState
    var recordCount: Int
    var since: String
    @Binding var query: String

    var body: some View {
        HStack(spacing: Metrics.space4) {
            HStack(spacing: Metrics.space3) {
                MarkGlyph()
                VStack(alignment: .leading, spacing: 0) {
                    Text("MythLog").font(Typography.appName).foregroundStyle(Palette.textPrimary)
                    Text(edition).font(Typography.editionLabel).foregroundStyle(Palette.textTertiary)
                }
            }

            RecorderStatusPill(isRunning: true, heartbeat: "4 s")

            Text("\(recordCount.formatted()) records · \(since)")
                .font(Typography.chip)
                .foregroundStyle(Palette.textSecondary)

            Spacer()

            LedgerStatusBadge(state: integrity)

            searchField
        }
        .frame(height: Metrics.headerHeight)
    }

    private var searchField: some View {
        HStack(spacing: Metrics.space2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)
            TextField("Search this window", text: $query)
                .textFieldStyle(.plain)
                .font(Typography.chip)
                .foregroundStyle(Palette.textPrimary)
        }
        .frame(width: 210)
        .pillSurface(fill: Palette.surfaceSunken, stroke: Palette.border)
        .accessibilityLabel("Search events in the current window")
    }
}

/// The "M" drawn as a timeline: a polyline with a chain-head node.
struct MarkGlyph: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            var path = Path()
            path.move(to: CGPoint(x: w * 0.10, y: h * 0.78))
            path.addLine(to: CGPoint(x: w * 0.32, y: h * 0.26))
            path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.58))
            path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.26))
            path.addLine(to: CGPoint(x: w * 0.90, y: h * 0.78))
            context.stroke(
                path,
                with: .color(Palette.textPrimary),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
            let head = CGRect(x: w * 0.90 - 3, y: h * 0.78 - 3, width: 6, height: 6)
            context.fill(Path(ellipseIn: head), with: .color(Palette.accent))
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}
