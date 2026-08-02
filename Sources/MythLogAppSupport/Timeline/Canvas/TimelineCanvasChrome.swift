import SwiftUI

struct EmptyTimelineState: View {
    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 28

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "timeline.selection")
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No events in this range")
                .font(.headline)
            Text("Change the time window or category filters.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.control))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No events in this range. Change the time window or category filters.")
        .accessibilityIdentifier(A11yIdentifier.timelineEmptyState)
    }
}

struct LiveEdge: View {
    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.green.opacity(0.8))
                .frame(width: 4, height: 34)
            Rectangle()
                .fill(Color.green.opacity(0.42))
                .frame(width: 2)
            Capsule()
                .fill(Color.green.opacity(0.8))
                .frame(width: 4, height: 34)
        }
        .padding(.vertical, 22)
        .padding(.trailing, 10)
        .help("Live edge")
        // Decorative, but it is the only cue that the right edge of the canvas is "now", so it is
        // named rather than hidden.
        .accessibilityElement()
        .accessibilityLabel("Live edge. The right end of the timeline is the present moment.")
        .accessibilityIdentifier(A11yIdentifier.timelineLiveEdge)
    }
}
