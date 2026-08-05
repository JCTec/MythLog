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

    /// Says only what the ledger actually establishes.
    ///
    /// This used to open "the recorder was stopped", which the ledger cannot
    /// support: a gap is found from *silence*, and silence does not say why. A
    /// stop record, when there is one, is extra detail — and its absence is the
    /// more alarming case, not the less. Claiming a clean shutdown over a
    /// force-quit would be exactly the reassurance this product must not offer.
    private var bodyText: String {
        let from = gap.start.clockText
        let to = gap.end.clockText
        let bounds =
            "The last record before it is #\(gap.lastRecordBefore.formatted()) and the first after it is "
            + "#\(gap.firstRecordAfter.formatted()), so the span is checkable."

        switch gap.evidence {
        case .recordedStop(let ordinal):
            return """
                No coverage for \(gap.durationLabel), from \(from) to \(to). The recorder wrote a stop record \
                (#\(ordinal.formatted())) before it went quiet, so this was a deliberate shutdown. Nothing was \
                recorded during the span, which is not the same as nothing happening. \(bounds)
                """
        case .unexplained:
            return """
                No coverage for \(gap.durationLabel), from \(from) to \(to), and the ledger does not say why — \
                nothing was written at all. That is what a force quit, a crash, or a power cut leaves behind: \
                a clean shutdown would have written a stop record. Nothing was recorded during the span, which \
                is not the same as nothing happening. \(bounds)
                """
        }
    }
}
