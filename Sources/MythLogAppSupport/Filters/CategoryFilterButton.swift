import SwiftUI

struct CategoryFilterButton: View {
    let filter: TimelineFilterDefinition
    let state: CategoryDisplayState
    let hoverChanged: (TimelineFilterDefinition.ID?, Bool) -> Void
    let action: () -> Void
    @State private var isHovering = false

    @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = 13
    @ScaledMetric(relativeTo: .body) private var overlayGlyphSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var spotlightDotSize: CGFloat = 7
    @ScaledMetric(relativeTo: .body) private var buttonWidth: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var buttonHeight: CGFloat = 30

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: AppRadius.control)
                    .fill(backgroundColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.control)
                            .strokeBorder(borderColor, lineWidth: state == .spotlight ? 1.5 : 1)
                    }

                Image(systemName: filter.symbolName)
                    .font(.system(size: glyphSize, weight: .semibold))
                    .foregroundStyle(foregroundColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if state == .hidden {
                    Image(systemName: "slash")
                        .font(.system(size: overlayGlyphSize, weight: .bold))
                        .foregroundStyle(.secondary)
                        .offset(x: -4, y: 4)
                } else if state == .spotlight {
                    Circle()
                        .fill(filter.tintColor)
                        .frame(width: spotlightDotSize, height: spotlightDotSize)
                        .offset(x: -5, y: 5)
                }
            }
            .frame(width: buttonWidth, height: buttonHeight)
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.control))
        }
        .buttonStyle(.plain)
        .opacity(state == .hidden ? 0.48 : 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
            hoverChanged(filter.id, hovering)
        }
        .zIndex(isHovering ? 1_000 : 0)
        .accessibilityLabel(Text(filter.title))
        .accessibilityValue(Text(state.accessibilityText))
        .accessibilityHint(Text("Cycles filter visibility."))
        .accessibilityIdentifier(A11yIdentifier.toolbarCategoryFilter(id: filter.id))
    }

    private var foregroundColor: Color {
        switch state {
        case .normal: filter.tintColor
        case .spotlight: .white
        case .hidden: .secondary
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .normal: Color(nsColor: .controlBackgroundColor)
        case .spotlight: filter.tintColor
        case .hidden: Color(nsColor: .controlBackgroundColor).opacity(0.45)
        }
    }

    private var borderColor: Color {
        switch state {
        case .normal: filter.tintColor.opacity(0.28)
        case .spotlight: filter.tintColor.opacity(0.72)
        case .hidden: Color(nsColor: .separatorColor).opacity(0.45)
        }
    }
}
