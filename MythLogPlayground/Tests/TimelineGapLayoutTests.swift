import Foundation
import Testing

@testable import MythLog

/// The coverage-gap overlay, and the contradiction it used to draw.
///
/// The fault worth remembering: hatched spans marked "no coverage" contained
/// bars showing counts of 3, 3, 1, 2, 2, 2, 1. A coverage gap means nothing was
/// recorded, so a bucket cannot both contain events and be a gap — and every
/// test here that mixes bars with hatching would fail against the version that
/// composited two independently-computed pictures.
@Suite("Coverage gap layout")
struct CoverageGapLayoutTests {

    /// Divisible by every step in ``BucketGrid/steps``, so bucket boundaries in
    /// these tests land on whole minutes from `start` and the arithmetic in the
    /// expectations is readable.
    private let start = Date(timeIntervalSince1970: 1_770_000_000)
    private let heartbeat: TimeInterval = 60
    private var threshold: TimeInterval { HeartbeatConfig(intervalSeconds: heartbeat).gapThreshold }

    private func at(_ minute: Double) -> Date { start.addingTimeInterval(minute * 60) }

    /// A minute-by-minute heartbeat ledger with silences cut out of it, plus a
    /// few events of other kinds so the buckets are not uniform.
    private func events(minutes: Double, silences: [Range<Double>]) -> [TimelineEvent] {
        var out = [TimelineEvent]()
        var record = 1_000

        for minute in stride(from: 0.0, through: minutes, by: heartbeat / 60) {
            guard !silences.contains(where: { $0.contains(minute) }) else { continue }
            record += 1
            out.append(
                TimelineEvent(
                    record: record, at: at(minute), kind: .health, label: "Recorder heartbeat",
                    detail: "nominal", source: "agent", payloadKind: "agent.heartbeat"))
        }

        for minute in stride(from: 7.0, through: minutes, by: 23) {
            guard !silences.contains(where: { $0.contains(minute) }) else { continue }
            record += 1
            out.append(
                TimelineEvent(
                    record: record, at: at(minute), kind: .apps, label: "App launched",
                    detail: "test", source: "apps", payloadKind: "apps.app.launched"))
        }

        return out.sorted { $0.at == $1.at ? $0.record < $1.record : $0.at < $1.at }
    }

    private func window(minutes: Double, from startMinute: Double = 0, over historyMinutes: Double) -> TimelineWindow {
        TimelineWindow(
            history: start...at(historyMinutes),
            centredOn: at(startMinute + minutes / 2),
            span: minutes * 60
        )
    }

    private func marks(
        _ events: [TimelineEvent], _ gaps: [CoverageGap], _ window: TimelineWindow
    ) -> (grid: BucketGrid, buckets: [BucketGrid.Bucket], marks: [CoverageGapLayout.Mark]) {
        let grid = BucketGrid(window: window)
        let inWindow = events.filter { window.contains($0.at) }
        let buckets = grid.buckets(over: inWindow)
        return (
            grid, buckets,
            CoverageGapLayout.marks(
                for: CoverageAnalysis.gaps(gaps, overlapping: window), on: grid, buckets: buckets)
        )
    }

    // MARK: - The invariant

