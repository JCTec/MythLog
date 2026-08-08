import SwiftUI

/// What is inside one category, in the window that is on screen.
///
/// # Every value here came off an event you can see
///
/// Nothing is hardcoded. The event types, the sources, and the subjects are read
/// from the window's own records, which is the only version that survives Wave 5:
/// drives, displays, and user switching bring types this build has never heard
/// of, and a written-down list would offer filters for things the ledger no
/// longer contains and none for what it does.
///
/// It is also why the panel can be honest about emptiness. "No sources" here
/// means this window's events of this category carry no source, not that the
/// concept is missing.
///
/// # The category itself is not offered
///
/// The chip *is* that dimension. A control inside the popover that turned off
/// the category the popover belongs to would be a switch that closes the room it
/// is in.
struct FilterFacetPanel: View {
    var kind: EventKind
    /// One entry per facet, in ``EventFacet/detail`` order. Empty
    /// means the derivation has not finished — which is a different thing from
    /// a category with no values, and reads differently.
    var facetValues: [FacetValues]
    var filter: EventFilter
    var onSet: (EventFacet, String, FacetSelection.ValueState) -> Void
    var onClear: (EventFacet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space3) {
            header

            if facetValues.isEmpty {
                Text("Reading this window…")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.space4) {
                        ForEach(facetValues, id: \.facet) { section($0) }
                    }
                }
                .frame(maxHeight: Metrics.facetPanelMaxHeight)
            }
        }
        .padding(Metrics.space4)
        .frame(width: Metrics.facetPanelWidth)
        .background(Palette.surface)
    }

    private var header: some View {
        HStack(spacing: Metrics.space2) {
            StatusDot(color: kind.hue)
            Text(kind.label)
                .font(Typography.rowLabel)
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            Text("in this window")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    @ViewBuilder
    private func section(_ values: FacetValues) -> some View {
        let selection = filter[values.facet]

        VStack(alignment: .leading, spacing: Metrics.space1) {
            HStack(spacing: Metrics.space2) {
                Text(values.facet.label.uppercased())
                    .font(Typography.sectionKicker)
                    .foregroundStyle(Palette.textTertiary)
                Spacer()
                if !selection.isEmpty {
                    Button("Clear") { onClear(values.facet) }
                        .buttonStyle(.plain)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.accent)
                }
            }

            Text(values.facet.explanation)
                .font(Typography.caption)
                .foregroundStyle(Palette.textQuiet)

            if values.isEmpty {
                Text("Nothing here carries one.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuiet)
                    .padding(.top, Metrics.space1)
            } else {
                ForEach(values.values) { value in
                    FacetValueRow(
                        facet: values.facet,
                        value: value,
                        state: selection.state(of: value.value)
                    ) { onSet(values.facet, value.value, $0) }
                }
            }

            // Never a silent cap. A list that quietly stopped would let somebody
            // conclude a value is not in this window when it is — the same class
            // of lie as an undrawn coverage gap, at a smaller scale.
            if values.omitted > 0 {
                Text(
                    "\(values.omitted) less common \(values.facet.noun(count: values.omitted)) "
                        + "not listed. Narrow the window, or search for one by name."
                )
                .font(Typography.caption)
                .foregroundStyle(Palette.textQuiet)
                .padding(.top, Metrics.space1)
            }
        }
    }
}
