import SwiftUI

/// The one mark that means "nothing was recorded here".
///
/// It appeared three ways: diagonal hatching on the timeline, a `powerplug`
/// glyph on the list cards, and a hatch swatch in the legend. Three marks for one
/// concept means a reader has to learn three times that they are the same thing,
/// and the glyph in particular was unrecognisable at 15pt — a plug reads as
/// *power*, which is a category this app already has.
///
/// The hatching wins because it is the one the timeline cannot do without: the
/// region it draws has to be a texture, not an icon. So the cards and the legend
/// adopt the texture instead, at swatch size.
struct CoverageGapMark: View {
    var size: CGSize = CGSize(width: 14, height: 14)

    var body: some View {
        HatchFill(spacing: 3, lineWidth: 1, color: Palette.textQuiet.opacity(0.85))
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: Metrics.hairline)
            )
            .accessibilityHidden(true)
    }
}

#Preview("Coverage gap mark") {
    HStack(spacing: Metrics.space3) {
        CoverageGapMark()
        CoverageGapMark(size: CGSize(width: 13, height: 10))
        CoverageGapMark(size: CGSize(width: 24, height: 24))
    }
    .padding()
    .background(Palette.canvas)
}
