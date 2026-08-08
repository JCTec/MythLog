import Foundation
import Testing

@testable import MythLog

/// The two rules no filter may break, and the counting that makes a filter
/// impossible to forget.
///
/// These are not ordinary behaviour tests. A filter that hides a coverage gap or
/// an unverifiable record turns this app into one that tells its user a quiet
/// night happened when it did not — the single failure the product exists to
/// prevent. So they are asserted over the fixture *and* over generated ledgers
/// under randomly-built filters, rather than over one hand-picked case.
@Suite("What a filter may never hide")
struct FilterInvariantTests {

    private let base = Date(timeIntervalSince1970: 1_770_000_000)

    /// A ledger with several silences in it, so gaps of several sizes exist.
    private func ledger(count: Int, silences: [Range<Int>] = []) -> (events: [TimelineEvent], gaps: [CoverageGap]) {
        var events = [TimelineEvent]()
        var record = 1
        let sources = ["loginwindow", "fseventsd", "kernel", "diskarbitrationd", "agent"]
        let payloads = ["session.unlock", "file.modify", "power.wake", "drive.mount", "agent.heartbeat"]
        let details = ["/Projects/x/.build/a.o", "/Documents/lease.pdf", "Xcode 16.2", "\"Backup\" · 2 TB", ""]

        for minute in 0..<count {
            guard !silences.contains(where: { $0.contains(minute) }) else { continue }
            let slot = minute % 5
            events.append(
                TimelineEvent(
                    record: record,
                    at: base.addingTimeInterval(Double(minute) * 60),
                    kind: EventKind.allCases[minute % EventKind.allCases.count],
                    label: "Event \(minute)",
                    detail: details[slot],
                    source: sources[slot],
                    payloadKind: payloads[slot],
                    severity: AlarmSeverity.allCases[minute % AlarmSeverity.allCases.count]
                ))
            record += 1
        }

        let gaps = CoverageAnalysis.gaps(
            in: events, threshold: HeartbeatConfig(intervalSeconds: 60).gapThreshold)
        return (events, gaps)
    }

    /// A deterministic generator, so a failure here is reproducible rather than
    /// something that happened once on somebody's machine.
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    /// Filters spanning every dimension, including ones that match nothing.
    private func filters(count: Int, from events: [TimelineEvent]) -> [EventFilter] {
        var random = Seeded(state: 0x5EED)
        let types = Array(Set(events.map(\.payloadKind))).sorted()
        let sources = Array(Set(events.map(\.source))).sorted()
        let subjects = Array(Set(events.map(\.subject))).sorted()
        let queries = ["", "lease", "kind:session", "-path:.build", "severity:>=warning", "zzzz", "sevrity:x"]

        return (0..<count).map { _ in
            var filter = EventFilter()
            for kind in EventKind.allCases where Bool.random(using: &random) {
                filter.toggle(kind)
            }
            if !types.isEmpty, Bool.random(using: &random) {
                filter[.type].include(types.randomElement(using: &random)!)
            }
            if !sources.isEmpty, Bool.random(using: &random) {
                filter[.source].exclude(sources.randomElement(using: &random)!)
            }
            if !subjects.isEmpty, Bool.random(using: &random) {
                filter[.subject].exclude(subjects.randomElement(using: &random)!)
            }
            if Bool.random(using: &random) {
                filter.minimumSeverity = AlarmSeverity.allCases.randomElement(using: &random)
            }
            filter.query.text = queries.randomElement(using: &random)!
            return filter
        }
    }

    // MARK: - Rule one: gaps

    @Test("no filter, of any shape, removes a coverage gap")
    func gapsSurviveEveryFilter() async throws {
        // Three silences of different lengths. All comfortably longer than the
        // threshold `CoverageAnalysis` derives from this ledger's own heartbeat
        // cadence — a five-minute beat, so fifteen minutes of quiet.
        let (events, gaps) = ledger(count: 900, silences: [100..<120, 300..<340, 500..<560])
        #expect(gaps.count == 3, "the fixture must actually contain gaps or this asserts nothing")

        let derivation = TimelineDerivation()
        await derivation.replace(events: events, gaps: gaps)

        let history = events.first!.at...events.last!.at
        let unfiltered = try await derivation.result(
            window: TimelineWindow(showingAllOf: history), filter: .none)

        for filter in filters(count: 120, from: events) {
            let result = try await derivation.result(
                window: TimelineWindow(showingAllOf: history), filter: filter)
            #expect(
                result.gaps == unfiltered.gaps,
                "a filter changed the gaps: \(filter.summarySentence)")
        }

