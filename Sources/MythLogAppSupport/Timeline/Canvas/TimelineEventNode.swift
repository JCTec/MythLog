import SwiftUI

struct TimelineEventNode: View {
    let displayRecord: TimelineDisplayRecord
    let placement: TimelinePlacement
    let canvasHeight: CGFloat
    let selected: Bool
    /// Descending index in chronological order, used so VoiceOver walks the timeline oldest-first
    /// instead of following the visual z-order set by severity and selection.
    let chronologicalSortPriority: Double
    let identifier: String
    let select: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let showLabel = selected || hovering || placement.prominence.labelVisible
        let labelY = TimelineEventLabelPositioner.yPosition(
            nodeY: placement.nodeY,
            direction: placement.direction,
            circleSize: placement.prominence.circleSize,
            canvasHeight: canvasHeight
        )

        ZStack(alignment: .topLeading) {
            Button(action: activate) {
                TimelineEventNodeIcon(
                    displayRecord: displayRecord,
                    prominence: placement.prominence,
                    selected: selected,
                    hovering: hovering
                )
            }
            .buttonStyle(.plain)
            .position(x: placement.x, y: placement.nodeY)
            .onHover { hovering = $0 }
            .help(displayRecord.eventNodeHelpText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(displayRecord.eventNodeAccessibilityLabel)
            .accessibilityValue(Text(displayRecord.eventNodeAccessibilityValue ?? ""))
            .accessibilityHint(displayRecord.eventNodeAccessibilityHint)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(named: "Open details", activate)
            .accessibilitySortPriority(chronologicalSortPriority)
            .accessibilityIdentifier(identifier)

            if showLabel {
                TimelineEventLabel(displayRecord: displayRecord, selected: selected)
                    .position(x: placement.x, y: labelY)
                    .transition(
                        ReducedMotion.transition(
                            .opacity.combined(with: .scale(scale: 0.98)), reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(selected ? 100 : placement.prominence.zIndex)
    }

    private func activate() {
        withAnimation(
            ReducedMotion.animation(.spring(response: 0.32, dampingFraction: 0.82), reduceMotion: reduceMotion)
        ) {
            select()
        }
    }
}
