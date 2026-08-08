import Foundation

/// The search box, and the structured tokens it understands.
///
/// # The box is still a search box
///
/// Typing `lease` searches for "lease", exactly as before. Everything below is
/// additive: someone who never learns a token loses nothing, and **no filter is
/// expressible only as a token** — every field here has a control beside the
/// chips that writes the same constraint. That rule is not stylistic. This app's
/// audience is people worried about their own Mac, not people who write queries,
/// and a filter reachable only through a syntax is a filter most of them cannot
/// undo.
///
/// # Tokens
///
/// ```text
/// lease                 anywhere in the headline, detail, or source
/// "screen unlocked"     the phrase, not the two words
/// kind:session          the category
/// type:unlock           the event type — `session.unlock`, `session.screen.unlocked`
/// source:fseventsd      who reported it
/// path:.build           anywhere in the detail line
/// severity:>=warning    warning and above; also > >= < <= and a bare value
/// -path:.build          any of the above, subtracted
/// ```
///
/// Terms combine with **and**. `kind:session -type:lock` is "session events that
/// are not locks".
///
/// # Tokens match loosely; checkboxes match exactly
///
/// `type:unlock` matches `session.unlock` *and* `session.screen.unlocked`, which
/// is what somebody typing it means and is also why it is the only thing that
/// works across two recorder vocabularies. A value ticked in a facet popover is
/// an exact value the window actually contains. The two are different tools and
/// the difference is deliberate: one is a search, the other is a selection.
///
/// # An unknown field is never silently ignored
///
/// `sevrity:>=warning` matches nothing as a field and everything as a typo. If
/// it were quietly treated as text the user would see an empty timeline and
/// have every reason to read it as "nothing happened" — which is the failure
/// this whole feature exists to prevent. So the token is searched as plain text
/// *and* reported in ``Parsed/unrecognisedFields``, which the interface shows.
struct FilterQuery: Hashable, Sendable, Codable {
    /// Exactly what was typed. The parse is derived, never stored, so the text
    /// and its meaning cannot drift apart.
    var text: String = ""

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    var parsed: Parsed { Parsed(text) }
}

extension FilterQuery {

    /// A severity comparison, as the ordered enum was built to express.
    enum SeverityConstraint: Hashable, Sendable {
        case atLeast(AlarmSeverity)
        case atMost(AlarmSeverity)
        case exactly(AlarmSeverity)

        func allows(_ severity: AlarmSeverity) -> Bool {
            switch self {
            case .atLeast(let bound): severity >= bound
            case .atMost(let bound): severity <= bound
            case .exactly(let value): severity == value
            }
        }

        var description: String {
            switch self {
            case .atLeast(let bound): "severity ≥ \(bound.rawValue)"
            case .atMost(let bound): "severity ≤ \(bound.rawValue)"
            case .exactly(let value): "severity \(value.rawValue)"
            }
        }
    }

    /// A field a token can name.
    ///
    /// `kind` is absent: a category needle is resolved to a `Set<EventKind>` at
    /// parse time, so matching it costs a set lookup rather than a string search
    /// on every event in the window.
    enum Field: String, Hashable, Sendable {
        case type
        case source
        case path

        func value(of event: TimelineEvent) -> String {
            switch self {
            case .type: event.payloadKind
            case .source: event.source
            case .path: event.detail
            }
        }
    }

    /// The parsed query.
    ///
    /// `Hashable` because it ends up inside ``TimelineDerivation/Request``, which
    /// is a cache key.
    struct Parsed: Hashable, Sendable {

        struct Term: Hashable, Sendable {
            enum Test: Hashable, Sendable {
                /// Anywhere in the headline, the detail, or the source.
                case anywhere(String)
                case field(Field, String)
                case kinds(Set<EventKind>)
                case severity(SeverityConstraint)
            }

            var test: Test
            var isNegated: Bool

            /// The term as a person would say it, for the removable pills.
            var description: String {
                let body =
                    switch test {
                    case .anywhere(let needle): "“\(needle)”"
                    case .field(let field, let needle): "\(field.rawValue) “\(needle)”"
                    case .kinds(let kinds):
                        kinds.isEmpty
                            ? "no such category"
                            : kinds.map(\.label).sorted().joined(separator: " or ")
                    case .severity(let constraint): constraint.description
                    }
                return isNegated ? "not \(body)" : body
            }

            func allows(_ event: TimelineEvent) -> Bool {
                let hit: Bool =
                    switch test {
                    case .anywhere(let needle):
                        event.label.containsCaseInsensitive(needle)
                            || event.detail.containsCaseInsensitive(needle)
                            || event.source.containsCaseInsensitive(needle)
                    case .field(let field, let needle):
                        field.value(of: event).containsCaseInsensitive(needle)
                    case .kinds(let kinds):
                        kinds.contains(event.kind)
                    case .severity(let constraint):
                        constraint.allows(event.severity)
                    }
                return isNegated ? !hit : hit
            }
        }

        var terms: [Term] = []

        /// Field names that looked like tokens and are not. Surfaced, never
        /// swallowed — see the note on ``FilterQuery``.
        var unrecognisedFields: [String] = []

        var isEmpty: Bool { terms.isEmpty }

