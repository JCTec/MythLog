import Foundation
import Testing

@testable import MythLog

/// The axis, which is the only part of the timeline that claims to be a *scale*.
///
/// It used to divide the span into five and print whatever times those divisions
/// happened to be — `19:18 · 01:58 · 08:38` — so the labels changed on every pan
/// and a reader could not tell how far apart two of them were without doing
/// arithmetic. Ticks on round times fix both at once: they stay put while the
/// window moves under them, and the distance between two of them is a number
/// anybody can read off.
///
/// All three properties below are things a renderer cannot be asked about, which
/// is why the tick arithmetic is static and reachable from here.
@Suite("The timeline axis")
struct TimelineAxisTests {

    private let calendar = Calendar.current

    private func date(month: Int = 6, day: Int, hour: Int, minute: Int) -> Date {
        calendar.date(
            from: DateComponents(
                year: 2026, month: month, day: day, hour: hour, minute: minute, second: 0)
        )!
    }

    /// A window of `span` starting at `start`, with a history wide enough that
    /// nothing is clamped.
    private func window(startingAt start: Date, span: TimeInterval) -> TimelineWindow {
        let history = start.addingTimeInterval(-span * 4)...start.addingTimeInterval(span * 5)
        return TimelineWindow(
            history: history, centredOn: start.addingTimeInterval(span / 2), span: span)
    }

    /// Every span the app can show, sampled geometrically from the minimum zoom
    /// to two years.
    private var spans: [TimeInterval] {
        var spans = [TimeInterval]()
        var span = TimelineWindow.minimumSpan
        while span <= 2 * 365 * 86_400 {
            spans.append(span)
            span *= 1.07
        }
        return spans
    }

    // MARK: - The step

