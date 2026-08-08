import SwiftUI

/// One active constraint, with the way to undo it attached.
///
/// # Why every constraint gets a pill
///
/// This is what makes a preset teach instead of enchant. Clicking "Unlocks only"
/// fills the row with `only session.unlock`, and the next thing the user learns
/// is that event types exist, that this one is called that, and that it can be
/// taken off on its own. A preset that applied silently would leave them with a
/// filtered timeline and no model of why.
///
/// It is also the fastest possible undo. The alternative — reopening the popover
/// that set it — requires remembering which one that was, and the entire premise
/// of this feature is that people do not.
struct FilterConstraintPill: View {
    var constraint: FilterConstraint
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: Metrics.space2) {
            Text(constraint.text)
                .font(Typography.caption)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.textSecondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove filter: \(constraint.text)")
        }
        .padding(.horizontal, Metrics.space2)
        .padding(.vertical, Metrics.space1)
        .background(Capsule(style: .continuous).fill(Palette.surfaceRaised))
        .overlay(Capsule(style: .continuous).strokeBorder(Palette.filteredEdge, lineWidth: Metrics.hairline))
        .accessibilityElement(children: .contain)
    }
}

#Preview("Constraint pills") {
    HStack(spacing: Metrics.space2) {
        FilterConstraintPill(
            constraint: FilterConstraint(
                id: "a", text: "only session.unlock", removal: .value(.type, value: "session.unlock")),
            onRemove: {})
        FilterConstraintPill(
            constraint: FilterConstraint(
                id: "b", text: "excluding 3 subjects",
                removal: .wholeFacet(.subject, isExclusion: true)),
            onRemove: {})
        FilterConstraintPill(
            constraint: FilterConstraint(id: "c", text: "Warning and above", removal: .severity),
            onRemove: {})
    }
    .padding()
    .background(Palette.canvas)
}
