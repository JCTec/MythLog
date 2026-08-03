import SwiftUI

struct TimelineFilterTemplateBadge: View {
    private var space = ScaledSpacing()

    var body: some View {
        Text("template")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, space.fixed(5))
            .padding(.vertical, space.fixed(1))
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
    }
}
