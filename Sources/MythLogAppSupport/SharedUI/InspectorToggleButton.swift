import SwiftUI

struct InspectorToggleButton: View {
    let isVisible: Bool
    let isEnabled: Bool
    let toggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ToolbarIconButton(
            symbolName: "sidebar.right",
            helpText: isVisible ? "Hide inspector" : "Show inspector",
            identifier: A11yIdentifier.toolbarInspectorToggle,
            isActive: isVisible,
            isEnabled: isEnabled
        ) {
            withAnimation(ReducedMotion.animation(.easeOut(duration: 0.2), reduceMotion: reduceMotion)) {
                toggle()
            }
        }
    }
}
