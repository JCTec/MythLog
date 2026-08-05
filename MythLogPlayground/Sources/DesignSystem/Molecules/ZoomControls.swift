import SwiftUI

/// Zoom affordance for the timeline.
///
/// Pinch is never the only way in: gestures are not keyboard-reachable and not
/// operable under VoiceOver. Buttons and ⌘+/⌘− carry the same job, and the hint
/// text exists because a pinch affordance is otherwise invisible.
struct ZoomControls: View {
    var canZoomIn: Bool
    var canZoomOut: Bool
    var onZoomIn: () -> Void
    var onZoomOut: () -> Void
    var presets: [(label: String, span: TimeInterval)]
    var activePreset: String?
    var onPreset: (TimeInterval) -> Void

    var body: some View {
        HStack(spacing: Metrics.space2) {
            Text("⌘ + / ⌘ −  or pinch · click a bar to zoom in")
                .font(Typography.hint)
                .foregroundStyle(Palette.textQuiet)

            button("minus", enabled: canZoomOut, action: onZoomOut)
                .accessibilityLabel("Zoom out")
            button("plus", enabled: canZoomIn, action: onZoomIn)
                .accessibilityLabel("Zoom in")

            ForEach(presets, id: \.label) { preset in
                Button { onPreset(preset.span) } label: {
                    Text(preset.label)
                        .font(Typography.chip)
                        .foregroundStyle(activePreset == preset.label ? Palette.accent : Palette.textSecondary)
                        .pillSurface(
                            fill: .clear,
                            stroke: activePreset == preset.label ? Palette.accentBorder : Palette.border,
                            horizontal: Metrics.space3
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show last \(preset.label)")
            }
        }
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? Palette.textSecondary : Palette.textQuiet)
                .frame(width: Metrics.controlHeight, height: Metrics.controlHeight)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: Metrics.hairline)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
