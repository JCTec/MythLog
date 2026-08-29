import SwiftUI

extension FilterChip {
    /// A source this build cannot observe.
    ///
    /// Deliberately shown rather than omitted: a locked chip means "I cannot
    /// see", a zero-count chip means "nothing happened". Those must never look
    /// alike, which is why this one is dashed and carries a lock glyph.
    struct Locked: View {
        var source: LockedSource

        var body: some View {
            HStack(spacing: Metrics.space2) {
                Image(systemName: "lock")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.textQuiet)
                Text(source.label)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuiet)
                    // "Failed u…" is not a source anybody can identify, and this
                    // chip's whole job is to name what cannot be seen. It sizes
                    // to its label and the row wraps around it.
                    .lineLimit(1)
                    .fixedSize()
            }
            // Quieter than a real chip on purpose: this is informational, not
            // interactive, and at equal weight four of them read as four more
            // controls the user has failed to understand.
            .pillSurface(fill: .clear, stroke: Palette.divider, dashed: true, horizontal: Metrics.space2)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(source.label)
            .accessibilityValue("Not observable by this edition")
        }
    }
}

#Preview {
    HStack(spacing: Metrics.space2) {
        ForEach(LockedSource.allCases) { FilterChip.Locked(source: $0) }
    }
    .padding()
    .background(Palette.canvas)
}
