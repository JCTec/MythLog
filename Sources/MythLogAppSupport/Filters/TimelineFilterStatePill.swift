import SwiftUI

struct TimelineFilterStatePill: View {
    let filter: TimelineFilterDefinition
    let state: CategoryDisplayState
    let action: () -> Void

    var body: some View {
        Button(state.settingsLabel) {
            action()
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.semibold))
        .foregroundStyle(state.indicatorColor(for: filter))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        .disabled(!filter.isEnabled)
        .accessibilityLabel(Text("\(filter.title) visibility"))
        .accessibilityValue(Text(state.accessibilityText))
        .accessibilityHint(Text("Cycles between visible, prioritized, and hidden."))
        .accessibilityIdentifier(A11yIdentifier.filterSettingsStatePill(id: filter.id))
        .help(state.accessibilityText)
    }
}