        /// Every term must pass.
        func allows(_ event: TimelineEvent) -> Bool {
            for term in terms where !term.allows(event) { return false }
            return true
        }

        init() {}

        init(_ text: String) {
            for token in Self.tokenise(text) {
                var body = token
                var negated = false
                if body.hasPrefix("-"), body.count > 1 {
                    negated = true
                    body.removeFirst()
                }

                guard let test = Self.test(for: body, reporting: &unrecognisedFields) else { continue }
                terms.append(Term(test: test, isNegated: negated))
            }
        }

        // MARK: - Parsing

        /// Splits on whitespace, keeping double-quoted runs together.
        ///
        /// Written by hand rather than with a regular expression because the
        /// rule is one sentence long and a regex for it is not.
        private static func tokenise(_ text: String) -> [String] {
            var tokens = [String]()
            var current = ""
            var inQuotes = false

            for character in text {
                if character == "\"" {
                    inQuotes.toggle()
                    continue
                }
                if character.isWhitespace, !inQuotes {
                    if !current.isEmpty { tokens.append(current) }
                    current = ""
                    continue
                }
                current.append(character)
            }
            if !current.isEmpty { tokens.append(current) }
            return tokens
        }

        /// The test a token expresses, or `nil` when it expresses nothing.
        private static func test(for token: String, reporting unrecognised: inout [String]) -> Term.Test? {
            guard !token.isEmpty else { return nil }

            // A field candidate is `letters:value`. The letters requirement is
            // what stops a search for a clock time — `14:38` — from being read
            // as a field called "14" and reported as a typo.
            guard let colon = token.firstIndex(of: ":"),
                colon > token.startIndex,
                token[token.startIndex..<colon].allSatisfy({ $0.isLetter })
            else {
                return .anywhere(token)
            }

            let name = String(token[token.startIndex..<colon]).lowercased()
            let value = String(token[token.index(after: colon)...])
            guard !value.isEmpty else { return .anywhere(token) }

            switch name {
            case "kind", "category":
                return .kinds(kinds(matching: value))
            case "type", "event":
                return .field(.type, value)
            case "source", "from":
                return .field(.source, value)
            case "path", "detail", "subject", "file":
                return .field(.path, value)
            case "severity", "sev":
                guard let constraint = severityConstraint(value) else {
                    unrecognised.append("\(name):\(value)")
                    return .anywhere(token)
                }
                return .severity(constraint)
            default:
                unrecognised.append(name)
                return .anywhere(token)
            }
        }

        /// Categories whose raw value or label contains the needle.
        ///
        /// Resolved here, once, rather than per event. An empty result is a real
        /// answer — `kind:zzz` matches no category, so it matches no event — and
        /// is left to say so rather than being turned into "no constraint".
        private static func kinds(matching needle: String) -> Set<EventKind> {
            Set(
                EventKind.allCases.filter {
                    $0.rawValue.containsCaseInsensitive(needle)
                        || $0.label.containsCaseInsensitive(needle)
                })
        }

        /// `>=warning`, `>notice`, `<=info`, `warning`.
        private static func severityConstraint(_ value: String) -> SeverityConstraint? {
            var body = value.lowercased()
            var comparison = ""
            while let first = body.first, first == ">" || first == "<" || first == "=" {
                comparison.append(first)
                body.removeFirst()
            }

            guard let severity = AlarmSeverity(rawValue: body) ?? AlarmSeverity.matching(prefix: body) else {
                return nil
            }

            switch comparison {
            case "", "=", "==": return .exactly(severity)
            case ">=": return .atLeast(severity)
            case "<=": return .atMost(severity)
            case ">": return severity.next.map(SeverityConstraint.atLeast) ?? .exactly(severity)
            case "<": return severity.previous.map(SeverityConstraint.atMost) ?? .exactly(severity)
            default: return nil
            }
        }
    }
}

extension AlarmSeverity {
    /// The unique severity this abbreviation names — `warn`, `crit`, `deb`.
    /// Ambiguous or unknown abbreviations return `nil` rather than a guess.
    static func matching(prefix: String) -> AlarmSeverity? {
        guard !prefix.isEmpty else { return nil }
        let hits = allCases.filter { $0.rawValue.hasPrefix(prefix) }
        return hits.count == 1 ? hits[0] : nil
    }

    var next: AlarmSeverity? {
        let ordered = Self.allCases.sorted()
        return ordered.firstIndex(of: self).flatMap { $0 + 1 < ordered.count ? ordered[$0 + 1] : nil }
    }

    var previous: AlarmSeverity? {
        let ordered = Self.allCases.sorted()
        return ordered.firstIndex(of: self).flatMap { $0 > 0 ? ordered[$0 - 1] : nil }
    }

    /// Capitalised for display. The raw value is what a token names, so the two
    /// stay recognisably the same word.
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

extension String {
    /// Case-insensitive substring search that does not build a lowercased copy
    /// of the haystack.
    ///
    /// This runs once per term per event in the window. `lowercased().contains`
    /// allocates a string for every one of them, which over a window holding a
    /// quarter of a million events is the difference between a filter that keeps
    /// up with a trackpad and one that does not.
    func containsCaseInsensitive(_ needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        return range(of: needle, options: .caseInsensitive) != nil
    }
}
