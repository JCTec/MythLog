import Foundation

/// One dimension's include and exclude sets.
///
/// # Include is a whitelist that only exists when it is non-empty
///
/// An empty `included` means "no opinion", not "nothing". That is the only
/// workable default: a filter starts empty and shows everything, and the
/// alternative — pre-filling `included` with every value in the window — would
/// mean the filter silently hides any value that arrives afterwards. Wave 5 adds
/// event types that do not exist yet, and a filter saved today must not hide
/// them the day they land.
///
/// # Exclusion beats inclusion, always
///
/// If a value is in both sets it is excluded. Subtraction is the more specific
/// statement — somebody who ticked "Files" and then excluded `.build/` meant the
/// second thing — and a rule that resolved it the other way would make the
/// exclusion silently do nothing.
struct FacetSelection: Hashable, Sendable, Codable {
    var included: Set<String> = []
    var excluded: Set<String> = []

    var isEmpty: Bool { included.isEmpty && excluded.isEmpty }

    func allows(_ value: String, matching: EventFacet.Matching) -> Bool {
        switch matching {
        case .exact:
            if excluded.contains(value) { return false }
            return included.isEmpty || included.contains(value)
        case .prefix:
            if excluded.contains(where: { value.hasPrefix($0) }) { return false }
            return included.isEmpty || included.contains { value.hasPrefix($0) }
        }
    }

    /// Whether this value is currently ticked in — which is not the same as
    /// being allowed. A value nobody named is allowed and is not included.
    func state(of value: String) -> ValueState {
        if excluded.contains(value) { return .excluded }
        if included.contains(value) { return .included }
        return included.isEmpty ? .allowed : .notIncluded
    }

    /// What the popover draws beside a value.
    enum ValueState: Hashable, Sendable {
        /// No opinion has been expressed and it passes.
        case allowed
        /// Explicitly named as one of the values to keep.
        case included
        /// Explicitly subtracted.
        case excluded
        /// Something else was included, so this is hidden without being named.
        /// Distinct from ``excluded`` because undoing it is a different action.
        case notIncluded
    }

    mutating func include(_ value: String) {
        excluded.remove(value)
        included.insert(value)
    }

    mutating func exclude(_ value: String) {
        included.remove(value)
        excluded.insert(value)
    }

    mutating func clear(_ value: String) {
        included.remove(value)
        excluded.remove(value)
    }
}

/// Everything the interface is currently hiding, as one value.
///
/// # Why the dimensions live in a dictionary
///
/// Four typed properties would be four popovers, four sets of "excluded wins"
/// logic, and a fifth of each when Wave 5 lands drives and user switching. The
/// interface renders ``EventFacet/allCases``; a facet added there needs no new
/// view and no new branch here.
///
/// # What this may never do
///
/// Two rules, and they are the reason the type is documented at this length:
///
/// 1. **No filter may hide a coverage gap.** Gaps are not events — they are the
///    absence of them — and they are derived separately in
///    ``TimelineDerivation``, where no filter can reach them.
/// 2. **No filter may hide an untrusted record.** Filtering answers "what
///    happened"; it must never answer "can this be believed". A record past the
///    trust boundary is shown whatever the filter says, and
///    ``TimelineDerivation/Result/forcedUntrustedCount`` reports how many, so
///    the interface can say why they are there.
///
/// Both are asserted in `FilterInvariantTests`, over generated ledgers as well
/// as the fixture.
struct EventFilter: Hashable, Sendable, Codable {

    /// Per-dimension selections. A facet absent from the dictionary is
    /// unconstrained, which is the same thing an empty ``FacetSelection`` means —
    /// the subscript hides the difference so no caller has to know.
    private var facets: [EventFacet: FacetSelection] = [:]

    /// "Warning and above". `nil` is no constraint; ``AlarmSeverity/debug`` is a
    /// constraint that happens to admit everything, and the two stay distinct so
    /// the summary can say which one the user chose.
    var minimumSeverity: AlarmSeverity?