    /// Fewer than three and the axis stops being a scale; more than about eight
    /// and the labels collide. The upper bound comes from the selection rule and
    /// the lower one from the ladder having no gaps in it — see ``axisStep``.
    @Test("every span from ten minutes to two years carries three to ten labels")
    func labelCount() {
        for span in spans {
            let count = span / TimelineCanvas.axisStep(for: span)
            #expect(
                count >= 3 && count <= 10,
                "a \(Int(span)) s span produces \(count) labels")
        }
    }

    /// A step that does not divide a day cannot land on clock times a reader
    /// recognises: it would drift across midnight and print 03:47 on one day and
    /// 04:12 on the next.
    @Test("every sub-day step divides a day evenly")
    func stepsDivideADay() {
        for span in spans {
            let step = TimelineCanvas.axisStep(for: span)
            guard step < 86_400 else {
                #expect(
                    step.truncatingRemainder(dividingBy: 86_400) == 0,
                    "a step of \(step) s is neither sub-day nor a whole number of days")
                continue
            }
            #expect(
                86_400.0.truncatingRemainder(dividingBy: step) == 0,
                "a step of \(step) s does not divide a day")
        }
    }

    /// The step never shrinks as the window widens. A zoom-out that produced a
    /// *finer* axis would be a scale that runs backwards.
    @Test("the step never decreases as the span grows")
    func monotonic() {
        var previous: TimeInterval = 0
        for span in spans {
            let step = TimelineCanvas.axisStep(for: span)
            #expect(step >= previous, "\(Int(span)) s went back to a \(step) s step")
            previous = step
        }
    }

    // MARK: - The ticks

    /// The property the whole thing exists for: a tick is a round time, not a
    /// division of the window. The awkward starts are the point — a window
    /// beginning at 12:37 must not produce an axis of 12:37, 13:37, 14:37.
    @Test(
        "ticks land on round times whatever time the window starts",
        arguments: [
            (12, 37), (23, 59), (0, 0), (0, 1), (7, 3), (13, 31), (19, 18),
        ] as [(Int, Int)])
    func roundTimes(hour: Int, minute: Int) {
        let spans: [TimeInterval] = [600, 3600, 5000, 6 * 3600, 86_400, 3 * 86_400, 30 * 86_400]
        for span in spans {
            let start = date(day: 10, hour: hour, minute: minute)
            let w = window(startingAt: start, span: span)
            let step = TimelineCanvas.axisStep(for: w.span)
            let ticks = TimelineCanvas.ticks(in: w)

            for tick in ticks {
                #expect(
                    calendar.component(.second, from: tick) == 0,
                    "\(tick) is not on a whole minute")
                #expect(w.contains(tick))

                // Round *against the clock*, not against the window: a tick's
                // offset from the window's own first midnight says nothing,
                // because the grid the ticks belong to is the calendar's.
                if step < 86_400 {
                    let intoDay = tick.timeIntervalSince(calendar.startOfDay(for: tick))
                    #expect(
                        intoDay.truncatingRemainder(dividingBy: step) == 0,
                        "\(tick) is \(intoDay) s into its day, not a whole \(Int(step)) s mark (span \(Int(span)) s, start \(hour):\(minute))")
                } else {
                    #expect(
                        calendar.startOfDay(for: tick) == tick,
                        "\(tick) is a day-scale tick that is not a midnight")
                }
            }

            // And evenly spaced, in whole steps, whichever scale they are on.
            for (earlier, later) in zip(ticks, ticks.dropFirst()) {
                let days = calendar.dateComponents([.day], from: earlier, to: later).day ?? 0
                if step >= 86_400 {
                    #expect(days == Int((step / 86_400).rounded()))
                } else {
                    #expect(later.timeIntervalSince(earlier) == step)
                }
            }
        }
    }

    /// Ticks are landmarks, so panning must slide the window under them rather
    /// than dragging them along with it. Any tick still inside the window after a
    /// small pan has to be the same instant it was before.
    @Test("panning does not move the ticks that stay visible")
    func ticksStayStill() {
        let w = window(startingAt: date(day: 10, hour: 12, minute: 37), span: 6 * 3600)
        let before = Set(TimelineCanvas.ticks(in: w))
        let after = Set(TimelineCanvas.ticks(in: w.panned(by: 900)))

        #expect(!after.isEmpty)
        #expect(!after.intersection(before).isEmpty)
        // Everything in the overlap of the two windows is common to both.
        let overlap = after.filter { w.contains($0) }
        #expect(Set(overlap).isSubset(of: before))
    }

    /// The same claim at day scale, where it is the harder one to keep: the
    /// anchor for a seven-day step cannot be the window's own first midnight, or
    /// panning across a single midnight drags every label on the axis with it.
    @Test("panning does not move the ticks at day-scale spans either")
    func dayTicksStayStill() {
        let spans: [TimeInterval] = [3 * 86_400, 10 * 86_400, 30 * 86_400, 200 * 86_400]
        for span in spans {
            let w = window(startingAt: date(day: 10, hour: 12, minute: 37), span: span)
            let before = Set(TimelineCanvas.ticks(in: w))

            // Far enough to cross a midnight, short enough that most of the
            // window is still the same window.
            let moved = w.panned(by: 86_400)
            let after = Set(TimelineCanvas.ticks(in: moved))
            let common = after.filter { w.contains($0) }

            #expect(!common.isEmpty, "a \(Int(span / 86_400)) d window shares no ticks after a one-day pan")
            #expect(
                Set(common).isSubset(of: before),
                "a \(Int(span / 86_400)) d window moved its ticks when it was panned")
        }
    }

    /// Twice a year a day is twenty-three or twenty-five hours long, and an axis
    /// that advances by adding elapsed seconds walks off the clock at that point:
    /// 00:00 becomes 01:00 and stays there for the rest of the window. Midnight
    /// is also the only tick that gets to name its day, so the drift takes the
    /// day names with it — which is the exact ambiguity round ticks exist to
    /// remove.
    /// The calendar is passed in rather than taken from the machine, on purpose.
    /// This one is in `America/Merida`, which has observed no transition since
    /// 2022 — a test that asked `Calendar.current` would pass here by never
    /// reaching the case it is named after.
    @Test(
        "ticks stay on the clock across a daylight-saving change",
        arguments: [
            (3, 8), (11, 1),  // spring forward and fall back, 2026, US rules
        ] as [(Int, Int)])
    func acrossDaylightSaving(month: Int, day: Int) {
        var dst = Calendar(identifier: .gregorian)
        dst.timeZone = TimeZone(identifier: "America/Denver")!
        #expect(dst.timeZone.nextDaylightSavingTimeTransition(after: Date()) != nil)

        let transition = dst.date(from: DateComponents(year: 2026, month: month, day: day))!

        // Both step scales that can straddle a transition: hours, and whole days.
        let spans: [TimeInterval] = [86_400, 2 * 86_400, 5 * 86_400, 20 * 86_400]
        for span in spans {
            let start = transition.addingTimeInterval(-20 * 3600)
            let w = window(startingAt: start, span: span)
            let step = TimelineCanvas.axisStep(for: w.span)
            let ticks = TimelineCanvas.ticks(in: w, calendar: dst)

            #expect(!ticks.isEmpty)
            for tick in ticks {
                let parts = dst.dateComponents([.hour, .minute, .second], from: tick)
                let secondsIntoDay = TimeInterval(
                    parts.hour! * 3600 + parts.minute! * 60 + parts.second!)
                #expect(
                    secondsIntoDay.truncatingRemainder(dividingBy: min(step, 86_400)) == 0,
                    "\(tick) is \(secondsIntoDay) s into its day, not a whole \(Int(step)) s mark")
            }

            // Midnight is the only tick allowed to name its day, so a day-scale
            // axis that drifts off midnight loses every day name it had.
            if step >= 86_400 {
                for tick in ticks {
                    #expect(dst.component(.hour, from: tick) == 0)
                    #expect(dst.startOfDay(for: tick) == tick)
                }
            }
        }
    }

    /// The loop is bounded at 128 iterations because its advance comes from the
    /// calendar, which can legitimately fail to advance. The bound is a backstop
    /// against a hang, not a working limit — a real window must finish long
    /// before it, or ticks would silently stop halfway across the axis.
    @Test("the tick loop finishes far short of its bound")
    func terminates() {
        // The pathological start: at the minimum zoom, 23:50 is 143 steps of ten
        // minutes from its own midnight, which is what the fast-forward exists
        // to skip.
        let tight = window(startingAt: date(day: 10, hour: 23, minute: 50), span: 600)
        let marks = TimelineCanvas.ticks(in: tight)
        #expect(!marks.isEmpty)
        #expect(marks.count <= 10)

        // And the widest thing the app can be asked to draw.
        let wide = window(startingAt: date(day: 10, hour: 23, minute: 50), span: 2 * 365 * 86_400)
        #expect(TimelineCanvas.ticks(in: wide).count <= 10)

        for span in spans {
            let w = window(startingAt: date(day: 10, hour: 23, minute: 50), span: span)
            let count = TimelineCanvas.ticks(in: w).count
            #expect(count >= 1, "a \(Int(span)) s window produced no ticks at all")
            #expect(count < 128, "a \(Int(span)) s window hit the iteration bound")
        }
    }
}

