import Foundation

/// The visible time window. One window drives the timeline, the list, and the
/// category counts — they are never allowed to disagree.
struct TimelineWindow: Equatable, Sendable {
    var start: Date
    var end: Date

    var span: TimeInterval { end.timeIntervalSince(start) }

    /// Zooming in below this is refused; below it a "window" stops being useful.
    static let minimumSpan: TimeInterval = 600

    func zoomed(by factor: Double, limit: ClosedRange<Date>) -> TimelineWindow {
        let centre = start.addingTimeInterval(span / 2)
        let target = max(Self.minimumSpan, min(span * factor, limit.upperBound.timeIntervalSince(limit.lowerBound)))
        return Self.centred(on: centre, span: target, limit: limit)
    }

    static func centred(on centre: Date, span: TimeInterval, limit: ClosedRange<Date>) -> TimelineWindow {
        let full = limit.upperBound.timeIntervalSince(limit.lowerBound)
        let clamped = max(minimumSpan, min(span, full))
        var s = centre.addingTimeInterval(-clamped / 2)
        if s < limit.lowerBound { s = limit.lowerBound }
        var e = s.addingTimeInterval(clamped)
        if e > limit.upperBound {
            e = limit.upperBound
            s = e.addingTimeInterval(-clamped)
        }
        return TimelineWindow(start: s, end: e)
    }

    func fraction(of date: Date) -> Double {
        guard span > 0 else { return 0 }
        return date.timeIntervalSince(start) / span
    }

    func contains(_ date: Date) -> Bool { date >= start && date < end }

    var label: String {
        "\(start.clockText) – \(end.clockText)"
    }

    /// Human span, used in the timeline level chip: "15 h", "1 h", "10 min".
    var spanLabel: String {
        let minutes = span / 60
        if minutes >= 90 { return "\(Int((minutes / 60).rounded())) h" }
        if minutes >= 55 { return "1 h" }
        return "\(Int(minutes.rounded())) min"
    }
}
