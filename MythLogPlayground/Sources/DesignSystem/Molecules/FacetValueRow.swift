import SwiftUI

/// One value a facet takes in the window, with the two things you can do to it.
///
/// # Two buttons, not a checkbox
///
/// A checkbox expresses one bit, and the useful operations here are two
/// different ones. "Show me only unlocks" is inclusion. "Show me everything
/// except the build folder" is subtraction — and subtraction is the one
/// investigators actually reach for, because the 312-event build storm is not a
/// thing you want to *select*, it is a thing you want gone so the day underneath
/// it becomes readable.
///
/// A single toggle cannot say both. Worse, it forces the exclusion case to be
/// expressed as "include these other 40 values", which nobody will do and which
/// silently hides any value that arrives afterwards.
///
/// So: **only** and **except**, each a toggle in its own right. Pressing the one
/// that is already on clears it, which is the undo people try first.
struct FacetValueRow: View {
    var facet: EventFacet
    var value: FacetValue
    var state: FacetSelection.ValueState
    var onSet: (FacetSelection.ValueState) -> Void

    var body: some View {
        HStack(spacing: Metrics.space2) {
            Text(facet.display(value.value))
                .font(Typography.caption)
                .foregroundStyle(textColour)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value.value)

            Spacer(minLength: Metrics.space2)

            Text(value.count.formatted())
                .font(Typography.rowRecord)
                .foregroundStyle(Palette.textQuiet)

            button(
                symbol: "plus", isOn: state == .included,
                on: Palette.facetIncluded, wash: Palette.facetIncludedWash,
                label: "Show only \(facet.display(value.value))"
            ) { onSet(state == .included ? .allowed : .included) }

            button(
                symbol: "minus", isOn: state == .excluded,
                on: Palette.facetExcluded, wash: Palette.facetExcludedWash,
                label: "Exclude \(facet.display(value.value))"
            ) { onSet(state == .excluded ? .allowed : .excluded) }
        }
        .frame(height: Metrics.facetRowHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(facet.display(value.value)), \(value.count.formatted()) events")
        .accessibilityValue(stateDescription)
    }

    private func button(
        symbol: String, isOn: Bool, on: Color, wash: Color, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isOn ? on : Palette.textTertiary)
                .frame(width: 20, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.space1, style: .continuous)
                        .fill(isOn ? wash : Palette.surfaceSunken))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.space1, style: .continuous)
                        .strokeBorder(isOn ? on.opacity(0.5) : Palette.border, lineWidth: Metrics.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }

    /// The fourth state is the one worth spelling out: a value nobody excluded,
    /// hidden because something else was included. It looks identical to an
    /// exclusion on screen and is undone differently.
    private var stateDescription: String {
        switch state {
        case .allowed: "shown"
        case .included: "the only one shown"
        case .excluded: "excluded"
        case .notIncluded: "hidden, because another value was selected"
        }
    }

    private var textColour: Color {
        switch state {
        case .allowed, .included: Palette.textPrimary
        case .excluded, .notIncluded: Palette.textQuiet
        }
    }
}

#Preview("Facet values") {
    VStack(alignment: .leading, spacing: 2) {
        FacetValueRow(
            facet: .type, value: FacetValue(value: "session.unlock", count: 2),
            state: .included, onSet: { _ in })
        FacetValueRow(
            facet: .type, value: FacetValue(value: "session.lock", count: 3),
            state: .notIncluded, onSet: { _ in })
        // The path case is the one this facet exists for and is demonstrated in
        // `Previews/FilterPreviews.swift`, where the values come off the fixture
        // rather than from a literal — `Scripts/check-layering.sh` forbids a
        // tilde-rooted string outside `Sources/Mock/`, and rightly: this file has
        // no way to prove its literal is display text and not a path.
        FacetValueRow(
            facet: .subject, value: FacetValue(value: "Xcode 16.2", count: 4),
            state: .excluded, onSet: { _ in })
        FacetValueRow(
            facet: .subject, value: FacetValue(value: "\"Time Machine\" · 4 TB", count: 2),
            state: .allowed, onSet: { _ in })
    }
    .frame(width: Metrics.facetPanelWidth)
    .padding()
    .background(Palette.surface)
}
