import Foundation

/// The grid the density and cluster renderers draw on — one grid, shared by the
/// bars *and* by the coverage-gap overlay.
///
/// # Why this is a type rather than a computed property on the canvas
///
/// It used to be `TimelineCanvas.buckets`, while the gap overlay positioned
/// itself with `window.fraction(of: gap.start)` — a continuous fraction of the
/// window. Two coordinate systems over one axis can only agree by accident, and
/// they did not: hatch edges fell mid-bar and bars came out half-hatched.
///
/// The second half of that fault was subtler. The bars were laid out in an
/// `HStack` of *n* equal slots spread across the whole width, whatever the
/// grid's own extent happened to be. The grid is snapped to wall-clock multiples
/// of ``step`` so that boundaries land on the clock, which means it begins
/// *before* `window.start` and ends *after* `window.end`. Spreading it evenly
/// therefore rescales time by up to one bucket at each end, and the error is
/// progressive — the right-hand bars sat furthest from where their events
/// actually happened. No amount of quantising the overlay would have lined it up
/// with a layout that was not itself on the time axis.
///
/// So the grid owns the projection. ``slot(_:)`` is the only place a bucket
/// index becomes a position, and bars, hatching and gap ticks all go through it.
///
/// # Partial buckets at the edges are drawn, not dropped
///
/// Because the grid is clock-aligned, the first and last buckets usually hang
/// over the edges of the window. ``slot(_:)`` clamps them, so those two bars are
/// narrower than the rest. That is the honest rendering: the bar is as wide as
/// the part of its bucket you can actually see, and its count is of the events
/// inside the window. Widening it to a full slot would put a bar where there is
/// no window, which is how the drift above got in.
struct BucketGrid: Equatable, Sendable {

    /// Bucket widths that read as durations on a clock — a minute, two, five,
    /// ten, fifteen, half an hour, an hour, two — rather than whatever
    /// `span / targetCount` happens to come to.
    static let steps: [TimeInterval] = [60, 120, 300, 600, 900, 1800, 3600, 7200]

    /// Roughly this many bars across the window. The first step that achieves it
    /// wins, so the bars stay legible without the count swinging with the span.
    static let targetCount = 30

    let window: TimelineWindow

    /// The width of one bucket, from ``steps``.
    let step: TimeInterval

    /// The grid origin: `window.start` floored to a multiple of ``step``, so the
    /// boundaries land on the clock rather than on whenever the window began.
    let start: Date

    /// How many buckets it takes to cover the window from ``start``.
    let count: Int

    init(window: TimelineWindow) {
        self.window = window

        let step = Self.steps.first { window.span / $0 <= Double(Self.targetCount) } ?? (Self.steps.last ?? 7200)
        self.step = step

        let origin = (window.start.timeIntervalSince1970 / step).rounded(.down) * step
        start = Date(timeIntervalSince1970: origin)
        count = max(1, Int(((window.end.timeIntervalSince1970 - origin) / step).rounded(.up)))
    }

    // MARK: - Time

    func start(of index: Int) -> Date {
        start.addingTimeInterval(Double(index) * step)
    }

    func end(of index: Int) -> Date {
        start.addingTimeInterval(Double(index + 1) * step)
    }

    /// The bucket a date falls in. Can be outside `0..<count` — a date outside
    /// the window has a grid index too, and clamping here would silently move
    /// events into the edge buckets.
    func index(containing date: Date) -> Int {
        Int((date.timeIntervalSince(start) / step).rounded(.down))
    }

    // MARK: - Projection

    /// Where a bucket is drawn: left and right edges as fractions of the window,
    /// clamped to `0...1`.
    ///
    /// This is the single projection. A caller that computes a position any
    /// other way is reintroducing the fault this type exists to remove.
    func slot(_ index: Int) -> ClosedRange<Double> {
        let lower = min(max(window.fraction(of: start(of: index)), 0), 1)
        let upper = min(max(window.fraction(of: end(of: index)), 0), 1)
        return lower...max(lower, upper)
    }

    // MARK: - Aggregation

    /// A bucket of events, shared by the density and cluster renderers.
    struct Bucket: Identifiable, Equatable, Sendable {
        /// The grid index, which is also what ``BucketGrid/slot(_:)`` takes.
        var id: Int
        var start: Date
        var count: Int
        var byKind: [EventKind: Int]
    }

    /// One bucket per grid index, in order.
    ///
    /// A single pass. The version this replaced ran `events.filter` once per
    /// bucket — thirty passes over the window's events on every render, and the
    /// window can contain a 312-event burst.
    ///
    /// Events outside the grid are ignored rather than clamped into the end
    /// buckets: the caller has already scoped `events` to the window, and an
    /// event that is somehow outside it must not be counted somewhere it did not
    /// happen.
    func buckets(over events: [TimelineEvent]) -> [Bucket] {
        var counts = [Int](repeating: 0, count: count)
        var byKind = [[EventKind: Int]](repeating: [:], count: count)

        for event in events {
            var index = index(containing: event.at)
            // The last bucket is closed at the window's end, for the same reason
            // ``TimelineWindow/contains(_:)`` is: when the whole history is
            // shown, the upper bound *is* the newest record's timestamp, and a
            // half-open bucket drops the one event a user is most likely
            // looking for. Every other boundary stays half-open, so no event is
            // ever counted twice.
            if index == count, event.at <= window.end { index = count - 1 }
            guard index >= 0, index < count else { continue }
            counts[index] += 1
            byKind[index][event.kind, default: 0] += 1
        }

        return (0..<count).map {
            Bucket(id: $0, start: start(of: $0), count: counts[$0], byKind: byKind[$0])
        }
    }
}
