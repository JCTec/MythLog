import SwiftUI

/// "Recorder running · heartbeat 4 s" — liveness, not a control.
struct RecorderStatusPill: View {
    var isRunning: Bool
    var heartbeat: String

    var body: some View {
        HStack(spacing: Metrics.space2) {
            StatusDot(color: isRunning ? Palette.accent : Palette.critical)
            Text(isRunning ? "Recorder running · heartbeat \(heartbeat)" : "Recorder stopped")
                .font(Typography.chip)
                .foregroundStyle(isRunning ? Palette.textPrimary : Palette.critical)
        }
        .pillSurface(
            fill: isRunning ? Palette.accentDim : Palette.critical.opacity(0.12),
            stroke: isRunning ? Palette.accentBorder : Palette.critical.opacity(0.4)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isRunning ? "Recorder running, heartbeat \(heartbeat)" : "Recorder stopped")
    }
}

/// The trust claim, stated in the header at all times.
struct LedgerStatusBadge: View {
    var state: IntegrityState

    var body: some View {
        HStack(spacing: Metrics.space2) {
            Image(systemName: state.symbol)
                .font(.system(size: 12, weight: .medium))
            Text(state.headerText)
                .font(Typography.chip)
        }
        .foregroundStyle(state.isHealthy ? Palette.accent : Palette.warning)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.headerText)
    }
}
