import Foundation

/// One way to write a duration, used everywhere a duration is written.
///
/// There were three. A coverage gap said "4 h 24 min", the timeline's level chip
/// said "6 d", and the two disagreed about whether a bare hour count was "1 h" or
/// "60 min" — so the same span could be described two ways on one screen, which
/// invites the reader to wonder whether they are the same span.
///
/// The rule: the two largest non-zero units, largest first, never more than two.
/// "22 h 25 min", "16 min", "3 d 4 h". Precision below the second unit is noise
/// at every scale this app draws, and a third unit is how "1 d 3 h 47 min"
/// happens.
enum DurationLabel {

    /// - Parameter seconds: a non-negative interval. Negative intervals are
    ///   clamped to zero rather than rendered with a sign — a negative duration
    ///   is an arithmetic bug upstream, and printing "-3 min" hides it.
    static func text(_ seconds: TimeInterval) -> String {
        let total = Int((max(0, seconds) / 60).rounded())

        if total >= 1440 {
            let days = total / 1440
            let hours = (total % 1440) / 60
            return hours == 0 ? "\(days) d" : "\(days) d \(hours) h"
        }
        if total >= 60 {
            let hours = total / 60
            let minutes = total % 60
            return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
        }
        // Deliberately "0 min" rather than "0 s": this app's smallest meaningful
        // duration is a minute, and a sub-minute silence is not a coverage gap
        // under any threshold it supports.
        return "\(total) min"
    }
}

extension Date {
    /// "Fri 13:31" — the clock with the weekday in front.
    ///
    /// For ranges that cross midnight, where "13:31 – 11:56" is not merely
    /// ambiguous but reads as a *negative* span until the reader works out that
    /// a day boundary went past. Twenty-two hours of unrecorded time looked like
    /// a typo.
    var weekdayClockText: String {
        "\(formatted(.dateTime.weekday(.abbreviated))) \(clockText)"
    }
}

extension ClosedRange where Bound == Date {
    /// Whether the two ends fall on different calendar days.
    var crossesDayBoundary: Bool {
        !Calendar.current.isDate(lowerBound, inSameDayAs: upperBound)
    }
}

/// A time range written the shortest way that stays unambiguous.
///
/// Within one day the weekday is redundant and adding it to every range would
/// cost width in the densest part of the interface for nothing. Across a day
/// boundary it is the difference between a readable span and an apparent
/// contradiction, so it appears exactly there.
enum RangeLabel {
    /// The two ends in the order they happened.
    ///
    /// Callers hand over window edges and gap bounds, and one of those arriving
    /// inverted is an arithmetic bug upstream — the same class of bug
    /// ``DurationLabel/text(_:)`` clamps a negative interval for. Normalising in
    /// one place is what keeps the two halves of a label from disagreeing: the
    /// version that reordered only the *text* printed a correctly ordered range
    /// followed by "(0 min)", which is worse than either mistake alone, because
    /// it reads as a real range that lasted no time.
    private static func ordered(_ start: Date, _ end: Date) -> (Date, Date) {
        start <= end ? (start, end) : (end, start)
    }

    static func text(from start: Date, to end: Date) -> String {
        let (first, last) = ordered(start, end)
        if (first...last).crossesDayBoundary {
            return "\(first.weekdayClockText) → \(last.weekdayClockText)"
        }
        return "\(first.clockText) – \(last.clockText)"
    }

    /// The same range with its duration appended: "Fri 13:31 → Sat 11:56 (22 h 25 min)".
    static func textWithDuration(from start: Date, to end: Date) -> String {
        let (first, last) = ordered(start, end)
        return "\(text(from: first, to: last)) (\(DurationLabel.text(last.timeIntervalSince(first))))"
    }
}
