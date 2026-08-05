import SwiftUI

/// The smallest unit of state in the app: a coloured dot.
///
/// Never used alone to carry meaning — always paired with a label — because
/// severity and category must survive greyscale.
struct StatusDot: View {
    var color: Color
    var diameter: CGFloat = 7
    var isMuted: Bool = false

    var body: some View {
        Circle()
            .fill(isMuted ? Palette.textQuiet : color)
            .frame(width: diameter, height: diameter)
    }
}

#Preview {
    HStack(spacing: Metrics.space3) {
        ForEach(EventKind.allCases) { StatusDot(color: $0.hue) }
        StatusDot(color: .clear, isMuted: true)
    }
    .padding()
    .background(Palette.canvas)
}