        // Including the extreme: every category off and a query nothing matches.
        let nothing = try await derivation.result(
            window: TimelineWindow(showingAllOf: history),
            filter: .showing(kinds: [], query: "zzzzzzzz"))
        #expect(nothing.visibleEvents.isEmpty)
        #expect(nothing.gaps == unfiltered.gaps, "an absence of recording is not an event")
        #expect(nothing.hiddenInWindow == nothing.totalInWindow)
    }

    @Test("a gap is still drawn in a window where everything else is filtered away")
    func aGapSurvivesAnEmptiedWindow() async throws {
        let (events, gaps) = ledger(count: 400, silences: [100..<200])
        #expect(!gaps.isEmpty)

        let derivation = TimelineDerivation()
        await derivation.replace(events: events, gaps: gaps)

        // A window centred on the silence, with everything hidden.
        let gap = gaps[0]
        let window = TimelineWindow(
            history: events.first!.at...events.last!.at,
            centredOn: gap.start.addingTimeInterval(gap.duration / 2),
            span: gap.duration * 2)

        let result = try await derivation.result(window: window, filter: .showing(kinds: []))
        #expect(result.visibleEvents.isEmpty)
        #expect(result.gaps.contains(gap), "the only thing left to say about this window was removed")
        #expect(result.hiddenInWindow > 0, "and the count that explains the emptiness must be there")
    }

    // MARK: - Rule two: records that cannot be trusted

    @Test("no filter hides a record that failed verification")
    func untrustedRecordsSurviveEveryFilter() async throws {
        let (events, gaps) = ledger(count: 400)
        // Verification failed two-thirds of the way through.
        let boundaryOrdinal = events[events.count * 2 / 3].record
        let integrity = IntegrityState.failed(
            lastTrustedOrdinal: boundaryOrdinal - 1, issueCount: 40, recordCount: events.count)
        let boundary = try #require(TrustBoundary.resolve(integrity: integrity, events: events))
        let untrusted = events.filter { $0.record >= boundary.firstUntrustedOrdinal }
        #expect(!untrusted.isEmpty)

        let derivation = TimelineDerivation()
        await derivation.replace(events: events, gaps: gaps, trustBoundary: boundary)

        let window = TimelineWindow(showingAllOf: events.first!.at...events.last!.at)

        for filter in filters(count: 80, from: events) {
            let result = try await derivation.result(window: window, filter: filter)
            let shown = Set(result.visibleEvents.map(\.record))
            for record in untrusted.map(\.record) {
                #expect(
                    shown.contains(record),
                    "record #\(record) cannot be trusted and was hidden by: \(filter.summarySentence)")
            }
        }

        // And the interface is told how many are there despite the filter, so it
        // can say why they are on screen.
        let hideEverything = try await derivation.result(
            window: window, filter: .showing(kinds: [], query: "zzzzzzzz"))
        #expect(hideEverything.visibleEvents.count == untrusted.count)
        #expect(hideEverything.forcedUntrustedCount == untrusted.count)
    }

    @Test("with nothing wrong, nothing is forced through — the exemption is not a leak")
    func aHealthyLedgerForcesNothing() async throws {
        let (events, gaps) = ledger(count: 200)
        let derivation = TimelineDerivation()
        await derivation.replace(events: events, gaps: gaps, trustBoundary: nil)

        let result = try await derivation.result(
            window: TimelineWindow(showingAllOf: events.first!.at...events.last!.at),
            filter: .showing(kinds: []))
        #expect(result.visibleEvents.isEmpty)
        #expect(result.forcedUntrustedCount == 0)
    }

    // MARK: - The counts

    @Test("the numbers add up, at every filter, so “hidden” can never be wrong")
    func countsAreConsistent() async throws {
        let (events, gaps) = ledger(count: 600, silences: [200..<240])
        let derivation = TimelineDerivation()
        await derivation.replace(events: events, gaps: gaps)

        let history = events.first!.at...events.last!.at

        for span in [3600.0, 6 * 3600.0, 24 * 3600.0] {
            let window = TimelineWindow(history: history, mostRecent: span)
            for filter in filters(count: 40, from: events) {
                let result = try await derivation.result(window: window, filter: filter)

                #expect(result.hiddenInWindow == result.totalInWindow - result.visibleEvents.count)
                #expect(result.hiddenInWindow >= 0)
                #expect(result.counts.values.reduce(0, +) == result.totalInWindow)
                #expect(result.passingCounts.values.reduce(0, +) == result.visibleEvents.count)

                // The denominator on a chip is the window total, before any
                // filter — that is what makes it stable to compare against while
                // the numerator moves.
                for kind in EventKind.allCases {
                    #expect((result.passingCounts[kind] ?? 0) <= (result.counts[kind] ?? 0))
                }
                // And everything shown really is inside the window.
                #expect(result.visibleEvents.allSatisfy { window.contains($0.at) })
            }
        }
    }

    @Test("the window is found by binary search, and that finds exactly what a scan would")
    func theBinarySearchAgreesWithAScan() async throws {
        let (events, _) = ledger(count: 1_000, silences: [300..<400])
        let history = events.first!.at...events.last!.at

        let derivation = TimelineDerivation()
        await derivation.replace(events: events, gaps: [])

        // Sweep spans and positions, including windows that start before the
        // first record and end after the last.
        for span in [600.0, 3600.0, 12 * 3600.0, 100 * 3600.0] {
            var window = TimelineWindow(history: history, mostRecent: span).pannedToStart
            for _ in 0..<25 {
                let result = try await derivation.result(window: window, filter: .none)
                let scanned = events.filter { $0.at >= window.start && $0.at <= window.end }
                #expect(
                    result.visibleEvents.map(\.record) == scanned.map(\.record),
                    "the slice disagreed with a full scan at \(window.label)")
                window = window.panned(by: span / 3)
            }
        }
    }

    @Test("an unsorted array falls back to a full scan rather than losing history")
    func unsortedDataIsNotSilentlyTruncated() async throws {
        // Both producers sort, so this should be unreachable. Being wrong about
        // it would not crash — it would show a window with events missing from
        // it, which is the one failure mode that looks like data.
        var (events, _) = ledger(count: 300)
        events.swapAt(10, 250)

        let derivation = TimelineDerivation()
        await derivation.replace(events: events, gaps: [])

        let history = events.map(\.at).min()!...events.map(\.at).max()!
        let window = TimelineWindow(showingAllOf: history)
        let result = try await derivation.result(window: window, filter: .none)

        #expect(result.totalInWindow == events.count, "events were dropped from an unsorted array")
    }

    // MARK: - The facet catalogue

    @Test("the offered values come from the window, and change when the window does")
    func facetValuesFollowTheWindow() async throws {
        let (events, _) = ledger(count: 600)
        let derivation = TimelineDerivation()
        await derivation.replace(events: events, gaps: [])

        let history = events.first!.at...events.last!.at

        let whole = try await derivation.values(of: .type, window: TimelineWindow(showingAllOf: history))
        #expect(whole.values.count > 1)
        #expect(whole.values.map(\.count).reduce(0, +) == events.count)
        // Commonest first, so the list does not reshuffle under the pointer.
        #expect(whole.values.map(\.count) == whole.values.map(\.count).sorted(by: >))

        // Scoped to one category, values are that category's.
        let filesOnly = try await derivation.values(
            of: .source, in: .files, window: TimelineWindow(showingAllOf: history))
        let expected = Set(events.filter { $0.kind == .files }.map(\.source)).filter { !$0.isEmpty }
        #expect(Set(filesOnly.values.map(\.value)) == expected)

        // A narrow window offers less, because there is less in it.
        let narrow = try await derivation.values(
            of: .type, window: TimelineWindow(history: history, mostRecent: 600))
        #expect(narrow.values.map(\.count).reduce(0, +) < whole.values.map(\.count).reduce(0, +))
    }

    @Test("a capped list says how many it did not show")
    func truncationIsStated() async throws {
        // 300 distinct subjects, so the cap has to bite.
        let events = (0..<300).map { index in
            TimelineEvent(
                record: index + 1, at: base.addingTimeInterval(Double(index) * 60), kind: .files,
                label: "File changed", detail: "/folder-\(index)/file.txt",
                source: "fseventsd", payloadKind: "file.modify")
        }
        let derivation = TimelineDerivation()
        await derivation.replace(events: events, gaps: [])

        let values = try await derivation.values(
            of: .subject, window: TimelineWindow(showingAllOf: events.first!.at...events.last!.at),
            limit: 20)

        #expect(values.values.count == 20)
        #expect(values.omitted == 280, "a list that quietly stopped would read as an exhaustive one")
        #expect(values.totalDistinct == 300)
    }

    @Test("empty subjects are not offered as a value")
    func emptyValuesAreNotOffered() async throws {
        let (events, _) = ledger(count: 100)
        #expect(events.contains { $0.detail.isEmpty }, "the fixture must contain the case")

        let derivation = TimelineDerivation()
        await derivation.replace(events: events, gaps: [])
        let values = try await derivation.values(
            of: .subject, window: TimelineWindow(showingAllOf: events.first!.at...events.last!.at))

        #expect(!values.values.contains { $0.value.isEmpty })
    }
}

