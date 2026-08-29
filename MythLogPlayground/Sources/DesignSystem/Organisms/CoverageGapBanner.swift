import SwiftUI

/// A span where nothing was recorded, stated in the list.
///
/// # One explanation, not one per gap
///
/// This used to render the full didactic paragraph — *"that is what a force
/// quit, a crash, or a power cut leaves behind…"* — on every gap it was given. A
/// real ledger has many gaps: every restart after a crash leaves another, and a
/// machine that sleeps unattended leaves several a week. Three identical
/// paragraphs stacked at the top of the list are not read three times, they are
/// read zero times. The most consequential card in the interface had become
/// wallpaper by repetition.
///
/// So the explanation appears **once**, on the first gap in the list, and every
/// gap after it compresses to a single scannable line carrying the same facts:
/// duration, range, whether the ledger explained itself, and the ordinals that
/// make the claim checkable. Any of them expands on click, so nothing is behind
/// a decision the reader has to make blind.
///
/// The facts are never what gets compressed. The prose is.
struct CoverageGapBanner: View {
    var gap: CoverageGap
    /// Whether this is the first gap shown. The first one explains what a
    /// coverage gap is; the rest assume the reader has met one.
    var isFirst: Bool = true

    @State private var isExpanded: Bool?

    /// Expanded by default only for the first gap.
    private var expanded: Bool { isExpanded ?? isFirst }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space3) {
            summaryRow
            if expanded {
                Text(explanation)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Metrics.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gap.summaryLine)
        .accessibilityHint(expanded ? "" : "Expands the explanation.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { isExpanded = !expanded }
    }

    /// The line every gap card shows, expanded or not.
    ///
    /// Laid out as discrete fields rather than one sentence so the eye can find
    /// the duration without reading: a reader scanning six gap cards is looking
    /// for the long one.
    private var summaryRow: some View {
        Button {
            isExpanded = !expanded
        } label: {
            HStack(spacing: Metrics.space3) {
                CoverageGapMark()

                Text("No coverage")
                    .font(Typography.rowLabel)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .fixedSize()

                Text(gap.durationLabel)
                    .font(Typography.rowLabel)
                    .monospacedDigit()
                    .foregroundStyle(Palette.warning)
                    .lineLimit(1)
                    .fixedSize()

                Text(gap.rangeLabel)
                    .font(Typography.rowTime)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .fixedSize()

                // The unexplained case is the alarming one and is coloured as
                // such; a recorded stop is ordinary and stays quiet.
                Text(gap.evidenceLabel)
                    .font(Typography.caption)
                    .foregroundStyle(gap.wasGraceful ? Palette.textTertiary : Palette.warning)
                    .lineLimit(1)
                    .fixedSize()

                Spacer(minLength: Metrics.space2)

                Text(gap.boundsLabel)
                    .font(Typography.rowRecord)
                    .foregroundStyle(Palette.textQuiet)
                    .lineLimit(1)
                    .fixedSize()

                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Says only what the ledger actually establishes.
    ///
    /// This used to open "the recorder was stopped", which the ledger cannot
    /// support: a gap is found from *silence*, and silence does not say why. A
    /// stop record, when there is one, is extra detail — and its absence is the
    /// more alarming case, not the less. Claiming a clean shutdown over a
    /// force-quit would be exactly the reassurance this product must not offer.
    ///
    /// The duration and the range are no longer repeated here — they are in the
    /// line above, and a paragraph that restates its own heading is a paragraph
    /// people learn to skip.
    private var explanation: String {
        let bounds =
            "The last record before it is #\(gap.lastRecordBefore.formatted()) and the first after it is "
            + "#\(gap.firstRecordAfter.formatted()), so the span is checkable."

        switch gap.evidence {
        case .recordedStop(let ordinal):
            return """
                The recorder wrote a stop record (#\(ordinal.formatted())) before it went quiet, so this was a \
                deliberate shutdown. Nothing was recorded during the span, which is not the same as nothing \
                happening. \(bounds)
                """
        case .unexplained:
            return """
                The ledger does not say why — nothing was written at all. That is what a force quit, a crash, \
                or a power cut leaves behind: a clean shutdown would have written a stop record. Nothing was \
                recorded during the span, which is not the same as nothing happening. \(bounds)
                """
        }
    }
}
