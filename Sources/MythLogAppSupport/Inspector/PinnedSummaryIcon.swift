import MythLogCore
import SwiftUI

struct PinnedSummaryIcon: View {
    let symbolName: String
    let tintColor: Color
    let severity: AlarmSeverity

    @ScaledMetric(relativeTo: .body) private var discSize: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = 16
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 15

    var body: some View {
        ZStack {
            Circle()
                .fill(tintColor)
                .frame(width: discSize, height: discSize)
            Circle()
                .stroke(
                    severity.timelineColor,
                    lineWidth: severity >= .warning ? 2.4 : 1.1
                )
                .frame(width: ringSize, height: ringSize)
            Image(systemName: symbolName)
                .foregroundStyle(.white)
                .font(.system(size: glyphSize, weight: .semibold))

            // Same shape-not-hue cue the timeline nodes carry, so the inspector header agrees with
            // the canvas on a grayscale display.
            if let badgeSymbolName = severity.timelineBadgeSymbolName {
                Image(systemName: badgeSymbolName)
                    .font(.system(size: badgeSize, weight: .bold))
                    .foregroundStyle(severity.timelineColor)
                    .background {
                        Circle()
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .frame(width: badgeSize + 3, height: badgeSize + 3)
                    }
                    .offset(x: ringSize * 0.4, y: -ringSize * 0.4)
            }
        }
    }
}
