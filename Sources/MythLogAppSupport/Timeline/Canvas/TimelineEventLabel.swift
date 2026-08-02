import SwiftUI

struct TimelineEventLabel: View {
    let displayRecord: TimelineDisplayRecord
    let selected: Bool

    @ScaledMetric(relativeTo: .caption) private var labelWidth: CGFloat = 172
    @ScaledMetric(relativeTo: .caption2) private var categoryDotSize: CGFloat = 4

    var body: some View {
        let presentation = displayRecord.presentation

        VStack(alignment: .leading, spacing: 3) {
            Text(displayRecord.title)
                .font(.caption.weight(selected ? .semibold : .medium))
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 5) {
                Text(displayRecord.hiddenBySearch ? "Hidden" : displayRecord.timestamp.timelineTimeString)
                Circle()
                    .fill(presentation.tintColor.opacity(0.75))
                    .frame(width: categoryDotSize, height: categoryDotSize)
                Text(presentation.title)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(width: labelWidth, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control)
                .strokeBorder(
                    selected ? presentation.tintColor.opacity(0.58) : Color(nsColor: .separatorColor).opacity(0.35),
                    lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(selected ? 0.12 : 0.06), radius: selected ? 10 : 4, y: 3)
        // The floating caption restates its own event node's title, time, and category. Its node
        // already speaks all three, so exposing it would double every event in VoiceOver.
        .accessibilityHidden(true)
    }
}
