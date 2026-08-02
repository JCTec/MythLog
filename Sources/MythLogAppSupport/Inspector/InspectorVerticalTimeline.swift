import SwiftUI

struct InspectorVerticalTimeline: View {
    let records: [TimelineDisplayRecord]
    let selectedID: TimelineRecord.ID
    let select: (TimelineRecord) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Timeline")
                .font(.headline)

            if records.isEmpty {
                Text("No visible events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        rowButton(displayRecord: record, index: index)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Nearby events")
    }

    /// A Button, not a tap gesture: a tap gesture is invisible to keyboard focus and gives VoiceOver
    /// nothing to activate.
    private func rowButton(displayRecord: TimelineDisplayRecord, index: Int) -> some View {
        let selected = displayRecord.id == selectedID

        return Button {
            withAnimation(
                ReducedMotion.animation(.spring(response: 0.32, dampingFraction: 0.82), reduceMotion: reduceMotion)
            ) {
                select(displayRecord.record)
            }
        } label: {
            InspectorTimelineRow(displayRecord: displayRecord, selected: selected)
        }
        .buttonStyle(.plain)
        .id(displayRecord.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayRecord.eventNodeAccessibilityLabel)
        .accessibilityHint("Selects this event.")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(A11yIdentifier.inspectorEventRow(index: index))
    }
}

struct InspectorTimelineRow: View {
    let displayRecord: TimelineDisplayRecord
    let selected: Bool

    @ScaledMetric(relativeTo: .callout) private var dotSize: CGFloat = 14
    @ScaledMetric(relativeTo: .callout) private var selectedDotSize: CGFloat = 18
    @ScaledMetric(relativeTo: .callout) private var glyphSize: CGFloat = 7
    @ScaledMetric(relativeTo: .callout) private var selectedGlyphSize: CGFloat = 8
    @ScaledMetric(relativeTo: .callout) private var stemHeight: CGFloat = 34

    var body: some View {
        let presentation = displayRecord.presentation
        let diameter = selected ? selectedDotSize : dotSize

        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(presentation.tintColor)
                    .frame(width: diameter, height: diameter)
                    .overlay {
                        Circle()
                            .stroke(
                                displayRecord.event.severity.timelineColor,
                                lineWidth: displayRecord.event.severity >= .warning ? 2 : 1)
                    }
                    .overlay {
                        Image(systemName: presentation.symbolName)
                            .font(.system(size: selected ? selectedGlyphSize : glyphSize, weight: .bold))
                            .foregroundStyle(.white)
                    }
                Rectangle()
                    .fill(presentation.tintColor.opacity(selected ? 0.42 : 0.22))
                    .frame(width: 1, height: stemHeight)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(displayRecord.title)
                    .font(.callout.weight(selected ? .semibold : .medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(displayRecord.timestamp.timelineTimeString)

                    // The row's dot is too small to carry a badge, so warning and critical say so in
                    // words here. The glyph is tinted; the word is not, so the cue does not depend on
                    // reading orange text at caption size.
                    if let badgeSymbolName = displayRecord.event.severity.timelineBadgeSymbolName {
                        Image(systemName: badgeSymbolName)
                            .foregroundStyle(displayRecord.event.severity.timelineColor)
                        Text(displayRecord.event.severity.accessibilityTitle)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text(displayRecord.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .padding(.horizontal, selected ? 7 : 0)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.control)
                .fill(selected ? presentation.tintColor.opacity(0.10) : Color.clear)
        )
    }
}
