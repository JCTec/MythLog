import Foundation

/// A dimension a filter can constrain, and the value one event has in it.
///
/// # Why this is one type rather than four sets of fields
///
/// Every dimension needs the same five things: a name a person reads, the value
/// to read off an event, the list of values actually present in the window, an
/// include set, and an exclude set. Written out per dimension that is four
/// copies of the same interface and four places for "excluded wins over
/// included" to be decided differently. The interface is generic over this enum
/// for the same reason — one popover renders every facet, so a facet added for
/// Wave 5 needs no new view.
///
/// # Severity is deliberately not a facet
///
/// ``AlarmSeverity`` is `Comparable`, and the query people actually have is
/// "warning and above" — a threshold, not a set. Modelling it as a set of five
/// checkboxes would express "notice but not warning", which nobody wants, and
/// would fail to express the one thing everybody wants without ticking two
/// boxes and remembering to tick a third when a sixth severity is added. So it
/// lives on ``EventFilter/minimumSeverity`` as the ordered comparison the type
/// was built for.
enum EventFacet: String, CaseIterable, Identifiable, Sendable, Codable {
    /// ``EventKind`` — the six chips.
    case category
    /// `payloadKind`: `session.unlock`, `file.modify`. One level below category,
    /// and the dimension the whole feature turns on.
    case type
    /// Who observed it: `loginwindow`, `fseventsd`, `com.apple.Safari`.
    case source
    /// What it was about: the containing folder, the application, the volume.
    case subject

    var id: String { rawValue }

    var label: String {
        switch self {
        case .category: "Category"
        case .type: "Event type"
        case .source: "Source"
        case .subject: "Subject"
        }
    }

    /// Used mid-sentence in the filter summary: "excluding 2 subjects".
    func noun(count: Int) -> String {
        let singular =
            switch self {
            case .category: "category"
            case .type: "event type"
            case .source: "source"
            case .subject: "subject"
            }
        return count == 1 ? singular : singular + "s"
    }

    /// One line explaining what the dimension is, for the popover header. The
    /// audience is explicitly not all technical, and `payloadKind` is not a word.
    var explanation: String {
        switch self {
        case .category: "The six groups the chips stand for."
        case .type: "Exactly what happened — one level below the category."
        case .source: "The part of macOS that reported it."
        case .subject: "The file, folder, app, or volume it happened to."
        }
    }

    /// How a value stored in a filter is compared to an event's value.
    enum Matching: Sendable {
        /// The two strings are the same.
        case exact
        /// The stored value is a prefix of the event's. Only ``subject`` uses
        /// this, and it is the point of that facet: excluding
        /// `~/Projects/mythlog/.build/` has to take everything underneath it
        /// too, or a build storm has to be excluded one object file at a time.
        case prefix

        func matches(_ value: String, _ stored: String) -> Bool {
            switch self {
            case .exact: value == stored
            case .prefix: value.hasPrefix(stored)
            }
        }
    }

    /// The facets a category's detail panel offers.
    ///
    /// ``category`` is absent: the chip *is* that dimension, and a control
    /// inside its own popover that turned the category off would be a switch
    /// that closes the room it is in.
    static let detail: [EventFacet] = [.type, .source, .subject]

    var matching: Matching {
        switch self {
        case .subject: .prefix
        case .category, .type, .source: .exact
        }
    }

    /// This event's value in this dimension.
    ///
    /// A raw string for every facet, including the category: the alternative is
    /// four parallel typed sets and a filter model that cannot be iterated. The
    /// category's values are always ``EventKind`` raw values, which is what
    /// ``EventKind/init(rawValue:)`` turns back for display.
    func value(of event: TimelineEvent) -> String {
        switch self {
        case .category: event.kind.rawValue
        case .type: event.payloadKind
        case .source: event.source
        case .subject: event.subject
        }
    }

    /// How this facet's raw value should be shown to a person.
    ///
    /// Only the category needs translating; the rest are already the strings the
    /// ledger carries, and inventing prettier names for them would mean the
    /// value shown and the value a query token has to name are different.
    func display(_ value: String) -> String {
        guard self == .category else { return value }
        return EventKind(rawValue: value)?.label ?? value
    }
}

extension TimelineEvent {
    /// What this event is *about*, as a value a filter can name.
    ///
    /// For a file event that is the containing folder; for an app it is the
    /// application; for a drive the volume. All three arrive here as `detail`,
    /// which is the single field ``LedgerEventMapping`` fills from whichever
    /// metadata key the record happened to carry — `path`, `application`,
    /// `bundleIdentifier`, `volume`.
    ///
    /// # A path collapses to its folder
    ///
    /// The useful subtraction is "everything under `.build/`", never one object
    /// file: the fixture's build storm is 312 distinct paths and one folder. So
    /// a value containing a separator becomes everything up to and including the
    /// last one, and matching is by prefix — which also means excluding a folder
    /// takes its subfolders, as anyone who typed it would expect.
    ///
    /// Anything without a separator is its own subject, unchanged.
    var subject: String {
        guard let separator = detail.lastIndex(of: "/") else { return detail }
        return String(detail[...separator])
    }
}
