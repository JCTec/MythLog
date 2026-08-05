import SwiftUI

/// A togglable category filter carrying its count for the current window.
///
/// The count is window-scoped: it recomputes on every zoom change, so it is a
/// live projection, not a static total.
struct FilterChip: View {
    var kind: EventKind
    var count: Int
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.space2) {
                StatusDot(color: kind.hue, isMuted: !isOn)
                Text(kind.label)
                    .font(Typography.chip)
                    .foregroundStyle(isOn ? Palette.textPrimary : Palette.textTertiary)
                Text("\(count)")
                    .font(Typography.chipCount)
                    .foregroundStyle(isOn ? Palette.textSecondary : Palette.textQuiet)
            }
            .pillSurface(
                fill: isOn ? Palette.surfaceRaised : Palette.surfaceSunken,
                stroke: isOn ? Palette.borderStrong : Palette.border
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind.label) filter")
        .accessibilityValue("\(count) events, \(isOn ? "shown" : "hidden")")
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview {
    HStack(spacing: Metrics.space2) {
        FilterChip(kind: .session, count: 65, isOn: true) {}
        FilterChip(kind: .files, count: 364, isOn: true) {}
        FilterChip(kind: .health, count: 0, isOn: false) {}
    }
    .padding()
    .background(Palette.canvas)
}
