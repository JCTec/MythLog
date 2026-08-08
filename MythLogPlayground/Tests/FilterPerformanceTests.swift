import Foundation
import Testing

@testable import MythLog

/// Filtering runs inside ``TimelineDerivation`` on every window change, and
/// window changes arrive several times a second while somebody zooms or pans.
/// Six chips and one substring survived that. A token query, four facets, and a
/// severity floor are a different amount of work, and the point of measuring is
/// that "it feels fine on the fixture" is not evidence about a real ledger.
///
/// These are floors, not benchmarks. They catch an accidental O(n²) and an
/// accidental main-thread pass over a quarter of a million records; they are
/// deliberately loose enough to survive a busy CI machine.
@Suite("Filtering over a large history")
struct FilterPerformanceTests {

    /// A hundred thousand records with realistic shape: several sources, several
    /// subjects, a heavy one (the build storm), and a spread of severities.
    private static func ledger(count: Int) -> [TimelineEvent] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let sources = ["loginwindow", "fseventsd", "kernel", "diskarbitrationd", "agent"]
        let payloads = ["session.unlock", "file.modify", "power.wake", "drive.mount", "agent.heartbeat"]

        return (0..<count).map { index in
            let slot = index % 5
            // Almost every file event comes from one folder, which is what the
            // exclusion case actually looks like — the fixture's build storm is
            // 312 of 364.
            let detail =
                slot == 1
                ? (index % 50 == 1 ? "/Documents/file-\(index).txt" : "/Projects/x/.build/artifact-\(index).o")
                : "subject-\(slot)"
            return TimelineEvent(
                record: index + 1,
                at: base.addingTimeInterval(Double(index) * 60),
                kind: EventKind.allCases[index % EventKind.allCases.count],
                label: "Event \(index)",
                detail: detail,
                source: sources[slot],
                payloadKind: payloads[slot],
                severity: AlarmSeverity.allCases[index % AlarmSeverity.allCases.count]
            )
        }
    }

    /// Exercises every dimension while leaving most of the window visible.
    ///
    /// Used where the test is about *responsiveness* rather than about the cost
    /// of the filter: an assertion that the derivation caught up needs the
    /// derivation to have produced something to catch up with, and a filter
    /// tight enough to empty some windows makes that test flaky about the wrong
    /// thing.
    private static func broadFilter() -> EventFilter {
        var filter = EventFilter()
        filter.toggle(.health)
        filter[.source].exclude("kernel")
        filter[.subject].exclude("/Projects/x/.build/")
        filter.minimumSeverity = .info
        filter.query.text = "-path:artifact"
        return filter
    }

    /// Everything at once: categories off, an inclusion, an exclusion, a subject
    /// prefix, a severity floor, and a token query with a negation.
    private static func heavyFilter() -> EventFilter {
        var filter = EventFilter()
        filter.toggle(.health)
        filter[.type].include("file.modify")
        filter[.source].exclude("kernel")
        filter[.subject].exclude("/Projects/x/.build/")
        filter.minimumSeverity = .info
        filter.query.text = "-path:artifact file"
        return filter
    }

    @Test("a hundred thousand records derive fast enough for continuous zoom with every filter active")
    func heavyFilteringKeepsUpWithZoom() async throws {
        let events = Self.ledger(count: 100_000)
        let derivation = TimelineDerivation()
        await derivation.replace(events: events, gaps: [])

        let history = events.first!.at...events.last!.at
        let filter = Self.heavyFilter()

        // Twelve distinct windows, as a zoom-in-and-out journey produces. The
        // widest is the whole history, so the first is a full pass.
        let clock = ContinuousClock()
        var window = TimelineWindow(showingAllOf: history)
        let elapsed = try await clock.measure {
            for _ in 0..<12 {
                _ = try await derivation.result(window: window, filter: filter)
                window = window.zoomed(by: 0.5)
            }
        }

        #expect(elapsed < .seconds(5), "12 filtered windows over 100k events took \(elapsed)")

        // The results are real, not an empty set that would make this cheap.
        let result = try await derivation.result(
            window: TimelineWindow(showingAllOf: history), filter: filter)
        #expect(!result.visibleEvents.isEmpty)
        #expect(result.hiddenInWindow > 0)
    }

    @Test("narrowing the window makes filtering cheaper, which is what the binary search buys")
    func narrowWindowsAreCheap() async throws {
        let events = Self.ledger(count: 100_000)
        let derivation = TimelineDerivation()
        await derivation.replace(events: events, gaps: [])

        let history = events.first!.at...events.last!.at
        let filter = Self.heavyFilter()
        let clock = ContinuousClock()

        // A one-hour window over a seventy-day history: sixty events out of a
        // hundred thousand. Before the slice was found by binary search this
        // cost the same as the whole history, because it *was* the whole
        // history — every record compared, on every pan.
        var narrow = TimelineWindow(history: history, mostRecent: 3600)
        let elapsed = try await clock.measure {
            for _ in 0..<40 {
                _ = try await derivation.result(window: narrow, filter: filter)
                // A distinct window each time, or the cache answers instead of
                // the code under test.
                narrow = narrow.panned(by: -3600)
            }
        }

        #expect(
            elapsed < .milliseconds(400),
            "40 narrow filtered windows over 100k events took \(elapsed) — that is a full scan per window")
    }

    @MainActor
    @Test("a fast pan with filters active neither blocks the main thread nor queues the windows it passed")
    func filteredSweepStaysResponsive() async throws {
        let model = MainPage.Model(
            source: GeneratedFilterLedger(events: Self.ledger(count: 100_000)),
            request: TimelineLoadRequest(verify: false),
            filterStore: SavedFilterStore(suiteName: "com.jctec.mythlog.playground.tests.\(UUID().uuidString)"))
        await model.load()
        model.filter = Self.broadFilter()
        model.apply(preset: 6 * 3600)
        try await settle(model)

        let clock = ContinuousClock()
        let single = try await clock.measure {
            model.pan(bySeconds: -600)
            try await settle(model)
        }

        // 200 window changes, as a two-finger flick produces.
        let burst = clock.measure {
            for _ in 0..<200 { model.pan(bySeconds: -60) }
        }
        #expect(burst < .milliseconds(250), "200 filtered pans blocked the main thread for \(burst)")

        let settled = try await clock.measure { try await settle(model) }
        #expect(
            settled < single * 20,
            "settling after 200 filtered pans took \(settled) against \(single) for one — that is a queue")

        #expect(model.visibleEvents.allSatisfy { model.window.contains($0.at) })
        #expect(model.window.span == 6 * 3600)
    }

    @MainActor
    @Test("typing in the search box does not stall the interface")
    func typingStaysResponsive() async throws {
        let model = MainPage.Model(
            source: GeneratedFilterLedger(events: Self.ledger(count: 100_000)),
            request: TimelineLoadRequest(verify: false),
            filterStore: SavedFilterStore(suiteName: "com.jctec.mythlog.playground.tests.\(UUID().uuidString)"))
        await model.load()
        try await settle(model)

        // Every keystroke of a token query, over the whole history — the worst
        // case, because the widest window is the one with everything in it.
        let typed = "severity:>=warning"
        let elapsed = ContinuousClock().measure {
            for end in 1...typed.count {
                model.query = String(typed.prefix(end))
            }
        }

        #expect(elapsed < .milliseconds(200), "typing 18 characters blocked the main thread for \(elapsed)")

        // And the query that was typed is the one that ends up applied — polled
        // for, because what settles first may be a derivation of a prefix.
        let deadline = ContinuousClock.now + .seconds(20)
        while ContinuousClock.now < deadline {
            let events = model.visibleEvents
            if !events.isEmpty, events.allSatisfy({ $0.severity >= .warning }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!model.visibleEvents.isEmpty)
        #expect(model.visibleEvents.allSatisfy { $0.severity >= .warning })
    }

    /// Waits for the derivation to catch up with the window.
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

/// A prepared ledger behind the protocol a real one comes through.
private struct GeneratedFilterLedger: TimelineSource {
    var events: [TimelineEvent]
    var describedOrigin: String { "\(events.count) generated events" }

    func load(_ request: TimelineLoadRequest) async throws -> TimelineSnapshot {
        TimelineSnapshot(
            events: events,
            gaps: [],
            history: events.first!.at...events.last!.at,
            totalRecords: events.count,
            omittedOlderRecords: 0,
            firstRetainedAt: events.first!.at,
            integrity: .verified(recordCount: events.count),
            origin: describedOrigin
        )
    }
}
