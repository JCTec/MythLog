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

    /// The natural height of the scroll content, measured at layout time.
    ///
    /// Starts at zero and is corrected on the first layout pass. That order is
    /// deliberate: this panel is presented in a popover *before* its values
    /// exist, so it grows into its content rather than shrinking into it, and
    /// growing from nothing is one step where starting at the cap would make a
    /// two-value category flash full height on the way down. See the comment on
    /// the `ScrollView` below for what the measurement is really for.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space3) {
            header

            if facetValues.isEmpty {
                Text("Reading this window…")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // The scroll view is given a definite height, measured from its
                // own content.
                //
                // # What actually went wrong
                //
                // Not what it looks like. A `ScrollView`'s ideal height does
                // *not* collapse here — hand this panel a populated
                // `facetValues` and it sizes correctly with nothing but
                // `.frame(maxHeight:)`, which is why it looked right in every
                // preview and every screenshot ever taken of it.
                //
                // It never receives one. ``MainPage/Model/openDetail(for:)``
                // clears `categoryDetail` and fills it from a task, so the
                // popover is *always* presented on the "Reading this window…"
                // branch above — one line of text — and the values arrive a
                // moment later. An `NSPopover` fixes its content size when it
                // is presented, and a SwiftUI view whose *ideal* height grows
                // afterwards does not move it. Measured: 100 pt on opening and
                // 100 pt for ever after, for a category with two values and one
                // with sixty alike. The header, and the first row sliced.
                //
                // # Why measuring fixes it
                //
                // A definite height is a value the popover follows. The content
                // is measured, the scroll view is given exactly that height up
                // to the cap, and the change lands as an explicit frame after
                // presentation rather than as a new ideal size — which is the
                // part `NSPopover` ignores. Same three categories, measured
                // through a real popover: 177, 357, 546 pt, the last being the
                // cap plus this panel's chrome.
                //
                // So: a category with two values gets a panel two values tall,
                // and a category with sixty scrolls at the cap and still says
                // how many values it did not show.
                //
                // `onGeometryChange` is macOS 13+ (verified against the DocC
                // data for the symbol, 2026-08-10), so no availability guard
                // is needed at this target. Its `transform` runs off-actor and
                // must be `@Sendable`; its `action` runs where the view lives,
                // which is what lets it write `@State` with no ceremony under
                // strict concurrency.
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.space4) {
                        ForEach(facetValues, id: \.facet) { section($0) }
                    }
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { contentHeight = $0 }
                }
                .frame(
                    height: min(
                        max(contentHeight, Metrics.facetRowHeight),
                        Metrics.facetPanelMaxHeight))
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
