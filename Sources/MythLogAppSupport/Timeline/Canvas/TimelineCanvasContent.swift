import SwiftUI

struct TimelineCanvasContent: View {
    let layout: TimelineLayout
    let records: [TimelineDisplayRecord]
    let selectedID: TimelineRecord.ID?
    let select: (TimelineRecord) -> Void

    var body: some View {
        let nodeCount = layout.nodes.count

        ZStack(alignment: .topLeading) {
            TimelineBackdrop(width: layout.contentWidth, height: layout.height, spineY: layout.spineY)
            TimeTicks(records: records, contentWidth: layout.contentWidth, spineY: layout.spineY)

            ForEach(Array(layout.nodes.enumerated()), id: \.element.id) { index, node in
                let selected = selectedID == node.id
                TimelineConnector(
                    width: layout.contentWidth,
                    height: layout.height,
                    x: node.placement.x,
                    spineY: layout.spineY,
                    nodeY: node.placement.nodeY,
                    color: node.displayRecord.presentation.tintColor,
                    prominence: node.placement.prominence,
                    selected: selected
                )

                TimelineEventNode(
                    displayRecord: node.displayRecord,
                    placement: node.placement,
                    canvasHeight: layout.height,
                    selected: selected,
                    chronologicalSortPriority: TimelineAccessibilityOrder.sortPriority(
                        index: index, count: nodeCount),
                    identifier: A11yIdentifier.timelineEventNode(index: index)
                ) {
                    select(node.displayRecord.record)
                }
                .id(node.id)
            }
        }
        .frame(width: layout.contentWidth, height: layout.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Event timeline")
        .accessibilityIdentifier(A11yIdentifier.timelineCanvas)
    }
}
