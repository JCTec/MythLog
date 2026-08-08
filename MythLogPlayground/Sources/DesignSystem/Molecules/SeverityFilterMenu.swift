import SwiftUI

/// "Warning and above" as a control, not as a query somebody has to type.
///
/// # A threshold, not five checkboxes
///
/// ``AlarmSeverity`` is `Comparable` on purpose, and the question people bring is
/// ordered: *at least* a warning. Five tick boxes can express that in two clicks
/// and can also express "notice but not warning", which is not a question anyone
/// has. Worse, a set would have to be re-ticked when a sixth severity is added,
/// and a threshold never does.
///
/// # It offers what the window contains
///
/// Levels with no records in the window are shown as unavailable rather than
/// hidden. Hiding them would make "there are no warnings here" indistinguishable
/// from "warnings are not a thing this app knows about", and the first is the
/// answer somebody came for.
struct SeverityFilterMenu: View {
    /// Records at each severity in the current window, before filtering.
    var counts: [AlarmSeverity: Int]
    var minimum: AlarmSeverity?
    var onChange: (AlarmSeverity?) -> Void

    /// Ascending, so "and above" sums the tail.
    private var levels: [AlarmSeverity] { AlarmSeverity.allCases.sorted() }

    private func atLeast(_ severity: AlarmSeverity) -> Int {
        levels.filter { $0 >= severity }.reduce(0) { $0 + (counts[$1] ?? 0) }
    }

    var body: some View {
        Menu {
            Button {
                onChange(nil)
            } label: {
                Label("Any severity", systemImage: minimum == nil ? "checkmark" : "")
            }

            Divider()

            ForEach(levels.reversed(), id: \.self) { severity in
                let matching = atLeast(severity)
                Button {
                    onChange(severity)
                } label: {
                    Text("\(severity.label) and above — \(matching)")
                }
                .disabled(matching == 0)
            }
        } label: {
            HStack(spacing: Metrics.space2) {
                Image(systemName: "dial.medium")
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(Typography.chip)
            }
            .foregroundStyle(minimum == nil ? Palette.textSecondary : Palette.filtered)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, Metrics.space2)
        .frame(height: Metrics.chipHeight)
        .background(Capsule(style: .continuous).fill(Palette.surfaceRaised))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    minimum == nil ? Palette.border : Palette.filteredEdge, lineWidth: Metrics.hairline))
        .accessibilityLabel("Minimum severity")
        .accessibilityValue(minimum.map { "\($0.label) and above" } ?? "any severity")
    }

    private var label: String {
        guard let minimum else { return "Any severity" }
        return "\(minimum.label)+"
    }
}

#Preview("Severity menu") {
    HStack(spacing: Metrics.space3) {
        SeverityFilterMenu(
            counts: [.debug: 59, .info: 320, .notice: 12, .warning: 2],
            minimum: nil, onChange: { _ in })
        SeverityFilterMenu(
            counts: [.debug: 59, .info: 320, .notice: 12, .warning: 2],
            minimum: .warning, onChange: { _ in })
    }
    .padding()
    .background(Palette.canvas)
}
