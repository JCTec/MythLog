import SwiftUI

/// Explains a gap in prose, because the hatching alone cannot carry the point:
/// nothing was recorded is not the same as nothing happened.
///
/// Note it cites the ledger records that bound the gap — the claim is checkable,
/// not just asserted.
struct CoverageGapBanner: View {
    var gap: CoverageGap

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.space3) {
            Image(systemName: "powerplug")
                .font(.system(size: 15))
                .foregroundStyle(Palette.textTertiary)

            Text(bodyText)
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(Metrics.space4)
        .background(
            ZStack {
                HatchFill(spacing: 6, lineWidth: 1, color: Palette.textQuiet.opacity(0.18))
                RoundedRectangle(cornerRadius: Metrics.radiusPanel, style: .continuous)
                    .strokeBorder(
                        Palette.border,
                        style: StrokeStyle(lineWidth: Metrics.hairline, dash: [4, 3])
                    )
            }
        )
        .accessibilityElement(children: .combine)
    }

    private var bodyText: String {
        let from = gap.start.clockText
        let to = gap.end.clockText
        return """
        No coverage — the recorder was stopped from \(from) to \(to). Nothing was recorded during this span, \
        which is not the same as nothing happening. The stop and restart are records \
        #\(gap.stoppedRecord.formatted()) and #\(gap.restartedRecord.formatted()) in the ledger.
        """
    }
}
