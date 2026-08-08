import Foundation
import Testing

@testable import MythLog

/// The filter model itself: what each dimension means, how they compose, and
/// what the search box's tokens parse to.
@Suite("The filter model")
struct EventFilterTests {

    private let base = Date(timeIntervalSince1970: 1_770_000_000)

    private func event(
        _ index: Int = 1,
        kind: EventKind = .files,
        payload: String = "file.modify",
        source: String = "fseventsd",
        detail: String = "/Projects/mythlog/.build/artifact.o",
        label: String = "File changed",
        severity: AlarmSeverity = .info
    ) -> TimelineEvent {
        TimelineEvent(
            record: index, at: base.addingTimeInterval(Double(index)), kind: kind,
            label: label, detail: detail, source: source, payloadKind: payload, severity: severity)
    }

    private func allows(_ filter: EventFilter, _ event: TimelineEvent) -> Bool {
        filter.allows(event, query: filter.query.parsed)
    }

    // MARK: - Include and exclude

    @Test("an empty selection is no opinion, not an empty result")
    func emptySelectionAllowsEverything() {
        // The default that makes a filter safe to add dimensions to: a facet
        // nobody has touched must not start hiding values that arrive later.
        #expect(allows(EventFilter(), event()))
        #expect(EventFilter().isFiltering == false)

        var filter = EventFilter()
        filter[.type] = FacetSelection()
        #expect(filter.isFiltering == false, "an empty selection must not register as a filter")
    }

    @Test("a non-empty include set is a whitelist")
    func inclusionIsAWhitelist() {
        var filter = EventFilter()
        filter[.type].include("session.unlock")

        #expect(allows(filter, event(kind: .session, payload: "session.unlock")))
        #expect(!allows(filter, event(kind: .session, payload: "session.lock")))
        #expect(!allows(filter, event(payload: "file.modify")))
    }

    @Test("exclusion beats inclusion, so the more specific statement wins")
    func exclusionBeatsInclusion() {
        var filter = EventFilter()
        filter[.type].included = ["session.unlock", "session.lock"]
        filter[.type].excluded = ["session.lock"]

        #expect(allows(filter, event(kind: .session, payload: "session.unlock")))
        #expect(
            !allows(filter, event(kind: .session, payload: "session.lock")),
            "a value in both sets must be excluded — subtraction is the more specific statement")

