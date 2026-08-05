import SwiftUI

/// The rounded container every chip, badge, and pill in the app is built from.
/// Centralised so chip height and border weight are decided once.
struct PillSurface: ViewModifier {
    var fill: Color = Palette.surfaceRaised
    var stroke: Color = Palette.border
    var dashed: Bool = false
    var horizontal: CGFloat = Metrics.space3

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontal)
            .frame(height: Metrics.chipHeight)
            .background(
                Capsule(style: .continuous).fill(fill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        stroke,
                        style: StrokeStyle(lineWidth: Metrics.hairline, dash: dashed ? [4, 3] : [])
                    )
            )
    }
}

extension View {
    func pillSurface(
        fill: Color = Palette.surfaceRaised,
        stroke: Color = Palette.border,
        dashed: Bool = false,
        horizontal: CGFloat = Metrics.space3
    ) -> some View {
        modifier(PillSurface(fill: fill, stroke: stroke, dashed: dashed, horizontal: horizontal))
    }

    /// Panels — the timeline, the list, the inspector.
    func panelSurface() -> some View {
        background(
            RoundedRectangle(cornerRadius: Metrics.radiusPanel, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusPanel, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: Metrics.hairline)
        )
    }
}
