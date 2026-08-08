import Foundation

/// One value a facet takes in the current window, and how often.
struct FacetValue: Identifiable, Hashable, Sendable {
    var value: String
    var count: Int

    var id: String { value }
}

/// The values one facet takes in the current window.
///
/// # Derived from the window, never from a list
///
/// Every value here was read off an event that is on screen right now. Nothing
/// is hardcoded, which is the only way this survives Wave 5: drives, displays,
/// and user switching bring event types that do not exist in this build, and a
/// list written today would be wrong the day they land — and wrong in the
/// direction that matters, offering a filter for something the ledger no longer
/// contains and none for what it does.
///
/// # Truncation is stated, never silent
///
/// A window over a build storm has hundreds of distinct subjects. The popover
/// shows the commonest and says how many it did not show. A list that quietly
/// stopped at fifty would let someone conclude a value is not present when it
/// is — the same class of lie as an undrawn coverage gap, at a smaller scale.
struct FacetValues: Equatable, Sendable {
    var facet: EventFacet
    /// The category this was derived within, or `nil` for the whole window.
    var kind: EventKind?
    /// Commonest first. Ties break alphabetically so the order is stable across
    /// derivations — a list that reshuffles under the pointer is unusable.
    var values: [FacetValue]
    /// Distinct values that exist in the window and are not in ``values``.
    var omitted: Int

    var totalDistinct: Int { values.count + omitted }

    var isEmpty: Bool { values.isEmpty }

    static func empty(facet: EventFacet, kind: EventKind? = nil) -> FacetValues {
        FacetValues(facet: facet, kind: kind, values: [], omitted: 0)
    }

    /// Builds from raw counts, applying the cap and recording what it cost.
    init(facet: EventFacet, kind: EventKind?, counts: [String: Int], limit: Int) {
        self.facet = facet
        self.kind = kind

        let sorted = counts
            .map { FacetValue(value: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.value < $1.value : $0.count > $1.count }

        values = Array(sorted.prefix(limit))
        omitted = max(0, sorted.count - values.count)
    }

    init(facet: EventFacet, kind: EventKind?, values: [FacetValue], omitted: Int) {
        self.facet = facet
        self.kind = kind
        self.values = values
        self.omitted = omitted
    }
}