    /// The one that matters. Asserted by index *and* geometrically, so an
    /// implementation that stopped carrying bucket indices could not quietly
    /// stop honouring it.
    private func expectNoBarInsideAGap(
        _ events: [TimelineEvent], _ gaps: [CoverageGap], _ window: TimelineWindow,
        _ comment: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let (grid, buckets, marks) = marks(events, gaps, window)

        for mark in marks where mark.isRegion {
            for index in mark.buckets ?? 0...0 {
                #expect(
                    buckets[index].count == 0,
                    "\(comment) — bucket \(index) draws \(buckets[index].count) events inside a gap",
                    sourceLocation: sourceLocation)
            }

            for bucket in buckets where bucket.count > 0 {
                let slot = grid.slot(bucket.id)
                // Touching at a shared edge is not overlapping: a region ends
                // exactly where the next bucket begins.
                let overlaps = mark.start < slot.upperBound - 1e-9 && mark.end > slot.lowerBound + 1e-9
                let where_ = "\(mark.start)…\(mark.end) over bucket \(bucket.id) at \(slot.lowerBound)…\(slot.upperBound)"
                #expect(
                    !overlaps,
                    "\(comment) — hatching \(where_) draws \(bucket.count) events",
                    sourceLocation: sourceLocation)
            }
        }
    }

    @Test("no bucket with events is ever drawn inside a gap — several short silences, every zoom")
    func invariantOverGeneratedSilences() {
        let historyMinutes = 900.0
        let all = events(
            minutes: historyMinutes,
            silences: [100..<108, 111..<116, 119..<125, 128..<133, 300..<370, 500..<504])
        let gaps = CoverageAnalysis.gaps(in: all, threshold: threshold)
        #expect(gaps.count == 6, "the fixture is only interesting if every silence was detected")

        // A sweep, because the fault appeared at one span and not at another:
        // the grid step changes with the window, and so does which gaps fall
        // inside a bucket.
        var regionsSeen = 0
        for spanMinutes in [30.0, 45, 90, 120, 240, 480, 900] {
            for startMinute in stride(from: 0.0, to: historyMinutes - spanMinutes, by: 37) {
                let live = window(minutes: spanMinutes, from: startMinute, over: historyMinutes)
                expectNoBarInsideAGap(all, gaps, live, "span \(spanMinutes) min from \(startMinute)")
                regionsSeen += marks(all, gaps, live).marks.filter(\.isRegion).count
            }
        }

        // An invariant nothing violates because nothing was drawn is not an
        // invariant that was tested.
        #expect(regionsSeen > 0, "the sweep drew no hatched regions at all")
    }

    @Test("filtering events out of the bars cannot put hatching over a bar")
    func invariantWithFiltersApplied() {
        let all = events(minutes: 300, silences: [100..<108, 111..<116, 200..<240])
        let gaps = CoverageAnalysis.gaps(in: all, threshold: threshold)

        // What the canvas is actually handed: gaps from the whole ledger, bars
        // from the visible events only.
        let visible = all.filter { $0.kind != .health }
        for spanMinutes in [90.0, 240, 300] {
            expectNoBarInsideAGap(
                visible, gaps, window(minutes: spanMinutes, over: 300),
                "filtered, span \(spanMinutes) min")
        }
    }

    @Test("the invariant holds over the ledger the shipping app wrote")
    func invariantOverShippingFixture() async throws {
        let temporary = try TemporaryDirectory()
        let snapshot = try await LedgerTimelineSource(
            store: try LedgerStore(
                ledgerURL: try temporary.copyShippingLedger(),
                hmacKey: try LedgerFixtures.shippingHMACKey()),
            describedOrigin: "fixture"
        ).load(TimelineLoadRequest(gapThreshold: HeartbeatConfig(intervalSeconds: 60).gapThreshold))

        let history = try #require(snapshot.events.first?.at)...(try #require(snapshot.events.last?.at))
        for spanMinutes in [30.0, 90, 240, 720, 4320] {
            let window = TimelineWindow(history: history, mostRecent: spanMinutes * 60)
            expectNoBarInsideAGap(
                snapshot.events, snapshot.gaps, window, "fixture, span \(spanMinutes) min")
        }
    }

    // MARK: - Alignment

    @Test("region edges are bucket edges, and bucket edges are where the bars are")
    func regionsAreQuantisedToTheGrid() {
        let all = events(minutes: 300, silences: [100..<170])
        let gaps = CoverageAnalysis.gaps(in: all, threshold: threshold)
        let (grid, _, marks) = marks(all, gaps, window(minutes: 240, over: 300))

        let regions = marks.filter(\.isRegion)
        #expect(!regions.isEmpty)

        for mark in regions {
            let buckets = try! #require(mark.buckets)
            #expect(mark.start == grid.slot(buckets.lowerBound).lowerBound)
            #expect(mark.end == grid.slot(buckets.upperBound).upperBound)
            // And every bucket in between is genuinely inside the gap, not
            // merely adjacent to it.
            for index in buckets {
                let gap = try! #require(mark.gaps.first { $0.start <= grid.start(of: index) && $0.end >= grid.end(of: index) })
                #expect(gap.start <= grid.start(of: index))
            }
        }
    }

    @Test("a bucket half inside a gap is drawn as a bucket, not as half a gap")
    func partialBucketsAreNotHatched() {
        // The silence runs 100–170, and the ten-minute grid puts boundaries on
        // the whole ten minutes. The gap itself therefore runs 99–170: the last
        // heartbeat before it and the first after it. Bucket 90–100 holds that
        // last heartbeat and must keep it.
        let all = events(minutes: 300, silences: [100..<170])
        let gaps = CoverageAnalysis.gaps(in: all, threshold: threshold)
        let (grid, buckets, marks) = marks(all, gaps, window(minutes: 240, over: 300))

        #expect(grid.step == 600)
        let region = try! #require(marks.first { $0.isRegion })
        let covered = try! #require(region.buckets)

        #expect(grid.start(of: covered.lowerBound) == at(100), "hatching may not start mid-bucket")
        #expect(grid.end(of: covered.upperBound) == at(170), "hatching may not end mid-bucket")
        #expect(buckets[covered.lowerBound - 1].count > 0, "the bucket before it still has its records")
    }

    // MARK: - Coalescing

    @Test("near-adjacent gaps read as one absence, not as five blocks with seams")
    func adjacentGapsCoalesce() {
        let all = events(minutes: 300, silences: [100..<108, 111..<116, 119..<125, 128..<133])
        let gaps = CoverageAnalysis.gaps(in: all, threshold: threshold)
        #expect(gaps.count == 4)

        let (_, _, marks) = marks(all, gaps, window(minutes: 240, over: 300))

        #expect(marks.count == 1, "four silences within a bucket of each other drew \(marks.count) marks")
        #expect(marks[0].gaps.count == 4, "the mark must still carry all four for the banner to cite")
        #expect(marks[0].label.contains("4 interruptions"))
    }

    @Test("gaps further apart than a bucket stay apart")
    func distantGapsStaySeparate() {
        let all = events(minutes: 300, silences: [60..<75, 160..<175])
        let gaps = CoverageAnalysis.gaps(in: all, threshold: threshold)
        let (_, _, marks) = marks(all, gaps, window(minutes: 240, over: 300))

        #expect(marks.count == 2)
    }

    @Test("coalescing never rewrites the evidence")
    func coalescingLeavesGapsIntact() {
        let all = events(minutes: 300, silences: [100..<108, 111..<116])
        let gaps = CoverageAnalysis.gaps(in: all, threshold: threshold)
        let groups = CoverageGapLayout.coalesced(gaps, closerThan: 600)

        #expect(groups.count == 1)
        // The banner cites these ordinals, so a merged pair must still be a
        // pair: two real spans, not one invented one.
        #expect(groups[0] == gaps)
        #expect(groups[0][0].lastRecordBefore != groups[0][1].lastRecordBefore)
    }

    @Test("a live stretch between two merged gaps keeps its bar, and the hatching breaks around it")
    func aBarInterruptsAMergedRegion() {
        // Two long silences with nine minutes of recording between them. Merged,
        // because nine minutes is less than one ten-minute bucket — but the
        // bucket holding those records is a bucket with coverage in it.
        let all = events(minutes: 400, silences: [60..<100, 110..<160])
        let gaps = CoverageAnalysis.gaps(in: all, threshold: threshold)
        #expect(gaps.count == 2)

        let live = window(minutes: 240, over: 400)
        let (_, buckets, marks) = marks(all, gaps, live)

        #expect(marks.filter(\.isRegion).count == 2, "the recorded minutes must not be hatched over")
        expectNoBarInsideAGap(all, gaps, live, "merged pair with records between them")
        #expect(buckets.contains { $0.count > 0 && $0.start >= at(100) && $0.start < at(110) })
    }

    // MARK: - Slivers

    @Test("a gap narrower than a bucket is drawn as a tick — never dropped")
    func subBucketGapsSurvive() {
        let all = events(minutes: 300, silences: [124..<128])
        let gaps = CoverageAnalysis.gaps(in: all, threshold: threshold)
        #expect(gaps.count == 1)

        let live = window(minutes: 240, over: 300)
        let (grid, _, marks) = marks(all, gaps, live)

        #expect(grid.step == 600, "a four-minute gap has to be narrower than the bucket for this to test anything")
        #expect(marks.count == 1, "a short gap may change shape, never disappear")
        #expect(marks[0].form == .tick)
        // At the gap's real position, not snapped to anything.
        let centre = live.fraction(of: at(125.5))
        #expect(abs(marks[0].start - centre) < 0.01)
    }

    @Test("every gap in the window is drawn at every zoom level, whatever its size")
    func nothingIsEverDropped() {
        let all = events(minutes: 900, silences: [100..<104, 200..<270, 400..<404, 600..<603])
        let gaps = CoverageAnalysis.gaps(in: all, threshold: threshold)
        #expect(gaps.count == 4)

        for spanMinutes in [90.0, 240, 480, 900] {
            let live = window(minutes: spanMinutes, over: 900)
            let visible = CoverageAnalysis.gaps(gaps, overlapping: live)
            let (_, _, marks) = marks(all, gaps, live)

            let drawn = Set(marks.flatMap { $0.gaps.map(\.id) })
            #expect(
                drawn == Set(visible.map(\.id)),
                "span \(spanMinutes) min drew \(drawn.count) of \(visible.count) gaps")
        }
    }

    @Test("at Events level a gap keeps its real edges — there is no grid to snap to")
    func eventsLevelStaysContinuous() {
        let all = events(minutes: 300, silences: [124..<128])
        let gaps = CoverageAnalysis.gaps(in: all, threshold: threshold)
        let live = window(minutes: 30, from: 112, over: 300)

        let marks = CoverageGapLayout.marks(for: gaps, in: live, minimumWidth: 6.0 / 900)
        #expect(marks.count == 1)
        #expect(marks[0].form == .region)
        #expect(marks[0].start == live.fraction(of: at(123)))
        #expect(marks[0].end == live.fraction(of: at(128)))
    }

    @Test("a gap too narrow to hatch at Events level becomes a tick there too")
    func eventsLevelSliversBecomeTicks() {
        let gap = CoverageGap(
            start: at(100), end: at(100.2), lastRecordBefore: 1, firstRecordAfter: 2,
            evidence: .unexplained)
        let live = window(minutes: 240, over: 300)

        let marks = CoverageGapLayout.marks(for: [gap], in: live, minimumWidth: 6.0 / 900)
        #expect(marks.count == 1)
        #expect(marks[0].form == .tick)
    }

    // MARK: - The grid itself

    @Test("the grid is clock-aligned and covers the window")
    func gridCoversTheWindow() {
        let live = window(minutes: 240, from: 7, over: 900)
        let grid = BucketGrid(window: live)

        #expect(grid.step == 600)
        #expect(grid.start <= live.start)
        #expect(grid.start.timeIntervalSince1970.truncatingRemainder(dividingBy: grid.step) == 0)
        #expect(grid.end(of: grid.count - 1) >= live.end)
        // Edge slots are clipped rather than allowed to hang off the canvas —
        // the drift that put bars where their events were not.
        #expect(grid.slot(0).lowerBound == 0)
        #expect(grid.slot(grid.count - 1).upperBound == 1)
    }

    @Test("every event in the window lands in exactly one bucket")
    func bucketsAccountForEveryEvent() {
        let all = events(minutes: 300, silences: [100..<170])
        let live = window(minutes: 240, from: 30, over: 300)
        let inWindow = all.filter { live.contains($0.at) }
        let buckets = BucketGrid(window: live).buckets(over: inWindow)

        #expect(buckets.map(\.count).reduce(0, +) == inWindow.count)
        for bucket in buckets {
            #expect(bucket.byKind.values.reduce(0, +) == bucket.count)
        }
    }
}