    var query = FilterQuery()

    init() {}

    subscript(facet: EventFacet) -> FacetSelection {
        get { facets[facet] ?? FacetSelection() }
        set {
            if newValue.isEmpty {
                facets.removeValue(forKey: facet)
            } else {
                facets[facet] = newValue
            }
        }
    }

    // MARK: - Matching

    /// Whether this event passes, ignoring the two exemptions above — those are
    /// applied by ``TimelineDerivation``, which is the only place that knows
    /// about gaps and about the trust boundary.
    ///
    /// The parsed query is passed in rather than read from ``query`` because
    /// parsing it once per derivation instead of once per event is the whole
    /// difference over a window holding a quarter of a million records.
    func allows(_ event: TimelineEvent, query parsed: FilterQuery.Parsed) -> Bool {
        if let minimumSeverity, event.severity < minimumSeverity { return false }

        for (facet, selection) in facets {
            guard selection.allows(facet.value(of: event), matching: facet.matching) else { return false }
        }

        return parsed.allows(event)
    }

    // MARK: - Categories

    /// Whether a category's chip reads as on.
    func includes(_ kind: EventKind) -> Bool {
        self[.category].allows(kind.rawValue, matching: .exact)
    }

    /// The chips that are on, which is the shape the rest of the app had before
    /// facets existed and still the most useful summary of the category row.
    var enabledKinds: Set<EventKind> {
        Set(EventKind.allCases.filter(includes))
    }

    /// Clicking a chip.
    ///
    /// Turning one off is an exclusion, which is why a chip and a value in a
    /// popover are the same mechanism rather than two that have to agree.
    mutating func toggle(_ kind: EventKind) {
        var selection = self[.category]
        let value = kind.rawValue
        if includes(kind) {
            selection.exclude(value)
        } else {
            selection.excluded.remove(value)
            // Only re-include when something else is explicitly included;
            // otherwise removing the exclusion is enough and adding to the
            // whitelist would silently hide every other category.
            if !selection.included.isEmpty { selection.included.insert(value) }
        }
        self[.category] = selection
    }

    // MARK: - State

    /// Whether anything at all is being hidden.
    var isFiltering: Bool {
        !facets.isEmpty || minimumSeverity != nil || !query.isEmpty
    }

    /// Whether anything beyond the category chips is active.
    ///
    /// This is what decides whether a chip shows one number or two — see
    /// ``FilterChip``. With only chips in play a chip's count is unambiguous;
    /// the moment a sub-filter exists it is not, and the chip has to show both.
    var hasSubFilters: Bool {
        facets.keys.contains { $0 != .category } || minimumSeverity != nil || !query.isEmpty
    }

    static let none = EventFilter()

    /// Only these categories, plus an optional plain search. The shape the
    /// interface had before facets, kept because it is genuinely the common case
    /// and because presets and tests both want to say it in one line.
    static func showing(kinds: Set<EventKind>, query text: String = "") -> EventFilter {
        var filter = EventFilter()
        var selection = FacetSelection()
        selection.excluded = Set(EventKind.allCases.filter { !kinds.contains($0) }.map(\.rawValue))
        filter[.category] = selection
        filter.query.text = text
        return filter
    }

    // MARK: - Describing itself

    /// The active constraints, each removable.
    ///
    /// This is what makes a preset teachable rather than magic: applying
    /// "Physical access" fills this list with the event types it expanded to, so
    /// the next thing the user learns is that those types exist and can be
    /// adjusted one at a time.
    ///
    /// A facet with more than ``collapseThreshold`` values collapses to one
    /// summarising pill. Twenty separate chips saying `~/…/node_modules/` is not
    /// more honest than one saying "excluding 20 subjects" — it is just a filter
    /// bar nobody can read, and the count is the part that matters.
    static let collapseThreshold = 4

