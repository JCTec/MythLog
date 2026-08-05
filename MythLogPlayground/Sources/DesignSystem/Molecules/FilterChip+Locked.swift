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
                    .font(Typography.chip)
                    .foregroundStyle(Palette.textQuiet)
            }
            .pillSurface(fill: .clear, stroke: Palette.border, dashed: true)
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
