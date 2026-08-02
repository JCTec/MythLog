import SwiftUI

struct IconTile: View {
    let symbolName: String
    let tintColor: Color
    var size: CGFloat = 32
    var cornerRadius: CGFloat = AppRadius.control
    var opacity: Double = 0.16

    /// Callers pass a fixed point size, so the tile scales through a ratio instead: at the default
    /// text size this resolves to 1 and the tile keeps its designed dimensions.
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    var body: some View {
        let scaledSize = size * textScale

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(tintColor.opacity(opacity))
                .frame(width: scaledSize, height: scaledSize)
            Image(systemName: symbolName)
                .font(.system(size: max(scaledSize * 0.45, 12 * textScale), weight: .semibold))
                .foregroundStyle(tintColor)
        }
    }
}
