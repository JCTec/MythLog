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
///
/// # Three severities, not two
///
/// This used to be `isHealthy ? accent : warning`, which put "your history has
/// been altered" and "anchoring is paused" in the same amber. One of those means
/// somebody may have edited the record; the other means a backup copy is stale.
/// They now take their colour from ``IntegrityState/Severity``, and an alarm
/// also gets a filled pill so the difference survives greyscale.
struct LedgerStatusBadge: View {
    var state: IntegrityState

    private var tint: Color { Palette.tint(for: state.severity) }

    var body: some View {
        HStack(spacing: Metrics.space2) {
            Image(systemName: state.symbol)
                .font(.system(size: 12, weight: .medium))
            Text(state.headerText)
                .font(Typography.chip)
        }
        .foregroundStyle(tint)
        .modifier(AlarmPill(isAlarm: state.severity == .alarm, tint: tint))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.headerText)
    }

    /// Only an alarm gets chrome. If every state had a pill the pill would stop
    /// meaning anything, which is the same reason the banner is not dismissible.
    private struct AlarmPill: ViewModifier {
        var isAlarm: Bool
        var tint: Color

        func body(content: Content) -> some View {
            if isAlarm {
                content.pillSurface(fill: tint.opacity(0.16), stroke: tint.opacity(0.5))
            } else {
                content
            }
        }
    }
}
