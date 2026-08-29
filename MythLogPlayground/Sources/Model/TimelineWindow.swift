import Foundation

/// The visible time window. One window drives the timeline, the list, and the
/// category counts — they are never allowed to disagree.
///
/// # An invalid window is unrepresentable
///
/// The span is `@Clamped` to `minimumSpan...fullHistory`, and the start is
/// always placed so the window lies inside the history it belongs to. Both are
/// enforced at every construction, not checked afterwards.
///
/// The failure this prevents is specific. `TimelineCanvas` maps dates to
/// x-positions by dividing by the span; a span that reached zero — which
/// repeated halving does in about fifty keystrokes — divides by something close
/// to zero and draws every event at ±10^6 points. The bug does not look like a
/// bad number, it looks like the timeline exploding, and by then the arithmetic
/// that produced it is three call sites away.
///
/// Carrying `history` inside the window is what makes that possible: the upper
/// bound of a valid span is the length of the user's recorded history, which is
/// only known at runtime.
struct TimelineWindow: Equatable, Sendable {
    /// The full extent of the loaded history. The window can never leave it.
    let history: ClosedRange<Date>

    /// Zooming in below this is refused; below it a "window" stops being useful.
    static let minimumSpan: TimeInterval = 600

    /// The visible span, which cannot be set outside `minimumSpan...fullHistory`
    /// whatever arithmetic produced the assignment.
    @Clamped private(set) var span: TimeInterval

    private(set) var start: Date

    var end: Date { start.addingTimeInterval(span) }

    /// The whole history, as a span.
    var fullSpan: TimeInterval {
        max(Self.minimumSpan, history.upperBound.timeIntervalSince(history.lowerBound))
    }

    init(history: ClosedRange<Date>, centredOn centre: Date, span requestedSpan: TimeInterval) {
        self.history = history

        let full = max(Self.minimumSpan, history.upperBound.timeIntervalSince(history.lowerBound))
        _span = Clamped(wrappedValue: requestedSpan, Self.minimumSpan...full)
        let clamped = _span.wrappedValue

        // Place the window inside the history: slide rather than shrink, so a
        // zoom near either edge keeps the span the user asked for.
        var proposed = centre.addingTimeInterval(-clamped / 2)
        if proposed < history.lowerBound { proposed = history.lowerBound }
        if proposed.addingTimeInterval(clamped) > history.upperBound {
            proposed = history.upperBound.addingTimeInterval(-clamped)
        }
        start = max(history.lowerBound, proposed)
    }

    /// The whole history at once.
    init(showingAllOf history: ClosedRange<Date>) {
        let full = history.upperBound.timeIntervalSince(history.lowerBound)
        self.init(
            history: history,
            centredOn: history.lowerBound.addingTimeInterval(full / 2),
            span: full
        )
    }

    /// The most recent `span` of the history.
    init(history: ClosedRange<Date>, mostRecent span: TimeInterval) {
        self.init(
            history: history,
            centredOn: history.upperBound.addingTimeInterval(-span / 2),
            span: span
        )
    }

    // MARK: - Zooming

    func zoomed(by factor: Double) -> TimelineWindow {
        TimelineWindow(
            history: history,
            centredOn: start.addingTimeInterval(span / 2),
            span: span * factor
        )
    }

    func centred(on date: Date, span newSpan: TimeInterval) -> TimelineWindow {
        TimelineWindow(history: history, centredOn: date, span: newSpan)
    }

    // MARK: - Panning

    /// # Panning is zooming with a different axis
    ///
    /// It moves the window along the history at a constant span. It is not
    /// scrolling a view: there is no content wider than the screen to scroll,
    /// and there could not be — a two-year history at the Events level would be
    /// millions of points wide. There is one window over one dataset, and every
    /// derived thing follows it.
    ///
    /// Every panning operation below goes through
    /// ``init(history:centredOn:span:)``, which already places a window inside
    /// its history by *sliding* rather than shrinking. So clamping at both ends
    /// is not implemented here — it is inherited, and it cannot be forgotten at
    /// one call site and remembered at another. The span survives untouched for
    /// the same reason: the initialiser clamps it to `minimumSpan...fullSpan`,
    /// and a span that is already in that range passes through unchanged.

    /// Moved `seconds` later (positive) or earlier (negative), at constant span.
    func panned(by seconds: TimeInterval) -> TimelineWindow {
        TimelineWindow(
            history: history,
            centredOn: start.addingTimeInterval(span / 2 + seconds),
            span: span
        )
    }