    var constraints: [FilterConstraint] {
        var out = [FilterConstraint]()

        for facet in EventFacet.allCases {
            let selection = self[facet]
            out += Self.constraints(for: facet, values: selection.included, isExclusion: false)
            out += Self.constraints(for: facet, values: selection.excluded, isExclusion: true)
        }

        if let minimumSeverity {
            out.append(
                FilterConstraint(
                    id: "severity",
                    text: minimumSeverity == .debug
                        ? "every severity"
                        : "\(minimumSeverity.label) and above",
                    removal: .severity))
        }

        let parsed = query.parsed
        if !parsed.isEmpty {
            out.append(
                FilterConstraint(
                    id: "query",
                    text: parsed.terms.map(\.description).joined(separator: " and "),
                    removal: .query))
        }

        return out
    }

    private static func constraints(
        for facet: EventFacet, values: Set<String>, isExclusion: Bool
    ) -> [FilterConstraint] {
        guard !values.isEmpty else { return [] }
        let verb = isExclusion ? "excluding" : "only"

        guard values.count <= collapseThreshold else {
            return [
                FilterConstraint(
                    id: "\(facet.rawValue).\(isExclusion)",
                    text: "\(verb) \(values.count) \(facet.noun(count: values.count))",
                    removal: .wholeFacet(facet, isExclusion: isExclusion))
            ]
        }

        return values.sorted().map { value in
            FilterConstraint(
                id: "\(facet.rawValue).\(isExclusion).\(value)",
                text: "\(verb) \(facet.display(value))",
                removal: .value(facet, value: value))
        }
    }

    /// One sentence, for VoiceOver and for the person who reads exactly one.
    var summarySentence: String {
        guard isFiltering else { return "No filter is active." }
        return "Filtered: " + constraints.map(\.text).joined(separator: ", ") + "."
    }

    // MARK: - Undoing

    mutating func remove(_ removal: FilterConstraint.Removal) {
        switch removal {
        case .value(let facet, let value):
            self[facet].clear(value)
        case .wholeFacet(let facet, let isExclusion):
            var selection = self[facet]
            if isExclusion { selection.excluded.removeAll() } else { selection.included.removeAll() }
            self[facet] = selection
        case .severity:
            minimumSeverity = nil
        case .query:
            query.text = ""
        }
    }
}

/// One active constraint, as the filter bar shows it.
struct FilterConstraint: Identifiable, Hashable, Sendable {
    enum Removal: Hashable, Sendable {
        case value(EventFacet, value: String)
        case wholeFacet(EventFacet, isExclusion: Bool)
        case severity
        case query
    }

    var id: String
    var text: String
    var removal: Removal
}

// MARK: - Coding

/// Written out as an array of pairs rather than as a dictionary.
///
/// Swift can encode an enum-keyed dictionary, and the encoding it produces
/// depends on conformances that are easy to acquire by accident and awkward to
/// notice losing. Saved filters are persisted across launches and across
/// versions, so the stored shape is written down here explicitly and sorted, and
/// an unknown facet name in a stored filter is skipped rather than failing the
/// whole decode — a filter saved by a later build must not make this one refuse
/// to launch.
extension EventFilter {
    private enum CodingKeys: String, CodingKey {
        case facets, minimumSeverity, query
    }

    private struct StoredFacet: Codable {
        var facet: String
        var selection: FacetSelection
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stored = try container.decodeIfPresent([StoredFacet].self, forKey: .facets) ?? []
        for entry in stored {
            guard let facet = EventFacet(rawValue: entry.facet) else { continue }
            self[facet] = entry.selection
        }
        minimumSeverity = try container.decodeIfPresent(AlarmSeverity.self, forKey: .minimumSeverity)
        query = try container.decodeIfPresent(FilterQuery.self, forKey: .query) ?? FilterQuery()
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            facets.keys.sorted { $0.rawValue < $1.rawValue }
                .map { StoredFacet(facet: $0.rawValue, selection: facets[$0] ?? FacetSelection()) },
            forKey: .facets)
        try container.encodeIfPresent(minimumSeverity, forKey: .minimumSeverity)
        try container.encode(query, forKey: .query)
    }
}
