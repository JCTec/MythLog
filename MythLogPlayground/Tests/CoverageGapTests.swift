import Foundation
import Testing

@testable import MythLog

/// The Wave 4 improvement that matters most: **gaps come from absence, not from
/// stop/start pairs.**
///
/// A graceful stop writes a record. A force-quit, a crash, or a power cut writes
/// nothing — and that is exactly the case a frightened user is looking at. Every
/// test here that involves an unexplained silence would fail against a
/// stop/start implementation.
@Suite("Coverage gaps from absence")
struct CoverageGapTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    /// A 60-second heartbeat, so a gap needs 180 seconds of silence.
    private let threshold = HeartbeatConfig(intervalSeconds: 60).gapThreshold

    /// Heartbeats every 60 s from `from` to `to` minutes, starting at ordinal
    /// `startingAt`.
    private func heartbeats(
        fromMinute from: Double, toMinute to: Double, startingAt ordinal: Int
    ) -> [TimelineEvent] {
        var events = [TimelineEvent]()
        var record = ordinal
        var minute = from
        while minute <= to {
            events.append(
                TimelineEvent(
                    record: record,
                    at: base.addingTimeInterval(minute * 60),
                    kind: .health,
                    label: "Recorder heartbeat",
                    detail: "nominal",
                    source: "agent",
                    payloadKind: "agent.heartbeat"
                ))
            record += 1
            minute += 1
        }
        return events
    }

    private func event(minute: Double, record: Int, payloadKind: String) -> TimelineEvent {
        TimelineEvent(
            record: record,
            at: base.addingTimeInterval(minute * 60),
            kind: .health,
            label: payloadKind,
            detail: "",
            source: String(payloadKind.split(separator: ".").first ?? ""),
            payloadKind: payloadKind
        )
    }

    // MARK: - The case that matters

    @Test("a force-quit leaves no stop record, and the gap is found anyway")
    func unexplainedSilenceIsAGap() {
        // Heartbeats stop dead at minute 30 — no stop record, nothing — and
        // resume at minute 90. A stop/start implementation sees no pair here and
        // reports nothing at all.
        var events = heartbeats(fromMinute: 0, toMinute: 30, startingAt: 1)
        events += heartbeats(fromMinute: 90, toMinute: 120, startingAt: 100)

        let gaps = CoverageAnalysis.gaps(in: events, threshold: threshold)

        #expect(gaps.count == 1)
        let gap = try! #require(gaps.first)
        #expect(gap.evidence == .unexplained)
        #expect(!gap.wasGraceful)
        #expect(gap.start == base.addingTimeInterval(30 * 60))
        #expect(gap.end == base.addingTimeInterval(90 * 60))
        #expect(gap.duration == 60 * 60)
        #expect(gap.durationLabel == "1 h")
    }

    @Test("a graceful stop is the same gap, with the stop record as extra detail")
    func gracefulStopIsAttachedNotRequired() {
        var events = heartbeats(fromMinute: 0, toMinute: 30, startingAt: 1)
        events.append(event(minute: 30.5, record: 32, payloadKind: "agent.stopped"))
        events += heartbeats(fromMinute: 90, toMinute: 120, startingAt: 100)

        let gaps = CoverageAnalysis.gaps(in: events, threshold: threshold)

        #expect(gaps.count == 1)
        let gap = try! #require(gaps.first)
        #expect(gap.evidence == .recordedStop(ordinal: 32))
        #expect(gap.wasGraceful)
        // Detection did not depend on the stop record: removing it still finds
        // the same span.
        let withoutStop = CoverageAnalysis.gaps(
            in: events.filter { $0.payloadKind != "agent.stopped" }, threshold: threshold)
        #expect(withoutStop.count == 1)
        #expect(withoutStop.first?.evidence == .unexplained)
    }

    @Test("a quiet stretch with heartbeats is not a gap")
    func heartbeatsMeanNoGap() {
        // Four hours in which literally nothing happened except heartbeats. The
        // recorder was running the whole time, so this is not a gap — and this
        // is the case a naive "long time between interesting events" rule gets
        // wrong.
        let events = heartbeats(fromMinute: 0, toMinute: 240, startingAt: 1)
        #expect(CoverageAnalysis.gaps(in: events, threshold: threshold).isEmpty)
    }

    @Test("several gaps are all found, in order")
    func multipleGaps() {
        var events = heartbeats(fromMinute: 0, toMinute: 10, startingAt: 1)
        events += heartbeats(fromMinute: 60, toMinute: 70, startingAt: 100)
        events += heartbeats(fromMinute: 200, toMinute: 210, startingAt: 200)

        let gaps = CoverageAnalysis.gaps(in: events, threshold: threshold)
        #expect(gaps.count == 2)
        #expect(gaps[0].start < gaps[1].start)
        #expect(gaps.allSatisfy { $0.evidence == .unexplained })
    }

    @Test("the gap cites the records that bound it, so the claim is checkable")
    func gapCitesItsBounds() {
        var events = heartbeats(fromMinute: 0, toMinute: 5, startingAt: 41)
        events += heartbeats(fromMinute: 60, toMinute: 65, startingAt: 900)

        let gap = try! #require(CoverageAnalysis.gaps(in: events, threshold: threshold).first)
        #expect(gap.lastRecordBefore == 46)
        #expect(gap.firstRecordAfter == 900)
    }

    @Test("a slower heartbeat means a longer silence is still healthy")
    func thresholdFollowsTheConfiguredInterval() {
        var events = heartbeats(fromMinute: 0, toMinute: 5, startingAt: 1)
        events += heartbeats(fromMinute: 20, toMinute: 25, startingAt: 100)

        // 15 minutes of silence. At a 60 s heartbeat that is a gap…
        #expect(!CoverageAnalysis.gaps(in: events, threshold: threshold).isEmpty)
        // …and at a 10-minute heartbeat it is not, because the recorder was not
        // expected to say anything.
        let slow = HeartbeatConfig(intervalSeconds: 600).gapThreshold
        #expect(CoverageAnalysis.gaps(in: events, threshold: slow).isEmpty)
    }

    // MARK: - The configured threshold is a claim, the ledger is the evidence

    @Test("a ledger whose heartbeats are slower than the config claims is not carved into gaps")
    func measuredCadenceRaisesATooTightThreshold() {
        // What a hand-opened ledger gets: no config.json beside it, so
        // `LedgerDiscovery` falls back to 60 s and a 180 s threshold — while the
        // records demonstrate a heartbeat every ten minutes. Every ordinary
        // quiet stretch in this ledger is longer than the threshold.
        var events = [TimelineEvent]()
        var record = 1
        for step in stride(from: 0.0, through: 200.0, by: 10) {
            events.append(
                TimelineEvent(
                    record: record, at: base.addingTimeInterval(step * 60), kind: .health,
                    label: "Recorder heartbeat", detail: "nominal",
                    source: "agent", payloadKind: "agent.agent.heartbeat"))
            record += 1
        }

        #expect(CoverageAnalysis.observedHeartbeatInterval(in: events) == 600)
        #expect(CoverageAnalysis.effectiveThreshold(configured: threshold, events: events) == 1800)
        #expect(
            CoverageAnalysis.gaps(in: events, threshold: threshold).isEmpty,
            "a guessed 180 s threshold turned an unremarkable ledger into a wall of gaps")
    }

    @Test("raising the threshold does not blind it to a real outage")
    func measuredCadenceStillFindsTheOutage() {
        var events = [TimelineEvent]()
        var record = 1
        for step in stride(from: 0.0, through: 200.0, by: 10) where !(60...140).contains(step) {
            events.append(
                TimelineEvent(
                    record: record, at: base.addingTimeInterval(step * 60), kind: .health,
                    label: "Recorder heartbeat", detail: "nominal",
                    source: "agent", payloadKind: "agent.agent.heartbeat"))
            record += 1
        }

        // The median ignores the outage that interrupts the sequence, which is
        // the reason it is a median: a mean would let a four-hour silence raise
        // the threshold until it stopped being detectable.
        #expect(CoverageAnalysis.observedHeartbeatInterval(in: events) == 600)
        let gaps = CoverageAnalysis.gaps(in: events, threshold: threshold)
        #expect(gaps.count == 1)
        // Last heartbeat at minute 50, first after at minute 150 — the gap runs
        // between the records that bound it, not between the missing beats.
        // Explicitly a `TimeInterval`: `100 * 60` on its own is typed as `Int`,
        // and comparing it to an optional `Double` bridges both through
        // `AnyHashable` — which compiles, and is false whatever the values are.
        #expect(gaps.first?.duration == TimeInterval(100 * 60))
    }

    @Test("a configured threshold is never lowered by the records")
    func measuredCadenceOnlyEverRaises() {
        // Heartbeats every 60 s, and a user who configured a ten-minute
        // interval. Their 1800 s stands: they are entitled to have three of
        // their own missed beats taken seriously.
        let events = heartbeats(fromMinute: 0, toMinute: 60, startingAt: 1)
        let slow = HeartbeatConfig(intervalSeconds: 600).gapThreshold
        #expect(CoverageAnalysis.effectiveThreshold(configured: slow, events: events) == slow)
    }

    @Test("a ledger with no heartbeats cannot be measured, and says so by declining to guess")
    func noHeartbeatsMeansNoMeasurement() {
        let events = (0..<10).map {
            event(minute: Double($0) * 5, record: $0 + 1, payloadKind: "apps.app.launched")
        }
        #expect(CoverageAnalysis.observedHeartbeatInterval(in: events) == nil)
        #expect(CoverageAnalysis.effectiveThreshold(configured: threshold, events: events) == threshold)
    }

    @Test("a heartbeat is recognised however the recorder qualified its name")
    func heartbeatsAreRecognisedFromEitherVocabulary() {
        // The shipping recorder writes `source.name` as `agent.agent.heartbeat`;
        // the fixture writes `agent.heartbeat`. Both are heartbeats.
        #expect(CoverageAnalysis.isHeartbeat(event(minute: 0, record: 1, payloadKind: "agent.heartbeat")))
        #expect(CoverageAnalysis.isHeartbeat(event(minute: 0, record: 1, payloadKind: "agent.agent.heartbeat")))
        #expect(!CoverageAnalysis.isHeartbeat(event(minute: 0, record: 1, payloadKind: "apps.app.launched")))
    }

    @Test("fewer than two records cannot establish a gap")
    func degenerateInputs() {
        #expect(CoverageAnalysis.gaps(in: [], threshold: threshold).isEmpty)
        #expect(CoverageAnalysis.gaps(in: heartbeats(fromMinute: 0, toMinute: 0, startingAt: 1),
                                      threshold: threshold).isEmpty)
        // A threshold of zero would make every interval a gap. Refused.
        let events = heartbeats(fromMinute: 0, toMinute: 5, startingAt: 1)
        #expect(CoverageAnalysis.gaps(in: events, threshold: 0).isEmpty)
    }

    @Test("a gap spanning the whole window still counts as overlapping it")
    func overlapIncludesEnclosingGaps() {
        let history = base...base.addingTimeInterval(86_400)
        let gap = CoverageGap(
            start: base,
            end: base.addingTimeInterval(86_400),
            lastRecordBefore: 1,
            firstRecordAfter: 2,
            evidence: .unexplained
        )
        // A window entirely inside the gap: the most important case to draw, and
        // the one a naive containment test misses.
        let window = TimelineWindow(
            history: history, centredOn: base.addingTimeInterval(43_200), span: 3600)
        #expect(CoverageAnalysis.gaps([gap], overlapping: window) == [gap])
    }

    @Test("the fixture's gap is unexplained by default, and graceful on request")
    func fixtureExercisesBothCases() async throws {
        let request = TimelineLoadRequest(
            gapThreshold: HeartbeatConfig(intervalSeconds: MockLedger.heartbeatInterval).gapThreshold,
            verify: false
        )

        let forceQuit = try await MockTimelineSource(gapWasGraceful: false).load(request)
        #expect(forceQuit.gaps.count == 1)
        #expect(forceQuit.gaps.first?.evidence == .unexplained)

        let graceful = try await MockTimelineSource(gapWasGraceful: true).load(request)
        #expect(graceful.gaps.count == 1)
        #expect(graceful.gaps.first?.wasGraceful == true)

        // The silence ends at the same place either way — detection did not
        // depend on the stop record.
        #expect(forceQuit.gaps.first?.end == graceful.gaps.first?.end)

        // It *begins* later in the graceful case, and that is correct rather
        // than incidental: a gap starts at the last evidence the recorder was
        // running, and the stop record is four minutes of evidence the
        // force-quit ledger does not have. Asserting the two starts were equal
        // would have been asserting that the stop record carries no information.
        let forceQuitStart = try #require(forceQuit.gaps.first?.start)
        let gracefulStart = try #require(graceful.gaps.first?.start)
        #expect(gracefulStart > forceQuitStart)
        #expect(try #require(forceQuit.gaps.first).duration > #require(graceful.gaps.first).duration)
    }
}