    /// The oldest `span` of the history — as far back as this window can go.
    var pannedToStart: TimelineWindow {
        TimelineWindow(
            history: history,
            centredOn: history.lowerBound.addingTimeInterval(span / 2),
            span: span
        )
    }

    /// The newest `span` of the history: the live edge, where new records
    /// arrive.
    var pannedToNow: TimelineWindow {
        TimelineWindow(history: history, mostRecent: span)
    }

    /// Half a second: shorter than any silence worth naming and longer than the
    /// floating-point drift of `history.upperBound - span + span`, which is what
    /// pinning to an edge actually computes.
    private static let edgeTolerance: TimeInterval = 0.5

    var isAtStart: Bool { start.timeIntervalSince(history.lowerBound) <= Self.edgeTolerance }

    /// At the newest end of the history — "I am watching now" rather than "I am
    /// reading history". What re-attaching to live means, and what the interface
    /// has to be able to say out loud.
    var isAtEnd: Bool { history.upperBound.timeIntervalSince(end) <= Self.edgeTolerance }

    var canPanEarlier: Bool { !isAtStart }
    var canPanLater: Bool { !isAtEnd }

    /// Where this window sits inside the whole history, as fractions in `0...1`.
    ///
    /// For the position indicator. A window spanning the entire history returns
    /// `0...1`, and a history of zero length — one record, before the minimum
    /// span is applied — returns `0...1` rather than dividing by zero.
    var positionInHistory: ClosedRange<Double> {
        let total = history.upperBound.timeIntervalSince(history.lowerBound)
        guard total > 0 else { return 0...1 }
        let lower = min(max(start.timeIntervalSince(history.lowerBound) / total, 0), 1)
        let upper = min(max(end.timeIntervalSince(history.lowerBound) / total, 0), 1)
        return lower...max(lower, upper)
    }

    /// The window starting at `fraction` of the way through the history — what a
    /// drag on the position bar means.
    func positioned(atFraction fraction: Double) -> TimelineWindow {
        let total = history.upperBound.timeIntervalSince(history.lowerBound)
        let at = history.lowerBound.addingTimeInterval(total * min(max(fraction, 0), 1))
        return TimelineWindow(history: history, centredOn: at.addingTimeInterval(span / 2), span: span)
    }

    /// True when zooming further would change nothing — the honest answer to
    /// "should this button still be enabled?".
    var isFullyZoomedIn: Bool { span <= Self.minimumSpan }
    var isFullyZoomedOut: Bool { span >= fullSpan }

    // MARK: - Projection

    func fraction(of date: Date) -> Double {
        guard span > 0 else { return 0 }
        return date.timeIntervalSince(start) / span
    }

    /// Inclusive at both ends, deliberately.
    ///
    /// A half-open window (`date < end`) drops any event landing exactly on the
    /// upper bound — and when the whole history is shown, the upper bound *is*
    /// the newest record's timestamp. So the most recent event, the one a user
    /// is most likely looking for, was the one that disappeared. It cost nothing
    /// to be wrong here because the fixture's last event was a few minutes
    /// before the fixture's "now".
    ///
    /// Double-counting at a shared boundary would be the usual argument for
    /// half-open intervals, and it does not apply: there is exactly one window,
    /// never a tiling of adjacent ones.
    func contains(_ date: Date) -> Bool { date >= start && date <= end }

    /// The window's extent, with weekdays once it crosses midnight.
    ///
    /// # The label used to contradict the span beside it
    ///
    /// A six-day window starting at 12:37 ends at 21:59 six days later, and this
    /// printed `12:37 – 21:59`. Next to a chip reading `Density · 6 d` that is a
    /// flat contradiction: one says six days, the other appears to say nine
    /// hours, and a reader has no way to tell which is lying. Neither was — the
    /// label had silently dropped the six days between the two clock times.
    ///
    /// ``RangeLabel`` adds the weekday exactly when the range crosses a day
    /// boundary, which is precisely when the clock alone stops being sufficient.
    var label: String { RangeLabel.text(from: start, to: end) }

    /// Human span, used in the timeline level chip: "3 d", "15 h", "10 min".
    /// Shared with coverage gaps and everything else that prints a duration —
    /// see ``DurationLabel``.
    var spanLabel: String { DurationLabel.text(span) }

    /// Whether this window is the entire history.
    ///
    /// For the position readout, which used to render "12:37 – 21:59 of 12:37 –
    /// 21:59" whenever the two coincided. A range qualified by itself is not a
    /// qualification, and it reads as though something has gone wrong.
    var showsWholeHistory: Bool {
        isAtStart && isAtEnd
    }
}
