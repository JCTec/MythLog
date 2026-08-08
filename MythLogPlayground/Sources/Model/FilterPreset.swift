import Foundation

/// A question somebody actually arrives with, as one click.
///
/// # Why presets and not just a better filter editor
///
/// "Every time this Mac was unlocked" is not an obscure query. For someone who
/// opened this app because they are worried, it is *the* question — and today
/// answering it means knowing that `Session` covers both lock and unlock, that
/// there is a level below the category, and what that level's values are called.
/// That is three things to learn before the first answer.
///
/// A preset is one click. It is also **not a mode**: applying one writes an
/// ordinary ``EventFilter`` that the user can then adjust value by value, and the
/// filter bar shows exactly what it expanded to. So the preset answers the
/// question and, on the way, teaches the model that answered it.
///
/// # Presets name behaviour, not identifiers
///
/// A preset cannot hardcode `session.unlock`, because that is not what every
/// ledger calls it: this build's fixture writes `session.unlock` and the shipping
/// recorder writes `session.screen.unlocked`. Nor can it hardcode both, because
/// Wave 5 will write a third.
///
/// So a preset carries *tokens* — "unlock", "wake", "mount" — matched against
/// the components of the event types the window actually contains, and resolves
/// to the concrete types found there. A token that matches nothing is reported
/// rather than silently contributing an empty set: "no unlock events in this
/// window" is an answer, and an empty timeline with no explanation is not.
struct FilterPreset: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    /// The question, in the words somebody would ask it in.
    var question: String
    var symbol: String

    /// Matched against each dot-separated component of an event type, by prefix.
    ///
    /// Prefix rather than substring, and that is load-bearing: `unmounted`
    /// contains "mount" but does not begin with it, so "drive mounted" does not
    /// quietly drag in "drive unmounted". `unlocked` does begin with "unlock",
    /// which is the case this has to catch.
    var typeTokens: [String]

    var minimumSeverity: AlarmSeverity?

    /// Whether this preset's meaning depends on the event types present. The
    /// severity preset does not, and must not report itself as empty when a
    /// window happens to contain no unlocks.
    var usesTypes: Bool { !typeTokens.isEmpty }

    static let all: [FilterPreset] = [
        FilterPreset(
            id: "unlocks",
            title: "Unlocks only",
            question: "Every time someone got in.",
            symbol: "lock.open",
            typeTokens: ["unlock"]
        ),
        FilterPreset(
            id: "physical",
            title: "Physical access",
            question: "Anyone who was at the machine.",
            symbol: "hand.raised",
            // "lid" matches nothing this build writes and is here deliberately:
            // it is what a lid event would be called, and a preset that has to
            // be edited when the recorder gains one is a preset that will not be.
            typeTokens: ["unlock", "wake", "display", "mount", "lid", "switch", "userswitch"]
        ),
        FilterPreset(
            id: "warnings",
            title: "Warnings and above",
            question: "Everything the recorder thought was worth raising.",
            symbol: "exclamationmark.triangle",
            typeTokens: [],
            minimumSeverity: .warning
        ),
    ]

    /// Whether an event type matches this preset.
    func matches(type: String) -> Bool {
        let components = type.split(separator: ".").map { $0.lowercased() }
        return typeTokens.contains { token in
            components.contains { $0.hasPrefix(token) }
        }
    }

    /// This preset against the event types the window actually holds.
    func resolved(against types: FacetValues) -> Resolution {
        let matched = types.values.map(\.value).filter(matches(type:)).sorted()

        var filter = EventFilter()
        if usesTypes, !matched.isEmpty {
            var selection = FacetSelection()
            selection.included = Set(matched)
            filter[.type] = selection
        }
        filter.minimumSeverity = minimumSeverity

        return Resolution(
            preset: self,
            filter: filter,
            matchedTypes: matched,
            // A type-driven preset that matched nothing would produce a filter
            // with no type constraint at all — which shows *everything*, the
            // exact opposite of what was asked for. So it is refused, loudly.
            foundNothing: usesTypes && matched.isEmpty,
            unlistedTypes: types.omitted
        )
    }

    /// What applying a preset to a particular window produced.
    struct Resolution: Equatable, Sendable {
        var preset: FilterPreset
        var filter: EventFilter
        /// The concrete event types the tokens found. Shown, so the preset
        /// teaches rather than hides.
        var matchedTypes: [String]
        /// The window contains none of what this preset is about.
        var foundNothing: Bool
        /// Distinct types the catalog capped away. Non-zero means the expansion
        /// may be incomplete, and the interface says so rather than implying the
        /// list is exhaustive.
        var unlistedTypes: Int

        var explanation: String {
            if foundNothing {
                return "No \(preset.title.lowercased()) in this window. "
                    + "Nothing was filtered — widen the window, or pan back through history."
            }
            if let severity = preset.minimumSeverity, matchedTypes.isEmpty {
                return "Showing \(severity.rawValue) and above."
            }
            let list = matchedTypes.joined(separator: ", ")
            let tail = unlistedTypes > 0
                ? " (\(unlistedTypes) less common type(s) in this window were not searched)"
                : ""
            return "Expanded to: \(list)\(tail)"
        }
    }
}
