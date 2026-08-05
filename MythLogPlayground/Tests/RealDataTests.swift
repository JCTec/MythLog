import Foundation
import Testing

@testable import MythLog

/// The Wave 4 gate: the interface's data comes from a real ledger, streamed,
/// cancellable, and rendered at every zoom level.
@Suite("Loading a real ledger")
struct LedgerTimelineSourceTests {

    private func source(_ ledgerURL: URL) throws -> LedgerTimelineSource {
        LedgerTimelineSource(
            store: try LedgerStore(ledgerURL: ledgerURL, hmacKey: try LedgerFixtures.shippingHMACKey()),
            describedOrigin: ledgerURL.path
        )
    }

    @Test("the ledger the shipping app wrote loads, verifies, and carries its ordinals through")
    func loadsAndVerifies() async throws {
        let temporary = try TemporaryDirectory()
        let snapshot = try await source(try temporary.copyShippingLedger()).load(TimelineLoadRequest())
        let manifest = try LedgerFixtures.shippingManifest()

        #expect(snapshot.totalRecords == manifest.records)
        #expect(snapshot.events.count == manifest.records)
        #expect(snapshot.integrity == .verified(recordCount: manifest.records))

        // Every ordinal survives the load — none lost, none invented — across
        // all fourteen segments.
        #expect(Set(snapshot.events.map(\.record)) == Set(1...manifest.records))

        // And the timeline is in *time* order, which is not the same as ledger
        // order: the fixture's `ledger.rotated` records were stamped when the
        // shipping engine rotated, not within the synthetic history it was
        // writing. Append order is asserted separately, over `LedgerStore`
        // itself, in ShippingLedgerCompatibilityTests.
        #expect(snapshot.events == snapshot.events.sorted { $0.at < $1.at })
    }

    @Test("a tampered ledger loads as a failing history, never as an empty one")
    func tamperedLedgerIsNotEmpty() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try temporary.copyShippingLedger()

        var lines = try String(contentsOf: ledgerURL, encoding: .utf8).split(separator: "\n").map(String.init)
        lines[1] = lines[1].replacingOccurrences(of: "\"fixture-host\"", with: "\"attacker-host\"")
        try (lines.joined(separator: "\n") + "\n").write(to: ledgerURL, atomically: true, encoding: .utf8)

        let snapshot = try await source(ledgerURL).load(TimelineLoadRequest())

        #expect(!snapshot.isEmpty, "a failing ledger must still render its records")
        #expect(!snapshot.integrity.isHealthy)
        guard case .failed(let lastTrusted, let issues, _) = snapshot.integrity else {
            Issue.record("expected .failed, got \(snapshot.integrity)")
            return
        }
        #expect(issues > 0)
        #expect(lastTrusted > 0)
        #expect(snapshot.integrity.bannerBody.contains("remain trustworthy"))
    }

    @Test("a ledger that cannot be read says so — it does not render as no history")
    func unreadableLedgerIsAttributed() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try temporary.copyShippingLedger()
        // Truncate a rotated segment mid-record: unreadable, not absent.
        let segments = try LedgerSegmentNaming.rotatedSegmentURLs(for: ledgerURL, fileManager: FileManager())
        let data = try Data(contentsOf: segments[0])
        try data.prefix(data.count / 2).write(to: segments[0])

        let snapshot = try await source(ledgerURL).load(TimelineLoadRequest())

        guard case .unreadable(let reason) = snapshot.integrity else {
            Issue.record("expected .unreadable, got \(snapshot.integrity)")
            return
        }
        #expect(!reason.isEmpty)
        // The banner must say this out loud rather than showing an empty list.
        #expect(snapshot.integrity.bannerBody.contains("not an empty history"))
        #expect(!snapshot.integrity.isHealthy)
    }

    @Test("a ledger that has never been written is empty and known to be empty")
    func absentLedgerIsHonestlyEmpty() async throws {
        let temporary = try TemporaryDirectory()
        let store = try LedgerStore(
            ledgerURL: temporary.appendingPathComponent("nothing.jsonl"), hmacKey: Data("k".utf8))
        let snapshot = try await LedgerTimelineSource(store: store, describedOrigin: "test")
            .load(TimelineLoadRequest())

        #expect(snapshot.isEmpty)
        #expect(snapshot.totalRecords == 0)
        #expect(snapshot.integrity == .verified(recordCount: 0))
        #expect(snapshot.since == "no records")
    }

    @Test("retention is bounded: the newest events are kept and the rest are counted")
    func retentionIsBounded() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try temporary.copyShippingLedger()
        let manifest = try LedgerFixtures.shippingManifest()

        let snapshot = try await source(ledgerURL)
            .load(TimelineLoadRequest(retainedEventLimit: 40, verify: false))

        #expect(snapshot.events.count == 40)
        #expect(snapshot.totalRecords == manifest.records)
        #expect(snapshot.omittedOlderRecords == manifest.records - 40)

        // The ones kept are the newest by *append* order — the ring buffer sees
        // the stream, not the clock — still carrying the ledger's own ordinals.
        // A ring buffer that unwrapped wrongly would show up here as a missing
        // or duplicated ordinal.
        #expect(Set(snapshot.events.map(\.record)) == Set((manifest.records - 39)...manifest.records))
        #expect(snapshot.events == snapshot.events.sorted { $0.at < $1.at })
        // And the header says the history is partial rather than implying it is
        // everything.
        #expect(snapshot.since.hasPrefix("newest since"))
    }

    /// Regression: over a 130,000-record ledger with 3,044 rotations, gap
    /// analysis on *append* order reported 3,045 coverage gaps instead of 2.
    /// A `ledger.rotated` record is stamped when rotation happens, which need
    /// not sit between its neighbours in time — and every out-of-order stamp
    /// read as a jump forward, and every jump forward read as a silence.
    @Test("records written out of time order do not fabricate coverage gaps")
    func outOfOrderTimestampsDoNotFabricateGaps() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = temporary.appendingPathComponent("events.jsonl")
        let key = Data("out-of-order-key".utf8)
        let store = try LedgerStore(ledgerURL: ledgerURL, hmacKey: key)

        // A minute of heartbeats, appended in an order that is not time order —
        // every tenth record is stamped an hour into the future, as a rotation
        // record written mid-stream would be.
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<120 {
            let offset = index.isMultiple(of: 10) ? 3600.0 : Double(index) * 60
            try await store.append(
                AlarmEvent(
                    observedAt: base.addingTimeInterval(offset),
                    host: "h", source: "agent", name: "agent.heartbeat", severity: .debug,
                    metadata: ["i": "\(index)"]))
        }

        let snapshot = try await LedgerTimelineSource(store: store, describedOrigin: "test")
            .load(TimelineLoadRequest(gapThreshold: HeartbeatConfig(intervalSeconds: 60).gapThreshold))

        // The events reach the timeline in time order…
        #expect(snapshot.events == snapshot.events.sorted { $0.at < $1.at })
        // …and their ledger ordinals are untouched by the reordering.
        #expect(Set(snapshot.events.map(\.record)) == Set(1...120))
        // The only real silence is the one before the twelve future-stamped
        // records, not one per out-of-order record.
        #expect(snapshot.gaps.count <= 1, "found \(snapshot.gaps.count) gaps in a continuous history")
    }

    @Test("a cancelled load stops rather than finishing")
    func loadIsCancellable() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try temporary.copyShippingLedger()
        let loader = try source(ledgerURL)

        let task = Task { try await loader.load(TimelineLoadRequest()) }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

