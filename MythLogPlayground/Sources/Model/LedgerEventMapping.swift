import Foundation

/// Turns a ledger record into the row the user reads.
///
/// # Why this is one place and not scattered through the views
///
/// The ledger stores `source`, `name`, and a `[String: String]` of metadata,
/// because that is what survives a schema frozen by a hash chain (see
/// ``AlarmEvent``). The interface needs a category, a headline, and a detail
/// line. Every view that did that translation itself would drift, and two views
/// disagreeing about what a record *is* is exactly the failure this app cannot
/// afford.
///
/// # Unknown records are shown, not dropped
///
/// A record whose `source.name` this build does not recognise still appears,
/// categorised as ``EventKind/health`` and labelled with its raw name. Dropping
/// it would mean a ledger written by a newer recorder renders as a history with
/// holes in it — the same class of lie as a coverage gap that is not drawn.
enum LedgerEventMapping {

    static func timelineEvent(from entry: LedgerEntry) -> TimelineEvent {
        let event = entry.event
        let qualified = "\(event.source).\(event.name)"

        return TimelineEvent(
            record: entry.ordinal,
            at: event.observedAt,
            kind: kind(source: event.source, name: event.name),
            label: label(for: qualified, event: event),
            detail: detail(for: event),
            source: event.source,
            payloadKind: qualified,
            severity: event.severity
        )
    }

    // MARK: - Category

    /// Categorised from `source` first, falling back to the name's prefix.
    ///
    /// Source is the more reliable signal: the recorder's own capture sources
    /// are named for what they observe, whereas names vary with what happened.
    static func kind(source: String, name: String) -> EventKind {
        switch source {
        case "session", "loginwindow": return .session
        case "power", "kernel": return .power
        case "apps", "application": return .apps
        case "filesystem", "fseventsd", "file": return .files
        case "drives", "diskarbitrationd", "volume": return .drives
        case "agent", "health", "ledger", "mythlogd", "heartbeat": return .health
        default: break
        }

        // Fall back to the name's prefix, which follows the same vocabulary.
        switch name.split(separator: ".").first.map(String.init) ?? name {
        case "screen", "session", "user": return .session
        case "power", "sleep", "wake", "display": return .power
        case "app": return .apps
        case "file", "path": return .files
        case "drive", "volume", "disk": return .drives
        default: return .health
        }
    }

    // MARK: - Headline

    /// The plain-English headline, for the record kinds this build knows.
    ///
    /// The table is deliberately explicit rather than clever: every string here
    /// is one a user reads, and generating them from the identifier produces
    /// "Screen unlocked" for some records and "Path changed 2" for others.
    private static let headlines: [String: String] = [
        "session.screen.locked": "Screen locked",
        "session.screen.unlocked": "Screen unlocked",
        "session.user.switched": "User switched",
        "power.power.sleep": "System slept",
        "power.power.wake": "Wake from sleep",
        "power.display.connected": "Display connected",
        "power.display.disconnected": "Display disconnected",
        "apps.app.launched": "App launched",
        "apps.app.terminated": "App terminated",
        "apps.app.activated": "App activated",
        "filesystem.path.changed": "File changed",
        "drives.volume.mounted": "Volume mounted",
        "drives.volume.unmounted": "Volume unmounted",
        "agent.agent.started": "Recorder started",
        "agent.agent.stopped": "Recorder stopped",
        "agent.agent.heartbeat": "Recorder heartbeat",
        "ledger.ledger.rotated": "Ledger segment rotated",
    ]

    static func label(for qualified: String, event: AlarmEvent) -> String {
        if let headline = headlines[qualified] { return headline }
        if let message = event.metadata["message"], !message.isEmpty { return message }
        // Unknown but present. Better a raw identifier than a missing row.
        return qualified
    }

    // MARK: - Detail

    /// The second line: whatever the record carries that is worth reading.
    ///
    /// Metadata keys are tried in a fixed order so the same kind of record
    /// always shows the same field, then falls back to the whole dictionary
    /// rendered stably. `.sorted()` matters — an unordered dictionary would make
    /// the same record read differently on different launches.
    private static let detailKeys = [
        "detail", "path", "application", "bundleIdentifier", "volume", "device",
        "reason", "archivedSegment", "message",
    ]

    static func detail(for event: AlarmEvent) -> String {
        for key in detailKeys {
            if let value = event.metadata[key], !value.isEmpty { return value }
        }

        guard !event.metadata.isEmpty else { return event.severity.rawValue }
        return
            event.metadata
            .sorted { $0.key < $1.key }
            .prefix(3)
            .map { "\($0.key): \($0.value)" }
            .joined(separator: " · ")
    }
}
