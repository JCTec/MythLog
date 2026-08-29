import Foundation
import Testing

@testable import MythLog

/// One way to write a duration, and one way to write a range.
///
/// These two are the most-shared strings in the app — a coverage gap, the zoom
/// pill, the position readout and the timeline's own region labels all print
/// through them — which is exactly why they are worth pinning. The failure they
/// exist to prevent is not a crash: it is one span described two ways on one
/// screen, which invites the reader to wonder whether they are the same span.
@Suite("Durations in words")
struct DurationLabelTests {

    /// The rule: at most two units, largest first. A third unit is how
    /// "1 d 3 h 47 min" happens, and precision below the second unit is noise at
    /// every scale this app draws.
    @Test(
        "the ladder from nothing to a day and a half",
        arguments: [
            (0.0, "0 min"),
            // Rounded to the nearest minute rather than truncated, so a
            // near-minute silence is not reported as no silence at all.
            (59.0, "1 min"),
            (60.0, "1 min"),
            (3600.0, "1 h"),
            (3660.0, "1 h 1 min"),
            // A second short of a day still rounds to a day: the second unit
            // would be "23 h 60 min", which is not a thing.
            (86_399.0, "1 d"),
            (86_400.0, "1 d"),
            (90_000.0, "1 d 1 h"),
        ] as [(TimeInterval, String)])
    func ladder(seconds: TimeInterval, expected: String) {
        #expect(DurationLabel.text(seconds) == expected)
    }

    /// The value `CoverageGapTests` depends on, asserted here too so the reason
    /// it must not move is written next to the formatter rather than only next
    /// to the gap.
    @Test("exactly one hour is an hour, never sixty minutes")
    func oneHour() {
        #expect(DurationLabel.text(3600) == "1 h")
    }

    /// A negative duration is an arithmetic bug upstream. Printing "-3 min"
    /// hides it behind something that looks like a label.
    @Test("a negative interval clamps to zero rather than printing a sign")
    func negative() {
        #expect(DurationLabel.text(-1) == "0 min")
        #expect(DurationLabel.text(-90_000) == "0 min")
        #expect(!DurationLabel.text(-3600).contains("-"))
    }

    /// Asserted over a sweep rather than at chosen points, because the third
    /// unit appears at boundaries nobody picks by hand.
    @Test("never more than two units, at any duration")
    func atMostTwoUnits() {
        let units = ["d", "h", "min"]
        for seconds in stride(from: 0.0, through: 400 * 86_400.0, by: 617.0) {
            let text = DurationLabel.text(seconds)
            let present = units.filter { unit in
                text.split(separator: " ").contains(Substring(unit))
            }
            #expect(present.count <= 2, "\(seconds) s rendered as \(text)")
            #expect(!present.isEmpty, "\(seconds) s rendered as \(text)")
        }
    }
}

@Suite("Time ranges in words")
struct RangeLabelTests {

    private let calendar = Calendar.current

    private func date(day: Int, hour: Int, minute: Int) -> Date {
        calendar.date(
            from: DateComponents(
                year: 2026, month: 3, day: day, hour: hour, minute: minute, second: 0)
        )!
    }

    private func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    /// Within one day the weekday is redundant, and adding it to every range
    /// would cost width in the densest band of the interface for nothing.
    @Test("a range inside one day carries no weekday")
    func insideOneDay() {
        let start = date(day: 10, hour: 13, minute: 31)
        let end = date(day: 10, hour: 21, minute: 59)
        let text = RangeLabel.text(from: start, to: end)

        #expect(text == "13:31 – 21:59")
        #expect(!text.contains(weekday(start)))
    }

    /// The case this exists for. "13:31 – 11:56" for twenty-two hours of silence
    /// reads as a negative span until the reader works out that a day boundary
    /// went past.
    @Test("a range crossing midnight names both days")
    func acrossMidnight() {
        let start = date(day: 10, hour: 13, minute: 31)
        let end = date(day: 11, hour: 11, minute: 56)
        let text = RangeLabel.text(from: start, to: end)

        #expect(text.contains(weekday(start)))
        #expect(text.contains(weekday(end)))
        #expect(text == "\(weekday(start)) 13:31 → \(weekday(end)) 11:56")
    }

    /// Crossing is about the day boundary, not about the length. Two minutes
    /// spanning midnight is still two days, and the label has to say so or the
    /// reader has no way to tell it from twenty-two hours.
    @Test("two minutes across midnight is still two days")
    func shortButAcross() {
        let start = date(day: 10, hour: 23, minute: 59)
        let end = date(day: 11, hour: 0, minute: 1)

        #expect((start...end).crossesDayBoundary)
        #expect(RangeLabel.text(from: start, to: end).contains(weekday(start)))
        #expect(RangeLabel.text(from: start, to: end).contains(weekday(end)))
        #expect(
            RangeLabel.textWithDuration(from: start, to: end).hasSuffix("(2 min)"))
    }

    /// Nearly a whole day inside one day: long, and still no weekday, because
    /// the clock alone is sufficient.
    @Test("a long range that stays inside one day still carries no weekday")
    func longButInside() {
        let start = date(day: 10, hour: 0, minute: 1)
        let end = date(day: 10, hour: 23, minute: 59)

        #expect(!(start...end).crossesDayBoundary)
        #expect(RangeLabel.text(from: start, to: end) == "00:01 – 23:59")
    }

    /// A reversed range is normalised, not printed backwards. Callers pass
    /// window edges and gap bounds; one of them being inverted is a bug that
    /// must not surface as a label reading "21:59 – 13:31".
    @Test("a reversed range is normalised rather than printed backwards")
    func reversed() {
        let earlier = date(day: 10, hour: 13, minute: 31)
        let later = date(day: 10, hour: 21, minute: 59)

        #expect(
            RangeLabel.text(from: later, to: earlier)
                == RangeLabel.text(from: earlier, to: later))
        #expect(
            RangeLabel.textWithDuration(from: later, to: earlier).hasSuffix("(8 h 28 min)"))
    }
}