/// The two things the timeline says about its own extent, which sit side by
/// side and used to contradict each other.
@Suite("The span and the range agree")
struct WindowLabelTests {

    private let calendar = Calendar.current

    /// The exact case from the review: a six-day window starting at 12:37 ends
    /// at 21:59 six days later, and the label said `12:37 – 21:59` next to a
    /// chip reading `Density · 6 d`. One appeared to say six days and the other
    /// nine hours, and a reader had no way to tell which was lying — neither
    /// was; the label had silently dropped the six days between the two clock
    /// times.
    @Test("a six-day window does not read as nine hours")
    func sixDays() {
        let start = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 10, hour: 12, minute: 37))!
        let span: TimeInterval = 6 * 86_400
        let history = start.addingTimeInterval(-86_400)...start.addingTimeInterval(span + 86_400)
        let window = TimelineWindow(
            history: history, centredOn: start.addingTimeInterval(span / 2), span: span)

        #expect(window.spanLabel == "6 d")
        #expect(window.label.contains(start.formatted(.dateTime.weekday(.abbreviated))))
        #expect(window.label.contains(window.end.formatted(.dateTime.weekday(.abbreviated))))
        #expect(window.label.contains("→"))
        // The old label, exactly. It must not be what comes back.
        #expect(window.label != "12:37 – 21:59")
    }

    /// Inside one day the clock alone is sufficient, and the weekday would cost
    /// width in the densest band of the interface for nothing.
    @Test("a window inside one day stays a plain clock range")
    func insideOneDay() {
        let start = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 10, hour: 8, minute: 0))!
        let span: TimeInterval = 6 * 3600
        let history = start.addingTimeInterval(-3600)...start.addingTimeInterval(span + 3600)
        let window = TimelineWindow(
            history: history, centredOn: start.addingTimeInterval(span / 2), span: span)

        #expect(window.spanLabel == "6 h")
        #expect(window.label == "08:00 – 14:00")
    }

    /// The span is written by the same formatter as everything else, so the two
    /// can never drift into "6 d" against "144 h".
    @Test("the span label is the shared duration formatter")
    func sharedFormatter() {
        let base = Date(timeIntervalSince1970: 1_770_000_000)
        let spans: [TimeInterval] = [600, 3600, 3660, 6 * 3600, 86_400, 90_000, 6 * 86_400]
        for span in spans {
            let history = base...base.addingTimeInterval(span)
            let window = TimelineWindow(showingAllOf: history)
            #expect(window.spanLabel == DurationLabel.text(window.span))
        }
    }
}

