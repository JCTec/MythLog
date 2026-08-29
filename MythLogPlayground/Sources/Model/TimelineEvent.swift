import Foundation

/// One recorded event, as the viewer sees it.
///
/// `record` is the cumulative ledger ordinal. It is display-critical — the
/// inspector shows "#4629 · chained to #4628" — and in the real app it must be
/// computed across rotated segments, not as a line index.
struct TimelineEvent: Identifiable, Hashable, Sendable {
    let id = UUID()
    var record: Int
    var at: Date
    var kind: EventKind
    var label: String
    var detail: String
    var source: String
    var payloadKind: String

    /// How loudly the record asked to be noticed, carried through from
    /// ``AlarmEvent/severity``.
    ///
    /// It was dropped during mapping until filtering needed it, which meant
    /// "warning and above" — the single most useful investigative query — could
    /// not be expressed at all over data that already carried the answer.
    ///
    /// Defaulted so it can be added to a value type with a memberwise
    /// initialiser used in a dozen places without touching any of them. `.info`
    /// rather than `.debug`: a record whose severity is unknown should sit where
    /// an ordinary record sits, not below the floor of a filter somebody set.
    var severity: AlarmSeverity = .info

    var previousRecord: Int { record - 1 }

    /// The mark for *this record*, which is not always the mark for its category.
    ///
    /// Six categories is the right granularity for a filter chip and the wrong
    /// granularity for an icon beside a headline: "Screen locked" and "Screen
    /// unlocked" are opposite facts and shared one glyph, so the icon carried no
    /// information precisely where a reader was most likely to rely on it.
    ///
    /// Only the types where the direction is the whole point are listed. Anything
    /// else falls through to its category, which is the honest default — an
    /// invented glyph per payload kind would be a legend nobody can learn, and
    /// Wave 5 adds kinds that do not exist yet.
    var symbol: String {
        // The last dotted component, which is the part the shipping recorder and
        // the fixture agree on: `agent.agent.heartbeat` and `agent.heartbeat`
        // differ everywhere except the end. Same reasoning as
        // ``CoverageAnalysis/isHeartbeat(_:)``.
        switch payloadKind.split(separator: ".").last.map(String.init) ?? "" {
        case "lock": "lock.fill"
        case "unlock": "lock.open.fill"
        case "sleep": "moon.fill"
        case "wake": "sun.max"
        case "display": "display"
        case "mount": "externaldrive.badge.plus"
        case "unmount": "externaldrive.badge.minus"
        case "launched": "arrow.up.forward.app"
        case "terminated": "xmark.app"
        case "stop": "stop.circle"
        case "started": "play.circle"
        default: kind.symbol
        }
    }
}

extension TimelineEvent {
    /// The canonical JSON shown in the inspector payload block.
    var payloadJSON: String {
        let stamp = at.iso8601Text
        return """
        { "kind": "\(payloadKind)",
          "source": "\(source)",
          "detail": "\(detail)",
          "ts": "\(stamp)" }
        """
    }

    var hmacShort: String {
        let seed = UInt64(abs(record.hashValue % 0xFFFF_FFFF))
        return String(format: "%08x %08x", seed &* 2_654_435_761 % 0xFFFF_FFFF, seed &* 40_503 % 0xFFFF_FFFF)
    }
}

/// Date rendering.
///
/// `DateFormatter` and `ISO8601DateFormatter` are reference types with mutable
/// state and are not `Sendable`, so holding them in `static let` is rejected
/// under Swift 6 strict concurrency. `FormatStyle` values are `Sendable`
/// structs, so they can be created at the call site with no shared state at all.
extension Date {
    /// 24-hour "14:38" — verbatim so it never flips to 12-hour by locale.
    var clockText: String {
        formatted(
            .verbatim(
                "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
                timeZone: .current,
                calendar: .current
            )
        )
    }

    /// 24-hour "14:38:07".
    var clockSecondsText: String {
        formatted(
            .verbatim(
                "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
                timeZone: .current,
                calendar: .current
            )
        )
    }

    /// "Monday, August 4, 2026" — locale-aware, unlike the clock formats.
    var longDateText: String {
        formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    var iso8601Text: String {
        formatted(.iso8601)
    }
}
