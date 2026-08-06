import Foundation
import Testing

@testable import MythLog

/// Panning: moving the window sideways through history at a constant span.
///
/// The load-bearing claim is the one in the suite name of the first test —
/// **panning is not zooming**. Every other rule here follows from the window
/// being the thing that moves: it cannot leave the history, it does not touch
/// the selection, and the coverage-gap hatching has to stay on the bucket grid
/// the whole way across.
@Suite("Panning the timeline")
struct TimelinePanningTests {

    private let base = Date(timeIntervalSince1970: 1_770_000_000)

    private func events(_ count: Int, everySeconds: TimeInterval = 60) -> [TimelineEvent] {
        (0..<count).map { index in
            TimelineEvent(
                record: index + 1,
                at: base.addingTimeInterval(Double(index) * everySeconds),
                kind: EventKind.allCases[index % EventKind.allCases.count],
                label: "Event \(index)",
                detail: "detail \(index)",
                source: "test",
                payloadKind: "test.event"
            )
        }
    }

    private var history: ClosedRange<Date> { base...base.addingTimeInterval(11 * 86_400) }

    private func window(spanHours: Double) -> TimelineWindow {
        TimelineWindow(history: history, mostRecent: spanHours * 3600)
    }

    // MARK: - Span is invariant

    @Test("panning changes where the window is and nothing else about it")
    func spanSurvivesPanning() {
        for spanHours in [0.25, 1.0, 4.0, 24.0, 100.0] {
            let start = window(spanHours: spanHours)
            var moving = start

            // Across the whole history and out the other side, in both
            // directions, including the clamped ends.
            for step in stride(from: -20.0, through: 20.0, by: 0.5) {
                moving = moving.panned(by: step * 3600)
                #expect(
                    moving.span == start.span,
                    "a \(spanHours) h window became \(moving.span / 3600) h after panning \(step) h")
            }

            #expect(moving.pannedToStart.span == start.span)
            #expect(moving.pannedToNow.span == start.span)
            #expect(moving.positioned(atFraction: 0.37).span == start.span)
        }
    }

    @Test("a window fully zoomed out cannot be panned anywhere, because there is nowhere")
    func fullHistoryDoesNotMove() {
        let whole = TimelineWindow(showingAllOf: history)
        #expect(whole.panned(by: 86_400) == whole)
        #expect(whole.panned(by: -86_400) == whole)
        #expect(whole.isAtStart)
        #expect(whole.isAtEnd)
        #expect(!whole.canPanEarlier)
        #expect(!whole.canPanLater)
    }

    // MARK: - Clamping

    @Test("the window stops at both ends rather than sliding into empty time")
    func panningClampsToHistory() {
        let live = window(spanHours: 4)

        // Far past either end, in one step and in many.
        let hardLeft = live.panned(by: -365 * 86_400)
        #expect(hardLeft.start == history.lowerBound)
        #expect(hardLeft.isAtStart)
        #expect(!hardLeft.canPanEarlier)

        var walked = live
        for _ in 0..<500 { walked = walked.panned(by: -3600) }
        #expect(walked.start == history.lowerBound, "walking off the start left the history")

        let hardRight = live.panned(by: 365 * 86_400)
        #expect(hardRight.end == history.upperBound)
        #expect(hardRight.isAtEnd)
        #expect(!hardRight.canPanLater)

        // And never outside, anywhere in between.
        for step in stride(from: -400.0, through: 400.0, by: 7) {
            let moved = live.panned(by: step * 3600)
            #expect(moved.start >= history.lowerBound)
            #expect(moved.end <= history.upperBound.addingTimeInterval(0.001))
        }
    }

    @Test("the live edge is where new records arrive, and panning away from it is a state you can read")
    func liveEdgeIsKnown() {
        let live = window(spanHours: 4)
        #expect(live.isAtEnd, "a `mostRecent` window is by definition at the end")

        let away = live.panned(by: -6 * 3600)
        #expect(!away.isAtEnd)
        #expect(away.canPanLater)

        // Re-attaching is one operation, and it is exact rather than
        // approximately-at-the-end.
        #expect(away.pannedToNow.isAtEnd)
        #expect(away.pannedToNow.end == history.upperBound)

        // Panning right in steps also re-attaches, and stops there.
        var walked = away
        for _ in 0..<50 { walked = walked.panned(by: 3600) }
        #expect(walked.isAtEnd)
        #expect(walked.span == live.span)
    }

    @Test("position in history describes where the window sits, and stays inside 0…1")
    func positionIsBounded() {
        let live = window(spanHours: 4)
        #expect(live.positionInHistory.upperBound == 1)

        let start = live.pannedToStart
        #expect(start.positionInHistory.lowerBound == 0)

        // Monotonic: panning later never moves the indicator backwards.
        var previous = start.positionInHistory.lowerBound
        var moving = start
        // Enough six-hour steps to cross eleven days and land on the far edge:
        // 264 hours of history, so 44 of them, and a few to spare.
        for _ in 0..<60 {
            moving = moving.panned(by: 6 * 3600)
            let position = moving.positionInHistory
            #expect(position.lowerBound >= previous - 1e-9)
            #expect(position.lowerBound >= 0 && position.upperBound <= 1)
            previous = position.lowerBound
        }
        #expect(moving.positionInHistory.upperBound == 1, "the sweep should have reached the end")
    }

    @Test("a drag on the position bar puts the window where it was dropped")
    func scrubbingPositionsTheWindow() {
        let live = window(spanHours: 4)

        #expect(live.positioned(atFraction: 0).isAtStart)
        #expect(live.positioned(atFraction: 1).isAtEnd)
        // Out-of-range fractions clamp rather than escaping — a drag runs past
        // the ends of the track constantly.
        #expect(live.positioned(atFraction: -3).isAtStart)
        #expect(live.positioned(atFraction: 4).isAtEnd)

        let half = live.positioned(atFraction: 0.5)
        let expected = history.lowerBound.addingTimeInterval(
            history.upperBound.timeIntervalSince(history.lowerBound) / 2)
        #expect(abs(half.start.timeIntervalSince(expected)) < 1)
    }

    // MARK: - Gaps stay on the grid

    /// The `BucketGrid` work must not regress under panning: it is the same
    /// invariant, asserted at every window a sweep passes through.
    @Test("coverage-gap hatching stays aligned to the bucket grid all the way across")
    func gapsStayAlignedWhilePanning() {
        // A ledger with silences of several sizes, so a pan crosses gaps that
        // are wider than a bucket, narrower than one, and straddling a boundary.
        var all = [TimelineEvent]()
        var record = 1
        let silences: [Range<Double>] = [100..<108, 111..<116, 300..<370, 500..<504, 700..<760]
        for minute in stride(from: 0.0, through: 900.0, by: 1) {
            guard !silences.contains(where: { $0.contains(minute) }) else { continue }
            all.append(
                TimelineEvent(
                    record: record, at: base.addingTimeInterval(minute * 60), kind: .health,
                    label: "Recorder heartbeat", detail: "nominal",
                    source: "agent", payloadKind: "agent.heartbeat"))
            record += 1
        }
        let gaps = CoverageAnalysis.gaps(
            in: all, threshold: HeartbeatConfig(intervalSeconds: 60).gapThreshold)
        #expect(gaps.count == silences.count)

        let history = base...base.addingTimeInterval(900 * 60)
        var regionsSeen = 0

        for spanMinutes in [30.0, 90, 240] {
            var live = TimelineWindow(history: history, mostRecent: spanMinutes * 60).pannedToStart

            // Sweep the whole history in eighth-window steps, which lands the
            // grid on a different offset almost every time.
            for _ in 0..<80 {
                let grid = BucketGrid(window: live)
                let inWindow = all.filter { live.contains($0.at) }
                let buckets = grid.buckets(over: inWindow)
                let marks = CoverageGapLayout.marks(
                    for: CoverageAnalysis.gaps(gaps, overlapping: live), on: grid, buckets: buckets)

                for mark in marks where mark.isRegion {
                    let covered = try! #require(mark.buckets)
                    regionsSeen += 1
                    // Edges on bucket edges…
                    #expect(mark.start == grid.slot(covered.lowerBound).lowerBound)
                    #expect(mark.end == grid.slot(covered.upperBound).upperBound)
                    // …and never over a bar.
                    for index in covered {
                        let where_ = "panned to \(live.label), bucket \(index)"
                        #expect(
                            buckets[index].count == 0,
                            "\(where_) draws \(buckets[index].count) events inside a gap")
                    }
                }

                live = live.panned(by: live.span / 8)
            }
        }

        #expect(regionsSeen > 0, "the sweep drew no hatched regions, so it asserted nothing")
    }

    // MARK: - The page

    @MainActor
    private func loadedModel(_ source: any TimelineSource = MockTimelineSource(gapWasGraceful: false)) async
        -> MainPage.Model
    {
        let model = MainPage.Model(
            source: source,
            request: TimelineLoadRequest(
                gapThreshold: HeartbeatConfig(intervalSeconds: MockLedger.heartbeatInterval).gapThreshold,
                verify: false)
        )
        await model.load()
        return model
    }

    @MainActor
    @Test("panning the page keeps the span, the selection, and the filters")
    func panningThePageChangesOnlyTheWindow() async {
        let model = await loadedModel()
        model.apply(preset: 3600)

        let span = model.window.span
        let selected = model.selected
        let kinds = model.enabledKinds

        model.panEarlier()
        model.panEarlier()

        #expect(model.window.span == span, "panning changed the zoom")
        #expect(model.selected?.record == selected?.record, "panning changed the selection")
        #expect(model.enabledKinds == kinds)
        #expect(model.window.start < TimelineWindow(history: model.history, mostRecent: span).start)

        // A quarter of the window per press, so two presses move half of one.
        let expected = TimelineWindow(history: model.history, mostRecent: span)
            .panned(by: -span / 2)
        #expect(abs(model.window.start.timeIntervalSince(expected.start)) < 1)
    }

    @MainActor
    @Test("panning to the right edge re-attaches to live, and the page says which state it is in")
    func panningToTheEdgeReattaches() async {
        let model = await loadedModel()
        model.apply(preset: 3600)
        #expect(model.isFollowingLive, "a preset shows the most recent span, which is the live edge")

        model.panEarlier()
        #expect(!model.isFollowingLive)
        #expect(model.canPanLater)

        model.panLater()
        #expect(model.isFollowingLive, "panning back to the edge must re-attach")

        // And so does the jump, from anywhere.
        model.jumpToStart()
        #expect(!model.isFollowingLive)
        #expect(!model.canPanEarlier)
        model.jumpToNow()
        #expect(model.isFollowingLive)
    }

    @MainActor
    @Test("the newest-event affordance goes to the newest record and to the live edge, not one of the two")
    func jumpToNewestReattaches() async {
        let model = await loadedModel()
        model.apply(preset: 3600)
        model.jumpToStart()
        #expect(!model.isFollowingLive)

        model.jumpToNewest()

        #expect(model.isFollowingLive)
        #expect(model.selected?.record == model.snapshot.events.last?.record)
        #expect(model.window.contains(try! #require(model.selected).at))
        #expect(!model.isSelectionOffscreen)
    }

    @MainActor
    @Test("a selection panned out of view is kept, reported, and can be returned to")
    func offscreenSelectionIsKeptAndRecoverable() async {
        let model = await loadedModel()
        model.apply(preset: 3600)
        let selected = try! #require(model.selected)
        #expect(!model.isSelectionOffscreen)

        model.jumpToStart()

        #expect(model.selected?.record == selected.record, "panning must not clear the selection")
        #expect(model.isSelectionOffscreen, "an off-screen selection has to be reported, not hidden")

        model.revealSelection()

        #expect(!model.isSelectionOffscreen)
        #expect(model.window.contains(selected.at))
        #expect(model.selected?.record == selected.record)
    }

    @MainActor
    @Test("⌥-arrow moves the selection and leaves the window; arrow moves the window and leaves the selection")
    func steppingAndPanningAreDifferentOperations() async {
        let model = await loadedModel()
        model.apply(preset: 24 * 3600)
        try? await Task.sleep(for: .milliseconds(200))

        let windowBefore = model.window
        model.selectPreviousEvent()
        let stepped = model.selected
        #expect(model.window == windowBefore, "stepping the selection moved the window")
        #expect(stepped != nil)

        model.selectNextEvent()
        #expect(model.window == windowBefore)

        // Stepping clamps rather than wrapping.
        for _ in 0..<500 { model.selectNextEvent() }
        #expect(model.selected?.record == model.visibleEvents.last?.record)
        for _ in 0..<1000 { model.selectPreviousEvent() }
        #expect(model.selected?.record == model.visibleEvents.first?.record)
    }

    @MainActor
    @Test("a reload holds the reader's position, and follows the live edge for a reader who was at it")
    func reloadKeepsPositionOrFollowsLive() async {
        let model = await loadedModel()
        model.apply(preset: 3600)
        let liveSpan = model.window.span

        // At the live edge: a reload re-pins to the edge at the same span
        // rather than throwing away the zoom.
        await model.reverify()
        #expect(model.isFollowingLive)
        #expect(model.window.span == liveSpan)

        // Reading history: a reload holds the position. Being moved to now
        // because the recorder wrote a heartbeat is the failure this prevents.
        model.jumpToStart()
        let held = model.window
        let selected = model.selected
        await model.reverify()

        #expect(!model.isFollowingLive)
        #expect(abs(model.window.start.timeIntervalSince(held.start)) < 1)
        #expect(model.window.span == held.span)
        // And the selection survives, matched by ledger ordinal — a reload
        // mints new `TimelineEvent` identities for the same records.
        #expect(model.selected?.record == selected?.record)
    }
}