/// The worked example, end to end: the question somebody actually arrives with.
@Suite("Show me only screen unlocks")
struct UnlocksWorkedExampleTests {

    @MainActor
    private func loadedModel() async -> MainPage.Model {
        let model = MainPage.Model(
            source: MockTimelineSource(gapWasGraceful: false),
            request: TimelineLoadRequest(
                gapThreshold: HeartbeatConfig(intervalSeconds: MockLedger.heartbeatInterval).gapThreshold,
                verify: false),
            filterStore: SavedFilterStore(suiteName: "com.jctec.mythlog.playground.tests.\(UUID().uuidString)")
        )
        await model.load()
        return model
    }

    /// Waits for the derivation to catch up. The model deliberately offers no
    /// "finished" signal — the interface renders whatever last completed.
    @MainActor
    private func settle(_ model: MainPage.Model, timeout: Duration = .seconds(10)) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if model.derived.totalInWindow > 0 { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("the derivation never produced a result")
    }

    @MainActor
    @Test("it takes one click, and the timeline resolves to individual unlock nodes")
    func oneClick() async throws {
        let model = await loadedModel()
        try await settle(model)

        // Before: `Session` is one chip covering lock and unlock together, so
        // the question cannot be asked at all.
        #expect(model.visibleEvents.contains { $0.payloadKind == "session.lock" })

        // One click.
        let preset = try #require(FilterPreset.all.first { $0.id == "unlocks" })
        await model.apply(preset)
        try await Task.sleep(for: .milliseconds(200))

        #expect(model.presetNotice?.matchedTypes == ["session.unlock"])
        #expect(!model.visibleEvents.isEmpty)
        #expect(model.visibleEvents.allSatisfy { $0.payloadKind == "session.unlock" })
        #expect(model.visibleEvents.count == 2, "the fixture records two unlocks")

        // And the pleasant consequence: the population drops far below the
        // Events-level threshold, so a sparse row of marks is what gets drawn —
        // which is the right shape for this question.
        #expect(
            model.level == .events,
            "a two-event answer must be drawn as two marks, not as density bars")