/// Derivation: window-scoped, off the main actor, cancellable, memoised.
@Suite("Timeline derivation")
struct TimelineDerivationTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

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

    private func window(spanMinutes: Double, over events: [TimelineEvent]) -> TimelineWindow {
        let history = (events.first?.at ?? base)...(events.last?.at ?? base.addingTimeInterval(3600))
        return TimelineWindow(history: history, mostRecent: spanMinutes * 60)
    }

    @Test("counts and visible events describe the window, not the whole history")
    func derivationIsWindowScoped() async throws {
        let all = events(600)
        let derivation = TimelineDerivation()
        await derivation.replace(events: all, gaps: [])

        let full = try await derivation.result(
            window: TimelineWindow(showingAllOf: all.first!.at...all.last!.at),
            enabledKinds: Set(EventKind.allCases), query: "")
        #expect(full.totalInWindow == 600)

        let hour = try await derivation.result(
            window: window(spanMinutes: 60, over: all),
            enabledKinds: Set(EventKind.allCases), query: "")
        #expect(hour.totalInWindow < 600)
        #expect(hour.totalInWindow > 0)
        #expect(hour.counts.values.reduce(0, +) == hour.totalInWindow)
    }

    @Test("category counts ignore the category filter, so a chip can say what it would restore")
    func countsPrecedeTheCategoryFilter() async throws {
        let all = events(120)
        let derivation = TimelineDerivation()
        await derivation.replace(events: all, gaps: [])

        let window = TimelineWindow(showingAllOf: all.first!.at...all.last!.at)
        let unfiltered = try await derivation.result(
            window: window, enabledKinds: Set(EventKind.allCases), query: "")
        let filtered = try await derivation.result(
            window: window, enabledKinds: [.session], query: "")

        #expect(filtered.counts == unfiltered.counts)
        #expect(filtered.visibleEvents.allSatisfy { $0.kind == .session })
        #expect(filtered.visibleEvents.count < unfiltered.visibleEvents.count)
    }

    @Test("a repeated window is served from the cache")
    func repeatedWindowsHitTheCache() async throws {
        let derivation = TimelineDerivation()
        await derivation.replace(events: events(5_000), gaps: [])
        let all = events(5_000)
        let a = TimelineWindow(showingAllOf: all.first!.at...all.last!.at)
        let b = window(spanMinutes: 60, over: all)

        // Zoom in, then back out: the second visit to each window is a hit.
        for window in [a, b, a, b, a] {
            _ = try await derivation.result(
                window: window, enabledKinds: Set(EventKind.allCases), query: "")
        }

        let stats = await derivation.cacheStatistics
        #expect(stats.misses == 2)
        #expect(stats.hits == 3)
    }

    @Test("replacing the data drops every cached answer")
    func replacingDataInvalidatesTheCache() async throws {
        let derivation = TimelineDerivation()
        let first = events(100)
        await derivation.replace(events: first, gaps: [])
        let window = TimelineWindow(showingAllOf: first.first!.at...first.last!.at)

        let before = try await derivation.result(
            window: window, enabledKinds: Set(EventKind.allCases), query: "")
        #expect(before.totalInWindow == 100)

        await derivation.replace(events: events(10), gaps: [])
        let after = try await derivation.result(
            window: window, enabledKinds: Set(EventKind.allCases), query: "")
        #expect(after.totalInWindow == 10, "a stale cached answer about somebody's history")

        let stats = await derivation.cacheStatistics
        #expect(stats.hits == 0)
    }

    @Test("a superseded derivation is cancelled part-way, not run to completion")
    func derivationIsCancellable() async throws {
        let derivation = TimelineDerivation()
        // Large enough that the cancellation check inside the loop is reached.
        await derivation.replace(events: events(400_000), gaps: [])
        let window = TimelineWindow(
            showingAllOf: base...base.addingTimeInterval(400_000 * 60))

        let task = Task {
            try await derivation.result(
                window: window, enabledKinds: Set(EventKind.allCases), query: "")
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }

        // And the cancellation was not cached: the same window computes cleanly
        // afterwards.
        let result = try await derivation.result(
            window: window, enabledKinds: Set(EventKind.allCases), query: "")
        #expect(result.totalInWindow == 400_000)
    }

    @Test("gaps are never removed by a filter")
    func gapsAreNotFilterable() async throws {
        let all = events(120)
        let gap = CoverageGap(
            start: all[10].at, end: all[40].at,
            lastRecordBefore: 11, firstRecordAfter: 41, evidence: .unexplained)

        let derivation = TimelineDerivation()
        await derivation.replace(events: all, gaps: [gap])

        let window = TimelineWindow(showingAllOf: all.first!.at...all.last!.at)
        // Every category unticked, and a query nothing matches.
        let result = try await derivation.result(window: window, enabledKinds: [], query: "zzzzz")

        #expect(result.visibleEvents.isEmpty)
        #expect(result.gaps == [gap], "an absence of recording is not an event and no filter may hide it")
    }

    @Test("the zoom level follows span and population together")
    func zoomLevelIsResolvedFromTheWindow() async throws {
        let dense = events(5_000, everySeconds: 1)
        let derivation = TimelineDerivation()
        await derivation.replace(events: dense, gaps: [])

        let history = dense.first!.at...dense.last!.at
        let whole = try await derivation.result(
            window: TimelineWindow(showingAllOf: history),
            enabledKinds: Set(EventKind.allCases), query: "")
        #expect(whole.level == .clusters)

        // Zoomed right in on a dense burst: still clustered, because exploding
        // 600 events into overlapping nodes helps nobody.
        let tight = try await derivation.result(
            window: TimelineWindow(history: history, mostRecent: TimelineWindow.minimumSpan),
            enabledKinds: Set(EventKind.allCases), query: "")
        #expect(tight.level == .clusters)

        // …and sparse enough, it becomes individual events.
        let sparse = events(20, everySeconds: 30)
        await derivation.replace(events: sparse, gaps: [])
        let sparseHistory = sparse.first!.at...sparse.last!.at
        let nodes = try await derivation.result(
            window: TimelineWindow(showingAllOf: sparseHistory),
            enabledKinds: Set(EventKind.allCases), query: "")
        #expect(nodes.level == .events)
    }
}

/// Zoom over a large history must stay responsive. Not a benchmark — a floor.
@Suite("Zoom over a large history")
struct ZoomPerformanceTests {

    @Test("a hundred thousand events derive fast enough for continuous zoom")
    func derivationKeepsUpWithZoom() async throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let events = (0..<100_000).map { index in
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

        let derivation = TimelineDerivation()
        await derivation.replace(events: events, gaps: [])
        let history = events.first!.at...events.last!.at

        // Twelve distinct windows, as a zoom-in-and-out journey produces. Each
        // is a full pass over 100,000 events.
        let clock = ContinuousClock()
        var window = TimelineWindow(showingAllOf: history)
        let elapsed = try await clock.measure {
            for _ in 0..<12 {
                _ = try await derivation.result(
                    window: window, enabledKinds: Set(EventKind.allCases), query: "")
                window = window.zoomed(by: 0.5)
            }
        }

        // Generous: this is a floor that catches an accidental O(n²), not a
        // benchmark. On this machine it runs in a small fraction of it.
        #expect(elapsed < .seconds(5), "12 windows over 100k events took \(elapsed)")

        // The point of the actor: this ran off the main actor, so the interface
        // was free the whole time.
        #expect(await derivation.cacheStatistics.misses == 12)
    }
}
