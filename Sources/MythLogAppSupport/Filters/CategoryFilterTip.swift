import SwiftUI

struct CategoryFilterTip: View {
    let filter: TimelineFilterDefinition
    let state: CategoryDisplayState

    // Not private: that would make the synthesized memberwise initializer private too.
    var space = ScaledSpacing()

    @ScaledMetric(relativeTo: .caption) private var glyphSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var glyphColumnWidth: CGFloat = 15
    @ScaledMetric(relativeTo: .caption2) private var stateDotSize: CGFloat = 6
    @ScaledMetric(relativeTo: .caption) private var tipWidth: CGFloat = 142

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: filter.symbolName)
                    .font(.system(size: glyphSize, weight: .semibold))
                    .foregroundStyle(filter.tintColor)
                    .frame(width: glyphColumnWidth)

                Text(filter.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(state.indicatorColor(for: filter))
                    .frame(width: stateDotSize, height: stateDotSize)

                Text(state.tipText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, space.fixed(10))
        .padding(.vertical, space.sm)
        .frame(width: tipWidth, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control)
                .strokeBorder(filter.tintColor.opacity(0.34), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .allowsHitTesting(false)
        // Hover-only chrome. Nothing here is exclusive to it — the filter button it points at speaks
        // the same title and state as its own label and value — so exposing it would just park
        // VoiceOver on an overlay that only exists while a mouse is present.
        .accessibilityHidden(true)
    }
}