        // The state is loud and countable.
        #expect(model.hiddenInWindow > 300)
        #expect(model.filter.constraints.map(\.text) == ["only session.unlock"])
        #expect(model.filterSummary.contains("hidden"))

        // And it is one click back.
        model.showEverything()
        try await Task.sleep(for: .milliseconds(200))
        #expect(!model.filter.isFiltering)
        #expect(model.hiddenInWindow == 0)
    }

    @MainActor
    @Test("excluding the build folder makes the day underneath it readable")
    func excludingTheBuildStormWorks() async throws {
        let model = await loadedModel()
        try await settle(model)

        let before = model.visibleEvents.count
        let storm = try #require(
            model.visibleEvents.first { $0.detail.contains(".build") }).subject

        model.setState(.excluded, for: storm, in: .subject)
        try await Task.sleep(for: .milliseconds(200))

        #expect(model.hiddenInWindow == 312, "the fixture's build storm is 312 events")
        #expect(model.visibleEvents.count == before - 312)
        #expect(!model.visibleEvents.contains { $0.detail.contains(".build/") })
        // Other files survive: this excluded a folder, not a category.
        #expect(model.visibleEvents.contains { $0.kind == .files })
    }

    @MainActor
    @Test("a saved filter that is active on launch announces itself")
    func aRestoredFilterAnnouncesItself() async throws {
        let suite = "com.jctec.mythlog.playground.tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = SavedFilterStore(suiteName: suite)

        var filter = EventFilter()
        filter[.type].include("session.unlock")
        let saved = SavedFilter(name: "Ignore builds", filter: filter)
        store.save(saved)
        store.rememberActive(SavedFilterStore.Active(filter: filter, savedAs: saved))

        let model = MainPage.Model(
            source: MockTimelineSource(gapWasGraceful: false),
            request: TimelineLoadRequest(verify: false),
            filterStore: store)

        #expect(model.filter == filter, "the filter was restored")
        let notice = try #require(model.restored, "a restored filter must announce itself")
        #expect(notice.headline.contains("Ignore builds"))
        #expect(notice.body.contains("not something you chose"))
        #expect(notice.expansion == "only session.unlock")

        // Acknowledging drops the notice and keeps the filter…
        model.acknowledgeRestoredFilter()
        #expect(model.restored == nil)
        #expect(model.filter == filter)

        // …and clearing drops both, and stops it coming back next launch.
        model.showEverything()
        #expect(!model.filter.isFiltering)
        #expect(store.active() == nil)
    }

    @MainActor
    @Test("a filter that was never active does not announce anything")
    func noNoticeWithoutARestoredFilter() async {
        let suite = "com.jctec.mythlog.playground.tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        let model = MainPage.Model(
            source: MockTimelineSource(gapWasGraceful: false),
            request: TimelineLoadRequest(verify: false),
            filterStore: SavedFilterStore(suiteName: suite))

        #expect(model.restored == nil)
        #expect(!model.filter.isFiltering)
    }
}