/// Whether the window *is* the history, which is a different question from
/// whether it is at either end of it.
@Suite("Showing the whole history")
struct WholeHistoryTests {

    private let base = Date(timeIntervalSince1970: 1_770_000_000)
    private var history: ClosedRange<Date> { base...base.addingTimeInterval(6 * 86_400) }

    /// The readout used to render "12:37 – 21:59 of 12:37 – 21:59" whenever the
    /// two coincided, which is the commonest state in the app. A range qualified
    /// by itself is not a qualification.
    @Test("the whole history shows the whole history")
    func wholeHistory() {
        #expect(TimelineWindow(showingAllOf: history).showsWholeHistory)
    }

    @Test("zooming in moves an edge, so it is no longer the whole history")
    func zoomed() {
        let zoomed = TimelineWindow(showingAllOf: history).zoomed(by: 0.5)
        #expect(!zoomed.showsWholeHistory)
        #expect(zoomed.span < TimelineWindow(showingAllOf: history).span)
    }

    /// Panning at full span cannot move anything — the window already fills the
    /// history — so the pan that matters is the one at a narrower span.
    @Test("a panned window is not the whole history, at either end")
    func panned() {
        let narrow = TimelineWindow(history: history, mostRecent: 3600)
        #expect(!narrow.showsWholeHistory)
        #expect(!narrow.pannedToStart.showsWholeHistory)
        #expect(!narrow.pannedToNow.showsWholeHistory)
        #expect(!narrow.panned(by: -7200).showsWholeHistory)
    }

    /// It is not enough to be at one end. A window pinned to the live edge is at
    /// the end and is emphatically not the whole history, which is the
    /// distinction the readout depends on.
    @Test("being at one end is not the same as being the whole of it")
    func atOneEndOnly() {
        let live = TimelineWindow(history: history, mostRecent: 3600)
        #expect(live.isAtEnd)
        #expect(!live.isAtStart)
        #expect(!live.showsWholeHistory)
    }

    /// Zooming back out returns to it, so the readout is not one-way.
    @Test("zooming back out is the whole history again")
    func zoomedBackOut() {
        let all = TimelineWindow(showingAllOf: history)
        #expect(all.zoomed(by: 0.5).zoomed(by: 2).showsWholeHistory)
    }
}
