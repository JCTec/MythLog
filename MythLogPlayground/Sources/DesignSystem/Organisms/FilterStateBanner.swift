import SwiftUI

/// The band that makes it impossible to forget you are looking at a subset.
///
/// # This is the whole feature's safety mechanism
///
/// In most applications a forgotten filter is an annoyance. Here it is the same
/// failure as an undrawn coverage gap: it makes absence look like safety.
/// Somebody opens this app because they are worried, sees a quiet night, and is
/// reassured — and if that quiet was a filter they set last Tuesday, the app has
/// lied to them about the one thing it exists to be honest about.
///
/// So this band is not a subtle highlight. It is permanent while a filter is
/// active, it sits directly above the timeline it is qualifying, it states the
/// number of hidden records rather than implying it, and "Show everything" is
/// always one click from wherever the user is looking.
///
/// # Three things stacked, loudest first
///
/// 1. **A restored filter**, in the alarm colour, because nobody chose it this
///    session. This is the dangerous case: a filter from last week that the user
///    does not remember setting.
/// 2. **The subset notice**, in the caution colour, whenever anything is hidden.
/// 3. **What a preset expanded to**, so a preset teaches the model rather than
///    hiding it.
///
/// # What it always says
///
/// The last line never changes and is never omitted: coverage gaps and records
/// that fail verification are not filterable. Someone reading a filtered
/// timeline needs to know which claims still hold, and "the gaps you can see are
/// all the gaps there are" is the one that matters.
struct FilterStateBanner: View {
    var filter: EventFilter
    var totalInWindow: Int
    var hiddenInWindow: Int
    var forcedUntrustedCount: Int
    var restored: RestoredFilterNotice?
    var presetNotice: FilterPreset.Resolution?
    /// Words in the search box that look like filter fields and are not.
    var queryProblems: [String] = []
    var onRemove: (FilterConstraint.Removal) -> Void
    var onShowEverything: () -> Void
    var onAcknowledgeRestored: () -> Void
    var onDismissPresetNotice: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space2) {
            if let restored { restoredBand(restored) }
            if let presetNotice { presetBand(presetNotice) }
            if filter.isFiltering { subsetBand }
        }
    }

    // MARK: - The subset notice

    private var subsetBand: some View {
        band(tint: Palette.filtered, wash: Palette.filteredWash, edge: Palette.filteredEdge) {
            VStack(alignment: .leading, spacing: Metrics.space2) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.space3) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.filtered)

                    Text(headline)
                        .font(Typography.rowLabel)
                        .foregroundStyle(Palette.textPrimary)

                    Spacer(minLength: Metrics.space3)

                    Button("Show everything", action: onShowEverything)
                        .buttonStyle(.plain)
                        .font(Typography.chip)
                        .foregroundStyle(Palette.textPrimary)
                        .pillSurface(fill: Palette.surfaceRaised, stroke: Palette.borderStrong)
                        .accessibilityHint("Removes every filter and shows the whole window.")
                }

                constraintRow

                if !queryProblems.isEmpty { queryProblemLine }

                Text(invariantLine)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter active")
        .accessibilityValue(
            "\(hiddenInWindow) of \(totalInWindow) records in this window are hidden. "
                + filter.summarySentence)
    }

    /// The number that must never stop being visible.
    ///
    /// Phrased as "hidden" rather than "shown" deliberately. "52 records" reads
    /// as an answer; "312 hidden" reads as a warning, and a warning is what a
    /// filtered view of somebody's history is.
    private var headline: String {
        guard hiddenInWindow > 0 else {
            return "A filter is active — nothing in this window matches it"
        }
        return "\(hiddenInWindow.formatted()) of \(totalInWindow.formatted()) records in this window are hidden"
    }

    private var invariantLine: String {
        let base =
            "Coverage gaps and records that fail verification are never hidden by a filter — "
            + "what you can see of those is all there is."
        guard forcedUntrustedCount > 0 else { return base }
        return base
            + " \(forcedUntrustedCount.formatted()) record(s) here failed verification and are shown "
            + "despite this filter."
    }

    /// A mistyped field is the one search failure that reads as an answer.
    ///
    /// `sevrity:>=warning` finds nothing, so the timeline empties, so the user
    /// concludes there were no warnings. Naming the word is the cheapest possible
    /// fix and the difference between a typo and a false reassurance.
    private var queryProblemLine: some View {
        HStack(spacing: Metrics.space2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.warning)
            Text(
                "\(queryProblems.map { "“\($0):”" }.joined(separator: ", ")) "
                    + "\(queryProblems.count == 1 ? "is not a filter" : "are not filters") — "
                    + "searched as plain text instead. Try kind:, type:, source:, path:, or severity:."
            )
            .font(Typography.caption)
            .foregroundStyle(Palette.warning)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var constraintRow: some View {
        FlowRow(spacing: Metrics.space2) {
            ForEach(filter.constraints) { constraint in
                FilterConstraintPill(constraint: constraint) { onRemove(constraint.removal) }
            }
        }
    }

    // MARK: - The restored filter

    private func restoredBand(_ notice: RestoredFilterNotice) -> some View {
        band(tint: Palette.critical, wash: Palette.restoredWash, edge: Palette.restoredEdge) {
            VStack(alignment: .leading, spacing: Metrics.space1) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.space3) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.critical)

                    Text(notice.headline)
                        .font(Typography.rowLabel)
                        .foregroundStyle(Palette.textPrimary)

                    Spacer(minLength: Metrics.space3)

                    Button("Show everything", action: onShowEverything)
                        .buttonStyle(.plain)
                        .font(Typography.chip)
                        .foregroundStyle(Palette.textPrimary)
                        .pillSurface(fill: Palette.surfaceRaised, stroke: Palette.borderStrong)

                    Button("Keep it", action: onAcknowledgeRestored)
                        .buttonStyle(.plain)
                        .font(Typography.chip)
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityHint("Dismisses this notice. The filter stays active.")
                }

                Text(notice.body)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)

                if !notice.expansion.isEmpty {
                    Text("It is hiding: \(notice.expansion)")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(notice.headline)
        .accessibilityValue(notice.body)
    }

    // MARK: - What a preset expanded to

    private func presetBand(_ resolution: FilterPreset.Resolution) -> some View {
        band(
            tint: resolution.foundNothing ? Palette.textTertiary : Palette.accent,
            wash: Palette.surfaceRaised,
            edge: Palette.border
        ) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.space3) {
                Image(systemName: resolution.preset.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(resolution.foundNothing ? Palette.warning : Palette.accent)

                VStack(alignment: .leading, spacing: 1) {
                    Text(resolution.preset.title)
                        .font(Typography.chip)
                        .foregroundStyle(Palette.textPrimary)
                    Text(resolution.explanation)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Metrics.space3)

                Button(action: onDismissPresetNotice) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
    }

    // MARK: - Shared chrome

    /// A left rule, a wash, and a hairline. The rule is what carries the state
    /// in greyscale, which is why it is a shape and not only a colour.
    private func band(
        tint: Color, wash: Color, edge: Color, @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(tint)
                .frame(width: Metrics.stateBandRule)
            content()
                .padding(.horizontal, Metrics.space4)
                .padding(.vertical, Metrics.space3)
        }
        .background(
            RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous).fill(wash))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                .strokeBorder(edge, lineWidth: Metrics.hairline))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous))
    }
}
