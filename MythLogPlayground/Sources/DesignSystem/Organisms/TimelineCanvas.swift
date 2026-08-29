import SwiftUI

/// The timeline. It never disappears — it changes what it is made of.
///
/// One component with three renderers, deliberately not three components:
/// selection, the window, and the coverage-gap overlay must behave identically
/// at every level. Splitting them is how the gap hatching and selection drift
/// apart.
struct TimelineCanvas: View {
    var events: [TimelineEvent]
    var window: TimelineWindow
    var gaps: [CoverageGap]
    /// Where trustworthy history ends, when part of it does not verify.
    var trustBoundary: TrustBoundary?
    var level: ZoomLevel
    var selected: TimelineEvent?
    /// Records in this window a filter is hiding, so an empty canvas can say
    /// which kind of empty it is.
    var hiddenByFilter: Int = 0
    var onSelect: (TimelineEvent) -> Void
    var onZoomTo: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space2) {
            GeometryReader { geo in
                // Derived once and handed to both the bars and the hatching.
                // Two computations of the same grid is how they drift apart, and
                // it also spared thirty passes over the window's events.
                let grid = BucketGrid(window: window)
                let buckets = level == .events ? [] : grid.buckets(over: events)

                ZStack(alignment: .topLeading) {
                    gapOverlays(marks: gapMarks(grid: grid, buckets: buckets, width: geo.size.width), size: geo.size)
                    untrustedOverlay(width: geo.size.width, height: geo.size.height)

                    switch level {
                    case .density: density(size: geo.size, grid: grid, buckets: buckets)
                    case .clusters: clusters(size: geo.size, grid: grid, buckets: buckets)
                    case .events: nodes(size: geo.size)
                    }

                    if events.isEmpty { emptyNotice(size: geo.size) }

                    axisLine(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(height: Metrics.timelineHeight)

            axisLabels
        }
    }

    // MARK: - Shared chrome

    /// What to draw for the gaps at this level.
    ///
    /// The decision lives in ``CoverageGapLayout`` rather than here because it
    /// is arithmetic over dates and buckets, and arithmetic that decides whether
    /// the interface contradicts itself belongs somewhere a test can reach it
    /// without a renderer.
    ///
    /// At Density and Clusters the marks are quantised to the same grid the bars
    /// are drawn on. At Events there is no grid, so a real timestamp is the
    /// honest position and the gap stays continuous.
    private func gapMarks(
        grid: BucketGrid, buckets: [BucketGrid.Bucket], width: CGFloat
    ) -> [CoverageGapLayout.Mark] {
        switch level {
        case .density, .clusters:
            return CoverageGapLayout.marks(for: gaps, on: grid, buckets: buckets)
        case .events:
            return CoverageGapLayout.marks(
                for: gaps,
                in: window,
                minimumWidth: Double(Metrics.timelineGapMinimumWidth / max(1, width))
            )
        }
    }

    /// Drawn beneath every level and never filterable. An absence of recording
    /// is not an event, so no filter may hide it.
    ///
    /// A real ledger has many gaps, not one — every restart after a crash leaves
    /// another. The fixture had exactly one, which is how this ended up
    /// singular.
    private func gapOverlays(marks: [CoverageGapLayout.Mark], size: CGSize) -> some View {
        ForEach(marks) { mark in
            gapOverlay(mark, width: size.width, height: size.height)
        }
    }

    @ViewBuilder
    private func gapOverlay(_ mark: CoverageGapLayout.Mark, width: CGFloat, height: CGFloat) -> some View {
        let height = height - Metrics.timelineAxisInset

        switch mark.form {
        case .region:
            let x = mark.start * width
            let w = (mark.end - mark.start) * width
            ZStack(alignment: .topLeading) {
                HatchFill()
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Palette.textQuiet.opacity(0.7))
                // Pinned to the region's top-left corner in small caps, not
                // floating in the middle as a capsule. A lozenge centred in a
                // band looks like a control sitting on top of the timeline —
                // something to click, or a tooltip that will go away — when it
                // is an annotation *of* the band. Annotations label their region
                // from its edge, which is also where they stop competing with
                // whatever the hatching is covering.
                if w > 110 {
                    Text(mark.label.uppercased())
                        .font(Typography.sectionKicker)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, Metrics.space2)
                        .padding(.vertical, Metrics.space1)
                        .background(Palette.surface.opacity(0.82))
                        .padding(Metrics.space1)
                }
            }
            .frame(width: w, height: height)
            .offset(x: x)
            .accessibilityLabel(mark.label)

        case .tick:
            // # Why this is dashed
            //
            // A short gap is drawn as a narrow full-height mark, and the density
            // renderer draws narrow bars in the same grey. Two series in one
            // colour, one meaning "this many events" and the other meaning "no
            // events could have been recorded" — the two most opposite claims
            // the timeline makes, rendered identically.
            //
            // Hatching cannot rescue it: three points of diagonal lines is a
            // smudge, which is the entire reason this is a mark and not a
            // region. So it takes the *other* half of the gap's visual language.
            // Dashes are absence, solid is data, and the rule holds at every
            // width. The cap gives the eye something to land on and lifts the
            // mark clear of the tallest bar it could sit beside.
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Palette.textSecondary)
                    .frame(width: Metrics.timelineGapTickWidth + 2, height: Metrics.timelineGapTickWidth + 2)
                Rectangle()
                    .strokeBorder(
                        style: StrokeStyle(
                            lineWidth: Metrics.timelineGapTickWidth, dash: [3, 2]))
                    .foregroundStyle(Palette.textQuiet)
                    .frame(width: Metrics.timelineGapTickWidth)
            }
            .frame(width: Metrics.timelineGapTickWidth + 2, height: height, alignment: .top)
            .offset(x: mark.start * width - (Metrics.timelineGapTickWidth + 2) / 2)
            .accessibilityLabel(mark.label)
        }
    }

    /// The span of the timeline that cannot be trusted, and the line where it
    /// begins.
    ///
    /// Drawn *under* the events, not over them: the point is that these records
    /// are still there and still readable — they simply cannot be relied on.
    /// Hiding or dimming them would answer a question nobody asked, and the
    /// altered records are the ones a person most wants to look at.
    ///
    /// Everything after the boundary is untrusted, including records that have
    /// not been written yet, so the region runs to the right-hand edge rather
    /// than stopping at the last event.
    @ViewBuilder
    private func untrustedOverlay(width: CGFloat, height: CGFloat) -> some View {
        if let trustBoundary, let at = trustBoundary.firstUntrustedAt {
            let f = window.fraction(of: at)
            if f < 1 {
                let x = max(0, f) * width
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.untrustedSpan)
                    Rectangle()
                        .fill(Palette.critical.opacity(0.8))
                        .frame(width: 2)
                }
                .frame(width: width - x, height: height - Metrics.timelineAxisInset)
                .offset(x: x)
                .accessibilityHidden(true)
            }
        }
    }

    /// An empty timeline, saying which kind of empty.
    ///
    /// Drawn over the gap hatching rather than instead of it, because a window
    /// containing nothing but a coverage gap must still show the gap: the
    /// hatching is the answer, and this only explains the space around it.
    ///
    /// "Nothing happened" and "you are hiding everything that happened" produce
    /// identical pixels otherwise, and only one of them is true.
    private func emptyNotice(size: CGSize) -> some View {
        VStack(spacing: Metrics.space1) {
            Text(hiddenByFilter > 0 ? "Everything here is filtered out" : "Nothing recorded in this window")
                .font(Typography.chip)
                .foregroundStyle(hiddenByFilter > 0 ? Palette.filtered : Palette.textTertiary)
            if hiddenByFilter > 0 {
                Text("\(hiddenByFilter.formatted()) record(s) are hidden")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.horizontal, Metrics.space3)
        .padding(.vertical, Metrics.space2)
        .background(Capsule().fill(Palette.surface.opacity(0.9)))
        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: Metrics.hairline))
        .frame(width: size.width, height: size.height - Metrics.timelineAxisInset)
    }

    private func axisLine(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Palette.divider)
            .frame(height: 1)
            .offset(y: height - Metrics.timelineAxisInset)
            .accessibilityHidden(true)
    }

    /// # Ticks land on round times, and are positioned rather than spaced
    ///
    /// The axis used to divide the span into five and print whatever times those
    /// divisions happened to be: `19:18 · 01:58 · 08:38`. Nobody can read a
    /// duration off that. Working out that 01:58 to 08:38 is about six and a
    /// half hours is arithmetic the axis exists to do for you, and the labels
    /// changed on every pan, so a moving timeline never showed the same landmark
    /// twice.
    ///
    /// Round hours are landmarks. They stay put while the window moves under
    /// them, which is what makes panning legible, and a reader knows without
    /// counting that two adjacent ticks are six hours apart.
    ///
    /// They are also *placed at their own time* rather than distributed evenly:
    /// an evenly spaced row of clock-aligned labels would be a row of numbers
    /// that lies about where those moments are.
    private var axisLabels: some View {
        GeometryReader { geo in
            ForEach(ticks, id: \.self) { tick in
                Text(labelText(for: tick))
                    .font(Typography.axisLabel)
                    .foregroundStyle(Palette.textQuiet)
                    .fixedSize()
                    .position(
                        x: min(max(window.fraction(of: tick) * geo.size.width, 22), geo.size.width - 22),
                        y: geo.size.height / 2
                    )
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    /// Midnight names its day; every other tick is a clock time.
    ///
    /// A window spanning several days otherwise shows `00:00` three times with
    /// nothing to say which day each one is, which is the same ambiguity that
    /// made a twenty-two hour coverage gap read as a typo.
    private func labelText(for tick: Date) -> String {
        let calendar = Calendar.current
        let isMidnight = calendar.component(.hour, from: tick) == 0
            && calendar.component(.minute, from: tick) == 0
        guard isMidnight, window.span > 12 * 3600 else { return tick.clockText }
        return tick.formatted(.dateTime.weekday(.abbreviated).day())
    }

    /// Round times inside the window, at the coarsest step that yields a
    /// readable number of them.
    ///
    /// The step is chosen from the span, not from a fixed count, so the labels
    /// are always on the hour, the six-hour, or the day — never on 19:18.
    private var ticks: [Date] { Self.ticks(in: window) }

    /// Static, internal, and `nonisolated`, for the same reason
    /// ``gapMarks(grid:buckets:width:)`` delegates to ``CoverageGapLayout``: this
    /// is arithmetic over dates that decides whether the axis tells the truth,
    /// and arithmetic like that belongs somewhere a test can reach it without
    /// standing up a renderer.
    ///
    /// `nonisolated` is load-bearing rather than decorative. `View` carries a
    /// `@preconcurrency @MainActor` conformance, so every member of this type —
    /// including a static function over two dates — inherits main-actor
    /// isolation, and `@preconcurrency` means a call from anywhere else compiles
    /// and then *traps at runtime* instead of being diagnosed. The first thing
    /// that happened when a test called this was the whole test host dying with
    /// no Swift error attached to it. Nothing here touches view state, so saying
    /// so is both true and what makes it callable.
    /// - Parameter calendar: injected only so a test can pin a daylight-saving
    ///   zone. The machine this was written on is in `America/Merida`, which has
    ///   observed no transition since 2022, so a test that asked
    ///   `Calendar.current` about DST would have passed here by saying nothing.
    nonisolated static func ticks(in window: TimelineWindow, calendar: Calendar = .current) -> [Date] {
        let step = Self.axisStep(for: window.span)
        return step < 86400
            ? clockTicks(in: window, step: step, calendar: calendar)
            : dayTicks(in: window, everyDays: Int((step / 86400).rounded()), calendar: calendar)
    }

    /// Ticks below a day: the same wall-clock times on every day.
    ///
    /// # Why this walks days and sets a clock time, rather than adding seconds
    ///
    /// It used to take the window's first midnight and add `step` seconds
    /// repeatedly. Twice a year that walks off the clock: a day containing a
    /// daylight-saving change is twenty-three or twenty-five hours long, so
    /// twenty-four hours of *elapsed time* after midnight is 01:00, and every
    /// tick after the transition is an hour out for the rest of the axis. The
    /// comment on that loop claimed calendar arithmetic prevented it —
    /// `date(byAdding: .second,)` adds elapsed seconds exactly as
    /// `addingTimeInterval` does, so it never did.
    ///
    /// Midnight is also the only tick allowed to name its day, so the drift took
    /// the day names with it: a multi-day window across a transition showed
    /// `01:00` several times with nothing to say which day each one was — the
    /// precise ambiguity round ticks exist to remove.
    ///
    /// Every sub-day step divides a day evenly, so "the k-th step past midnight"
    /// is the same set of clock times on every day, and asking the calendar for
    /// that clock time on each day is both correct across a transition and
    /// exactly what a reader sees on the axis.
    private nonisolated static func clockTicks(
        in window: TimelineWindow, step: TimeInterval, calendar: Calendar
    ) -> [Date] {
        let perDay = Int((86400 / step).rounded())
        var marks = [Date]()
        var day = calendar.startOfDay(for: window.start)

        // Bounded by *iterations*, not by marks appended. A bound on the output
        // does not bound a loop whose input never advances, and this loop's
        // advance comes from the calendar.
        for _ in 0..<128 {
            guard day < window.end else { break }

            // Fast-forward within the day rather than walking it: at the
            // two-minute step a window starting at 23:50 is 715 slots from its
            // own midnight, and computing those to discard all but a few is work
            // done on every frame of a pan. One slot of slack absorbs a short
            // day, where the division is off by one.
            let elapsed = window.start.timeIntervalSince(day)
            let first = elapsed > 0 ? max(0, Int(elapsed / step) - 1) : 0

            for slot in first..<perDay {
                let seconds = Int(step) * slot
                guard
                    let tick = calendar.date(
                        bySettingHour: seconds / 3600, minute: (seconds % 3600) / 60, second: 0,
                        of: day)
                else { continue }
                // Slots ascend, so the first one past the end ends the whole
                // walk, not just this day.
                if tick >= window.end { return marks }
                if tick >= window.start { marks.append(tick) }
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day
            else { break }
            day = next
        }
        return marks
    }

    /// Ticks of a day or more: midnights, every `everyDays` days.
    ///
    /// # Why the anchor is a fixed epoch and not the window's own first midnight
    ///
    /// Anchoring to the window meant a seven-day step counted seven days from
    /// whichever day the window happened to begin on — so panning across a
    /// single midnight moved *every label on the axis* by a day. That is the one
    /// thing round ticks exist to prevent, and it was invisible at the spans the
    /// design was reviewed at, because every step below a day divides a day
    /// evenly and is therefore anchor-independent by accident.
    ///
    /// A fixed reference day makes the marks a property of the calendar rather
    /// than of the window. It is a Monday, so the week-multiple steps — 7, 14,
    /// 28 days — land on Mondays, which is as close to a landmark as a
    /// multi-week grid gets.
    ///
    /// Advanced in whole `.day` units, which is the arithmetic that does keep a
    /// wall-clock midnight across a daylight-saving change.
    private nonisolated static func dayTicks(
        in window: TimelineWindow, everyDays: Int, calendar: Calendar
    ) -> [Date] {
        guard everyDays > 0 else { return [] }

        let epoch = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        let elapsedDays =
            calendar.dateComponents([.day], from: epoch, to: calendar.startOfDay(for: window.start))
            .day ?? 0
        // Floor, not truncation: a history before the reference date has a
        // negative day count, and truncating it would step off the grid.
        let aligned = Int((Double(elapsedDays) / Double(everyDays)).rounded(.down)) * everyDays

        var marks = [Date]()
        guard var cursor = calendar.date(byAdding: .day, value: aligned, to: epoch) else {
            return marks
        }

        for _ in 0..<128 {
            guard cursor < window.end else { break }
            if cursor >= window.start { marks.append(cursor) }
            guard
                let next = calendar.date(byAdding: .day, value: everyDays, to: cursor),
                next > cursor
            else { break }
            cursor = next
        }
        return marks
    }

    /// The gap between ticks, in seconds, for a given visible span.
    ///
    /// Chosen so a full window carries roughly four to eight labels: fewer and
    /// the axis stops being a scale, more and they collide.
    ///
    /// # Both bounds are the ladder's job, not the rule's
    ///
    /// The rule below only enforces the *upper* bound — take the first step that
    /// keeps the count at eight or under. The lower bound is a property of the
    /// ladder itself: when consecutive rungs are a factor `r` apart, a span that
    /// has just outgrown one rung lands at `8 / r` labels on the next. So `r`
    /// must stay under `8 / 3` for the axis never to drop below three, and every
    /// step from here to there has to exist.
    ///
    /// The ladder used to run from ten minutes to twenty-eight days with two
    /// rungs missing — 600→1800 and 2 d→7 d, both a factor of three or more —
    /// and with nothing at either end. The consequences were all real windows:
    /// at the minimum zoom the axis showed a *single* label, an eighty-minute
    /// window showed two, and a two-year history fell off the top of the ladder
    /// entirely and drew twenty-six overlapping day marks. Filling the gaps and
    /// extending both ends is the same decision, carried to the spans that
    /// actually occur.
    ///
    /// Every sub-day rung divides a day evenly, which is what keeps the marks on
    /// clock times a reader recognises; every rung above a day is a whole number
    /// of days, and the long ones are whole numbers of weeks, so they at least
    /// land on a consistent weekday.
    nonisolated static func axisStep(for span: TimeInterval) -> TimeInterval {
        let minute: TimeInterval = 60
        let hour: TimeInterval = 3600
        let day: TimeInterval = 86400
        let candidates: [TimeInterval] = [
            minute, 2 * minute, 5 * minute, 10 * minute, 20 * minute, 30 * minute,
            hour, 2 * hour, 3 * hour, 6 * hour, 12 * hour,
            day, 2 * day, 3 * day, 7 * day, 14 * day, 28 * day,
            56 * day, 112 * day, 224 * day,
        ]
        return candidates.first { span / $0 <= 8 } ?? candidates[candidates.count - 1]
    }
}
