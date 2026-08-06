import SwiftUI

/// Identity, liveness, scale, and the trust claim — the four things that must be
/// true at a glance before anything else is worth reading.
struct HeaderBar: View {
    var edition: String
    var integrity: IntegrityState
    var recordCount: Int
    var since: String
    /// Which ledger this is. Never hidden: an app that can show either a fixture
    /// or somebody's real history must say which one is on screen, or a
    /// screenshot of one can be mistaken for the other.
    var loaded: LoadedLedger?
    var onClose: (() -> Void)?
    @Binding var query: String
    /// Whether this field has the keyboard. The page needs to know: the
    /// Timeline menu's arrow-key commands stand down while a text field is
    /// being edited, or ⌘← stops meaning "beginning of line" here.
    @FocusState.Binding var queryFocus: Bool

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

            if let loaded { sourceChip(loaded) }

            Spacer()

            LedgerStatusBadge(state: integrity)

            searchField
        }
        .frame(height: Metrics.headerHeight)
    }

    /// What is loaded, and the way back to the chooser.
    ///
    /// The fixture is marked differently from a real ledger on purpose. Both
    /// look identical in a screenshot otherwise, and "is this real data?" is a
    /// question a reader of that screenshot cannot otherwise answer.
    private func sourceChip(_ loaded: LoadedLedger) -> some View {
        let isFixture = !loaded.isRealHistory
        return HStack(spacing: Metrics.space2) {
            Image(systemName: isFixture ? "sparkles" : "shield.lefthalf.filled")
                .font(.system(size: 10, weight: .medium))
            Text(loaded.badge)
                .font(Typography.caption)

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close this ledger and choose another")
            }
        }
        .foregroundStyle(isFixture ? Palette.textTertiary : Palette.accent)
        .pillSurface(
            fill: isFixture ? Palette.surfaceRaised : Palette.accentDim,
            stroke: isFixture ? Palette.border : Palette.accentBorder
        )
        .help(loaded.path ?? loaded.title)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Showing \(loaded.badge): \(loaded.title)")
    }

    private var searchField: some View {
        HStack(spacing: Metrics.space2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)
            TextField("Search this window", text: $query)
                .focused($queryFocus)
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