/// A ledger of a given size, behind the same protocol a real one comes through.
private struct GeneratedLedger: TimelineSource {
    var count: Int
    var describedOrigin: String { "\(count) generated events" }

    func load(_ request: TimelineLoadRequest) async throws -> TimelineSnapshot {
        let base = Date(timeIntervalSince1970: 1_770_000_000)
        let events = (0..<count).map { index in
            TimelineEvent(
                record: index + 1,
                at: base.addingTimeInterval(Double(index) * 60),
                kind: EventKind.allCases[index % EventKind.allCases.count],
                label: "Event \(index)",
                detail: "detail \(index)",
                source: "test",
                payloadKind: "test.event"
            )
        }
        return TimelineSnapshot(
            events: events,
            gaps: [],
            history: events[0].at...events[count - 1].at,
            totalRecords: count,
            omittedOlderRecords: 0,
            firstRetainedAt: events[0].at,
            integrity: .verified(recordCount: count),
            origin: describedOrigin
        )
    }
}

/// Panning fires window changes as fast as a trackpad emits them. That is the
/// same pressure zoom already creates, and it must be answered the same way:
/// off the main actor, cancelling what it supersedes.
@Suite("Panning over a large history")
struct PanningPerformanceTests {

    @MainActor
    @Test("a fast sweep over 100,000 records neither blocks the main thread nor queues the windows it passed")
    func fastSweepStaysResponsive() async throws {
        let model = MainPage.Model(
            source: GeneratedLedger(count: 100_000),
            request: TimelineLoadRequest(verify: false))
        await model.load()
        model.apply(preset: 3600)
        try await settle(model)

        // How long one derivation over this history takes, measured rather than
        // guessed, so the bound below is not a constant tuned to this machine.
        let clock = ContinuousClock()
        let single = try await clock.measure {
            model.pan(bySeconds: -600)
            try await settle(model)
        }

        // The sweep: 200 window changes, as a two-finger flick produces.
        let burst = clock.measure {
            for _ in 0..<200 { model.pan(bySeconds: -60) }
        }

        // The interface was free the whole time. If derivation ran on the main
        // actor this would be 200 full passes over 100,000 events — seconds,
        // not milliseconds.
        #expect(burst < .milliseconds(250), "200 pans blocked the main thread for \(burst)")

        let settled = try await clock.measure { try await settle(model) }

        // Superseded, not queued: settling costs about one derivation, not two
        // hundred. Twenty is loose enough to survive a busy CI machine and far
        // below what a queue would cost.
        #expect(
            settled < single * 20,
            "settling after 200 pans took \(settled) against \(single) for one — that is a queue")

        // And what settled describes the window the sweep ended on, not one it
        // passed through.
        #expect(model.visibleEvents.allSatisfy { model.window.contains($0.at) })
        #expect(!model.visibleEvents.isEmpty)
        #expect(model.window.span == 3600)
    }

    /// Waits for the derivation to catch up with the window.
    ///
    /// Polling, because the model deliberately offers no "derivation finished"
    /// signal — the interface renders whatever the last completed derivation
    /// produced, and a test that could await it would be testing something the
    /// app does not have.
    @MainActor
    private func settle(_ model: MainPage.Model, timeout: Duration = .seconds(20)) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let events = model.visibleEvents
            if !events.isEmpty, events.allSatisfy({ model.window.contains($0.at) }) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("the derivation never caught up with the window")
    }
}