        // And `include` and `exclude` are each the other's undo.
        var selection = FacetSelection()
        selection.include("a")
        selection.exclude("a")
        #expect(selection.included.isEmpty && selection.excluded == ["a"])
        selection.include("a")
        #expect(selection.included == ["a"] && selection.excluded.isEmpty)
    }

    @Test("the fourth value state exists: hidden without having been named")
    func notIncludedIsItsOwnState() {
        var selection = FacetSelection()
        selection.include("session.unlock")

        #expect(selection.state(of: "session.unlock") == .included)
        // Undone differently from an exclusion, so it must read differently.
        #expect(selection.state(of: "session.lock") == .notIncluded)

        selection = FacetSelection()
        #expect(selection.state(of: "session.lock") == .allowed)
    }

    // MARK: - The subject facet

    @Test("a subject is the containing folder, and matching it takes what is underneath")
    func subjectIsAFolderAndMatchesByPrefix() {
        #expect(event(detail: "/Projects/mythlog/.build/artifact.o").subject == "/Projects/mythlog/.build/")
        // Not a path: its own subject, unchanged.
        #expect(event(detail: "Xcode 16.2").subject == "Xcode 16.2")
        #expect(event(detail: "").subject == "")

        var filter = EventFilter()
        filter[.subject].exclude("/Projects/mythlog/")

        // The whole point of prefix matching: one exclusion takes the subtree,
        // rather than 312 object files one at a time.
        #expect(!allows(filter, event(detail: "/Projects/mythlog/.build/artifact.o")))
        #expect(!allows(filter, event(detail: "/Projects/mythlog/Sources/Ledger.swift")))
        #expect(allows(filter, event(detail: "/Documents/lease.pdf")))
    }

    // MARK: - Severity

    @Test("severity is a threshold, and the ordering is the one AlarmSeverity declares")
    func severityIsAThreshold() {
        var filter = EventFilter()
        filter.minimumSeverity = .warning

        #expect(!allows(filter, event(severity: .notice)))
        #expect(allows(filter, event(severity: .warning)))
        #expect(allows(filter, event(severity: .critical)))

        // A floor at the bottom is a constraint that admits everything, and it
        // is deliberately distinguishable from having set none at all.
        filter.minimumSeverity = .debug
        #expect(allows(filter, event(severity: .debug)))
        #expect(filter.isFiltering, "an explicit floor is still a choice the user made")
    }

    // MARK: - Categories

    @Test("a chip is an exclusion, so chips and popovers are one mechanism rather than two")
    func togglingAChipExcludes() {
        var filter = EventFilter()
        #expect(filter.enabledKinds == Set(EventKind.allCases))

        filter.toggle(.files)
        #expect(!filter.includes(.files))
        #expect(filter.enabledKinds == Set(EventKind.allCases).subtracting([.files]))
        #expect(!allows(filter, event(kind: .files)))
        #expect(allows(filter, event(kind: .apps, payload: "app.launched")))

        filter.toggle(.files)
        #expect(filter.includes(.files))
        #expect(!filter.isFiltering, "toggling twice must leave no residue")
    }

    @Test("turning a chip back on while a whitelist is active rejoins the whitelist")
    func togglingBackOnRespectsAWhitelist() {
        var filter = EventFilter()
        filter[.category].included = ["session"]
        #expect(!filter.includes(.files))

        filter.toggle(.files)
        #expect(filter.includes(.files))
        #expect(filter.includes(.session))
        #expect(
            !filter.includes(.apps),
            "re-including one category must not quietly discard the whole whitelist")
    }

    @Test("showing(kinds:) with nothing shows nothing, rather than everything")
    func showingNoKindsHidesEverything() {
        // The trap in a whitelist model: an empty include set means "no opinion",
        // so building "only these" from an empty set must produce exclusions.
        let filter = EventFilter.showing(kinds: [])
        for kind in EventKind.allCases {
            #expect(!allows(filter, event(kind: kind)))
        }
    }

    // MARK: - Query tokens

    @Test("a bare query is still a substring search across headline, detail, and source")
    func plainSearchIsUnchanged() {
        var filter = EventFilter()
        filter.query.text = "lease"
        #expect(allows(filter, event(detail: "/Documents/lease.pdf")))
        #expect(!allows(filter, event(detail: "/Documents/notes.md")))

        // Case-insensitive, and against the source too.
        filter.query.text = "FSEVENTSD"
        #expect(allows(filter, event()))
    }

    @Test("several bare words all have to match, and a quoted run stays a phrase")
    func wordsAreAndedAndQuotesGroup() {
        var filter = EventFilter()
        filter.query.text = "file changed"
        #expect(allows(filter, event(label: "File changed")))
        #expect(!allows(filter, event(detail: "file only", label: "App launched")))

        filter.query.text = "\"screen unlocked\""
        #expect(allows(filter, event(label: "Screen unlocked")))
        #expect(!allows(filter, event(label: "Screen was unlocked")))
    }

    @Test("field tokens parse, and a leading minus subtracts")
    func fieldTokensAndNegation() {
        var filter = EventFilter()

        filter.query.text = "kind:session"
        #expect(allows(filter, event(kind: .session, payload: "session.unlock")))
        #expect(!allows(filter, event(kind: .files)))

        filter.query.text = "-path:.build"
        #expect(!allows(filter, event(detail: "/Projects/x/.build/a.o")))
        #expect(allows(filter, event(detail: "/Documents/lease.pdf")))

        filter.query.text = "source:fseventsd -type:modify"
        #expect(!allows(filter, event(payload: "file.modify")))
        #expect(allows(filter, event(payload: "file.created")))
    }

    @Test("a type token matches loosely, which is what makes it work across two recorder vocabularies")
    func typeTokensAreTolerant() {
        var filter = EventFilter()
        filter.query.text = "type:unlock"

        // This build's fixture writes the first; the shipping recorder writes
        // the second. A token that only matched one would be wrong on half the
        // ledgers this app can open.
        #expect(allows(filter, event(kind: .session, payload: "session.unlock")))
        #expect(allows(filter, event(kind: .session, payload: "session.screen.unlocked")))
        #expect(!allows(filter, event(kind: .session, payload: "session.lock")))
    }

    @Test("severity comparisons parse, including the strict ones and abbreviations")
    func severityTokens() {
        func matches(_ text: String, _ severity: AlarmSeverity) -> Bool {
            var filter = EventFilter()
            filter.query.text = text
            return filter.allows(event(severity: severity), query: filter.query.parsed)
        }

        #expect(matches("severity:>=warning", .warning))
        #expect(matches("severity:>=warning", .critical))
        #expect(!matches("severity:>=warning", .notice))

        #expect(matches("severity:warning", .warning))
        #expect(!matches("severity:warning", .critical), "a bare value is exact, not a floor")

        #expect(matches("severity:>notice", .warning))
        #expect(!matches("severity:>notice", .notice))

        #expect(matches("severity:<=info", .debug))
        #expect(!matches("severity:<=info", .notice))

        #expect(matches("sev:>=warn", .critical), "an unambiguous abbreviation resolves")
    }

    @Test("a clock time is searched as text, not mistaken for a field called 14")
    func numericPrefixIsNotAField() {
        let parsed = FilterQuery.Parsed("14:38")
        #expect(parsed.unrecognisedFields.isEmpty, "'14' is not a field name and must not be reported as one")

        var filter = EventFilter()
        filter.query.text = "14:38"
        #expect(allows(filter, event(detail: "recorded at 14:38")))
    }

    @Test("a mistyped field is searched as text and reported, never silently ignored")
    func unknownFieldsAreReported() {
        // The failure this prevents: `sevrity:>=warning` matches nothing, the
        // timeline empties, and the user reads that as "there were no warnings".
        let parsed = FilterQuery.Parsed("sevrity:>=warning")
        #expect(parsed.unrecognisedFields == ["sevrity"])
        #expect(!parsed.isEmpty, "the token still has to search for something")

        // A known field with an unparseable value is reported too.
        #expect(FilterQuery.Parsed("severity:enormous").unrecognisedFields == ["severity:enormous"])

        #expect(FilterQuery.Parsed("severity:>=warning").unrecognisedFields.isEmpty)
    }

    @Test("kind: resolving to no category matches nothing, rather than becoming no constraint")
    func unknownCategoryMatchesNothing() {
        var filter = EventFilter()
        filter.query.text = "kind:zzz"
        for kind in EventKind.allCases {
            #expect(!allows(filter, event(kind: kind)))
        }
    }

    // MARK: - Describing itself

    @Test("every constraint gets a removable pill, and removing it undoes exactly that one")
    func constraintsAreRemovableOneAtATime() {
        var filter = EventFilter()
        filter[.type].include("session.unlock")
        filter[.subject].exclude("/Projects/x/.build/")
        filter.minimumSeverity = .warning
        filter.query.text = "lease"

        let constraints = filter.constraints
        #expect(constraints.count == 4)
        #expect(Set(constraints.map(\.id)).count == 4, "pill ids must be unique or SwiftUI will reuse rows")

        for constraint in constraints {
            var reduced = filter
            reduced.remove(constraint.removal)
            #expect(reduced != filter)
            #expect(reduced.constraints.count == constraints.count - 1)
        }
    }

    @Test("a facet with many values collapses to one pill that still says how many")
    func manyValuesCollapse() {
        var filter = EventFilter()
        filter[.subject].excluded = Set((0..<20).map { "/folder-\($0)/" })

        let constraints = filter.constraints
        #expect(constraints.count == 1, "twenty pills is a filter bar nobody can read")
        #expect(constraints[0].text == "excluding 20 subjects")

        var cleared = filter
        cleared.remove(constraints[0].removal)
        #expect(!cleared.isFiltering)
    }

    @Test("the chips-only case shows one number; anything else shows two")
    func subFiltersDecideTheCountFormat() {
        var filter = EventFilter()
        #expect(!filter.hasSubFilters)

        filter.toggle(.files)
        #expect(!filter.hasSubFilters, "a chip is not a sub-filter — its own count is unambiguous")

        filter[.source].exclude("fseventsd")
        #expect(filter.hasSubFilters)

        filter = EventFilter()
        filter.minimumSeverity = .warning
        #expect(filter.hasSubFilters)

        filter = EventFilter()
        filter.query.text = "lease"
        #expect(filter.hasSubFilters)
    }

    // MARK: - Persistence

    @Test("a filter survives being written down and read back")
    func filterRoundTrips() throws {
        var filter = EventFilter()
        filter[.type].included = ["session.unlock", "session.screen.unlocked"]
        filter[.subject].excluded = ["/Projects/x/.build/"]
        filter.minimumSeverity = .notice
        filter.query.text = "-path:.build lease"

        let data = try JSONEncoder().encode(filter)
        #expect(try JSONDecoder().decode(EventFilter.self, from: data) == filter)

        let saved = SavedFilter(name: "Ignore builds", filter: filter, createdAt: base)
        let decoded = try JSONDecoder().decode(
            SavedFilter.self, from: try JSONEncoder().encode(saved))
        #expect(decoded == saved)
        #expect(decoded.attribution.contains("Ignore builds"))
    }

    @Test("a filter naming a facet this build does not know decodes without the rest of it failing")
    func unknownFacetsAreSkipped() throws {
        // A filter saved by a later build must not stop this one launching.
        let json = """
            {"facets":[{"facet":"quantum","selection":{"included":["x"],"excluded":[]}},
            {"facet":"type","selection":{"included":["session.unlock"],"excluded":[]}}],
            "query":{"text":""}}
            """
        let filter = try JSONDecoder().decode(EventFilter.self, from: Data(json.utf8))
        #expect(filter[.type].included == ["session.unlock"])
        #expect(filter.constraints.count == 1)
    }

    @Test("saved filters persist, replace by name, and delete")
    func savedFiltersPersist() {
        let suite = "com.jctec.mythlog.playground.tests.\(UUID().uuidString)"
        let store = SavedFilterStore(suiteName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        #expect(store.saved().isEmpty)

        var filter = EventFilter()
        filter[.type].include("session.unlock")
        store.save(SavedFilter(name: "Unlocks", filter: filter))
        #expect(store.saved().count == 1)

        // Saving the same name again replaces rather than duplicating.
        filter.minimumSeverity = .warning
        store.save(SavedFilter(name: "Unlocks", filter: filter))
        #expect(store.saved().count == 1)
        #expect(store.saved()[0].filter.minimumSeverity == .warning)

        store.delete(store.saved()[0].id)
        #expect(store.saved().isEmpty)
    }

    @Test("the active filter is remembered, and an empty one is forgotten rather than stored")
    func activeFilterIsRemembered() {
        let suite = "com.jctec.mythlog.playground.tests.\(UUID().uuidString)"
        let store = SavedFilterStore(suiteName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

        var filter = EventFilter()
        filter[.type].include("session.unlock")
        store.rememberActive(SavedFilterStore.Active(filter: filter, savedAs: nil))
        #expect(store.active()?.filter == filter)

        // Clearing a filter must clear what is restored next launch, or the
        // notice would fire over a filter that is not there.
        store.rememberActive(SavedFilterStore.Active(filter: EventFilter(), savedAs: nil))
        #expect(store.active() == nil)
    }
}

/// Presets: the one-click questions, and what they are allowed to assume.
@Suite("Filter presets")
struct FilterPresetTests {

    private func types(_ values: [String]) -> FacetValues {
        FacetValues(
            facet: .type, kind: nil,
            values: values.map { FacetValue(value: $0, count: 1) }, omitted: 0)
    }

    @Test("“unlocks only” finds the unlock type whichever vocabulary the ledger uses")
    func unlocksResolveAcrossVocabularies() {
        let preset = FilterPreset.all.first { $0.id == "unlocks" }!

        let fixture = preset.resolved(against: types(["session.unlock", "session.lock", "file.modify"]))
        #expect(fixture.matchedTypes == ["session.unlock"])
        #expect(!fixture.foundNothing)

        let shipping = preset.resolved(
            against: types(["session.screen.unlocked", "session.screen.locked", "apps.app.launched"]))
        #expect(shipping.matchedTypes == ["session.screen.unlocked"])
    }

    @Test("a lock is never dragged in by an unlock, and an unmount never by a mount")
    func tokensMatchByPrefixNotSubstring() {
        // `unlocked` contains `lock`; `unmounted` contains `mount`. Matching on
        // substrings would make both presets quietly wrong in the direction that
        // matters — showing more than was asked for.
        let unlocks = FilterPreset.all.first { $0.id == "unlocks" }!
        #expect(!unlocks.matches(type: "session.lock"))
        #expect(!unlocks.matches(type: "session.screen.locked"))

        let physical = FilterPreset.all.first { $0.id == "physical" }!
        #expect(physical.matches(type: "drive.mount"))
        #expect(physical.matches(type: "drives.volume.mounted"))
        #expect(!physical.matches(type: "drives.volume.unmounted"))
    }

    @Test("physical access is every way somebody could have been at the machine")
    func physicalAccessCoversTheWays() {
        let preset = FilterPreset.all.first { $0.id == "physical" }!
        let resolution = preset.resolved(
            against: types([
                "session.unlock", "power.wake", "power.display", "drive.mount",
                "session.userSwitch", "file.modify", "agent.heartbeat",
            ]))

        #expect(
            Set(resolution.matchedTypes) == [
                "session.unlock", "power.wake", "power.display", "drive.mount", "session.userSwitch",
            ])
        // Shown expanded, so the preset teaches the model rather than hiding it.
        #expect(resolution.explanation.contains("session.unlock"))
    }

    @Test("a preset that matches nothing refuses, rather than showing everything")
    func aPresetThatFindsNothingRefuses() {
        // The trap: an unresolved type preset produces a filter with no type
        // constraint, which shows *more* than before. An empty answer must read
        // as an empty answer.
        let preset = FilterPreset.all.first { $0.id == "unlocks" }!
        let resolution = preset.resolved(against: types(["file.modify", "agent.heartbeat"]))

        #expect(resolution.foundNothing)
        #expect(resolution.explanation.contains("Nothing was filtered"))
    }

    @Test("the severity preset does not depend on event types and never reports itself empty")
    func severityPresetIsIndependentOfTypes() {
        let preset = FilterPreset.all.first { $0.id == "warnings" }!
        let resolution = preset.resolved(against: types(["file.modify"]))

        #expect(!resolution.foundNothing)
        #expect(resolution.filter.minimumSeverity == .warning)
        #expect(resolution.filter[.type].isEmpty)
    }
}
