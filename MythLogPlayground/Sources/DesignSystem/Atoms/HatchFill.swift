import SwiftUI

/// Diagonal hatching — the visual language for "nothing was recorded here".
///
/// A coverage gap is an absence of recording, not an absence of events, so it
/// gets a texture rather than emptiness. It must render identically at every
/// zoom level and can never be hidden by a filter.
struct HatchFill: View {
    var spacing: CGFloat = 5
    var lineWidth: CGFloat = 1.2
    var color: Color = Palette.textQuiet.opacity(0.55)

    var body: some View {
        Canvas { context, size in
            let diagonal = size.width + size.height
            var x = -size.height
            while x < diagonal {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(color), lineWidth: lineWidth)
                x += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    HatchFill()
        .frame(width: 260, height: 90)
        .background(Palette.surface)
        .padding()
        .background(Palette.canvas)
}
