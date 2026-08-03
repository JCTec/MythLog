import SwiftUI

struct StatusBadge<Leading: View, Content: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var content: () -> Content

    // Not private: a private stored property would make the synthesized memberwise initializer
    // private too, and callers build this with trailing closures.
    var space = ScaledSpacing()

    var body: some View {
        HStack(spacing: 6) {
            leading()
            content()
        }
        .padding(.horizontal, space.sm)
        .padding(.vertical, space.xs)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: AppRadius.control))
    }
}
