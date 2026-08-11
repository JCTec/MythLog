import SwiftUI

// Previews are a composition root, exactly like `MythLogApp`, which is why they
// may reach for `MockLedger` when nothing else may. Every value below is read
// off the fixture rather than written out here, so a preview cannot drift from
// what the app would actually derive — and so the subject strings stay honest
// paths without a literal one appearing in a layer that has no business
// carrying one.

extension EventFilter {
    /// A heavy, ordinary filter: two of the six categories off, one event type
    /// selected, the build folder subtracted, a severity floor, and a search.
    fileprivate static var heavyFixtureFilter: EventFilter {
        var filter = EventFilter()
        filter.toggle(.health)
        filter.toggle(.apps)
        filter[.type].include("session.unlock")
        filter[.subject].exclude(FilterPreviewFixtures.buildFolder)
        filter.minimumSeverity = .notice
        filter.query.text = "-path:artifact"
        return filter
    }

    /// A filter nothing satisfies. Distinct from a filter that hides a lot: the
    /// interface has to say "nothing here matches" rather than showing an empty
    /// timeline that reads as a quiet hour.
    fileprivate static var matchesNothing: EventFilter {
        var filter = EventFilter()
        filter.query.text = "kind:session type:carrier-pigeon"
        return filter
    }
}

enum FilterPreviewFixtures {
    /// The fixture's 312-event build storm, as the folder a filter would name.
    static var buildFolder: String {
        MockLedger.events.first { $0.detail.contains(".build") }?.subject ?? ""
    }

    static var buildStormCount: Int {
        MockLedger.events.filter { $0.subject == buildFolder }.count
    }

    /// Enough distinct values to overflow ``Metrics/facetPanelMaxHeight``, taken
    /// from the fixture's build storm rather than written out here — the paths
    /// stay real, and no literal one appears in a layer with no business
    /// carrying it. The cap is deliberately below the number available, so the
    /// "not listed" line is present too.
    static var buildStormFiles: FacetValues {
        FacetValues(
            facet: .subject,
            kind: .files,
            counts: MockLedger.events
                .filter { $0.kind == .files }
                .reduce(into: [String: Int]()) { counts, event in
                    counts[event.detail, default: 0] += 1
                },
            limit: 60)
    }

    /// The values a real derivation would offer for the Files chip, over the
    /// whole fixture.
    static func facetValues(for kind: EventKind) -> [FacetValues] {
        EventFacet.detail.map { facet in
            var counts = [String: Int]()
            for event in MockLedger.events where event.kind == kind {
                let value = facet.value(of: event)
                guard !value.isEmpty else { continue }
                counts[value, default: 0] += 1
            }
            return FacetValues(facet: facet, kind: kind, counts: counts, limit: 12)
        }
    }
}

// MARK: - The page

/// Nothing filtered. The band is absent, the chips carry one number each, and
/// the page looks exactly as it did before this feature existed — which is the
/// baseline the three below have to be judged against.
#Preview("Filters — nothing filtered") {
    MainPage(source: MockTimelineSource(gapWasGraceful: false), request: .fixtureRequest)
        .preferredColorScheme(.dark)
}

// MARK: - The band, in every state it has

#Preview("Filter band — heavy filtering, large hidden count") {
    FilterStateBanner(
        filter: .heavyFixtureFilter,
        totalInWindow: 401,
        hiddenInWindow: 399,
        forcedUntrustedCount: 0,
        restored: nil,
        presetNotice: nil,
        onRemove: { _ in }, onShowEverything: {},
        onAcknowledgeRestored: {}, onDismissPresetNotice: {}
    )
    .padding()
    .frame(width: 1100)
    .background(Palette.canvas)
}

/// The dangerous case. Everything is hidden and nothing matches, so the
/// timeline is empty — and an empty timeline is exactly what somebody worried
/// about their Mac wants to see. The band has to be the reason they do not read
/// it that way.
#Preview("Filter band — a filter matching nothing") {
    FilterStateBanner(
        filter: .matchesNothing,
        totalInWindow: 401,
        hiddenInWindow: 401,
        forcedUntrustedCount: 0,
        restored: nil,
        presetNotice: nil,
        queryProblems: [],
        onRemove: { _ in }, onShowEverything: {},
        onAcknowledgeRestored: {}, onDismissPresetNotice: {}
    )
    .padding()
    .frame(width: 1100)
    .background(Palette.canvas)
}

/// A filter nobody chose this session, over a ledger that also failed
/// verification — the two loudest things this band can say, at once. The
/// untrusted records are on screen despite the filter, and the band says so.
#Preview("Filter band — restored filter, and records shown despite it") {
    FilterStateBanner(
        filter: .heavyFixtureFilter,
        totalInWindow: 401,
        hiddenInWindow: 387,
        forcedUntrustedCount: 12,
        restored: RestoredFilterNotice(
            savedAs: SavedFilter(
                name: "Ignore builds", filter: .heavyFixtureFilter,
                createdAt: MockLedger.day.addingTimeInterval(-6 * 86400)),
            filter: .heavyFixtureFilter),
        presetNotice: nil,
        onRemove: { _ in }, onShowEverything: {},
        onAcknowledgeRestored: {}, onDismissPresetNotice: {}
    )
    .padding()
    .frame(width: 1100)
    .background(Palette.canvas)
}

/// A mistyped field, which is the search failure that reads as an answer.
#Preview("Filter band — a mistyped token") {
    FilterStateBanner(
        filter: {
            var filter = EventFilter()
            filter.query.text = "sevrity:>=warning"
            return filter
        }(),
        totalInWindow: 401,
        hiddenInWindow: 401,
        forcedUntrustedCount: 0,
        restored: nil,
        presetNotice: nil,
        queryProblems: ["sevrity"],
        onRemove: { _ in }, onShowEverything: {},
        onAcknowledgeRestored: {}, onDismissPresetNotice: {}
    )
    .padding()
    .frame(width: 1100)
    .background(Palette.canvas)
}

/// What a preset expanded to, and what it says when it expanded to nothing.
#Preview("Filter band — presets, resolved and unresolved") {
    let types = FacetValues(
        facet: .type, kind: nil,
        values: Array(Set(MockLedger.events.map(\.payloadKind))).sorted()
            .map { FacetValue(value: $0, count: 1) },
        omitted: 0)

    return VStack(spacing: Metrics.space3) {
        ForEach(FilterPreset.all) { preset in
            FilterStateBanner(
                filter: preset.resolved(against: types).filter,
                totalInWindow: 401, hiddenInWindow: 399, forcedUntrustedCount: 0,
                restored: nil,
                presetNotice: preset.resolved(against: types),
                onRemove: { _ in }, onShowEverything: {},
                onAcknowledgeRestored: {}, onDismissPresetNotice: {})
        }

        // The one that found nothing — over a window with no unlocks in it.
        FilterStateBanner(
            filter: EventFilter(),
            totalInWindow: 312, hiddenInWindow: 0, forcedUntrustedCount: 0,
            restored: nil,
            presetNotice: FilterPreset.all[0].resolved(
                against: FacetValues(
                    facet: .type, kind: nil,
                    values: [FacetValue(value: "file.modify", count: 312)], omitted: 0)),
            onRemove: { _ in }, onShowEverything: {},
            onAcknowledgeRestored: {}, onDismissPresetNotice: {})
    }
    .padding()
    .frame(width: 1100)
    .background(Palette.canvas)
}

// MARK: - The per-category panel

/// The Files chip's disclosure, over the fixture — which is where the build
/// storm lives, so this is the panel where the exclusion case is real rather
/// than illustrated.
#Preview("Facet panel — Files, with the build storm in it") {
    FilterFacetPanel(
        kind: .files,
        facetValues: FilterPreviewFixtures.facetValues(for: .files),
        filter: {
            var filter = EventFilter()
            filter[.subject].exclude(FilterPreviewFixtures.buildFolder)
            return filter
        }(),
        onSet: { _, _, _ in }, onClear: { _ in }
    )
    .background(Palette.canvas)
}

#Preview("Facet panel — Session, one type included") {
    FilterFacetPanel(
        kind: .session,
        facetValues: FilterPreviewFixtures.facetValues(for: .session),
        filter: {
            var filter = EventFilter()
            filter[.type].include("session.unlock")
            return filter
        }(),
        onSet: { _, _, _ in }, onClear: { _ in }
    )
    .background(Palette.canvas)
}

/// How tall the panel is, at both ends of what a category can hold.
///
/// `.fixedSize()` is the point of this preview, not decoration: it makes each
/// panel take the height it would *ask a popover for*, so the two heights here
/// are the two numbers that decide whether this panel is presented correctly. A
/// short category hugs its content; a long one stops at
/// ``Metrics/facetPanelMaxHeight`` and scrolls, still saying how many values it
/// did not list.
///
/// Both were the same collapsed sliver once, and nothing caught it, because the
/// panel only misbehaves when a popover presents it *before* its values exist —
/// see `FilterFacetPanel` and `FacetPanelHeightTests`. This preview is the check
/// on the sizes themselves; the test is the check on the order.
#Preview("Facet panel — two values against sixty") {
    HStack(alignment: .top, spacing: Metrics.space4) {
        FilterFacetPanel(
            kind: .session,
            facetValues: [
                FacetValues(
                    facet: .type, kind: .session,
                    values: [
                        FacetValue(value: "session.unlock", count: 3),
                        FacetValue(value: "session.lock", count: 2),
                    ],
                    omitted: 0)
            ],
            filter: EventFilter(),
            onSet: { _, _, _ in }, onClear: { _ in }
        )
        .fixedSize()

        FilterFacetPanel(
            kind: .files,
            facetValues: [FilterPreviewFixtures.buildStormFiles],
            filter: EventFilter(),
            onSet: { _, _, _ in }, onClear: { _ in }
        )
        .fixedSize()
    }
    .padding(Metrics.space4)
    .background(Palette.canvas)
}

/// Before the derivation finishes, and for a category with nothing in the
/// window. Two different emptinesses, which must not look the same.
#Preview("Facet panel — deriving, and empty") {
    HStack(alignment: .top, spacing: Metrics.space3) {
        FilterFacetPanel(
            kind: .drives, facetValues: [], filter: EventFilter(),
            onSet: { _, _, _ in }, onClear: { _ in })
        FilterFacetPanel(
            kind: .drives,
            facetValues: EventFacet.detail.map { .empty(facet: $0, kind: .drives) },
            filter: EventFilter(),
            onSet: { _, _, _ in }, onClear: { _ in })
    }
    .padding()
    .background(Palette.canvas)
}

// MARK: - The timeline and the list, filtered

/// A coverage gap visible while everything else is filtered out.
///
/// The case the whole feature is judged on: the window contains a four-hour
/// silence and 312 filtered-away records, and the only honest thing to draw is
/// the hatching plus a statement of what is being hidden. A blank canvas here
/// would be this app saying nothing happened.
#Preview("Timeline — a gap, with everything else filtered out") {
    let gap = MockLedger.gap

    return VStack(alignment: .leading, spacing: Metrics.space4) {
        TimelineCanvas(
            events: [],
            window: TimelineWindow(
                history: MockLedger.limit,
                centredOn: gap.start.addingTimeInterval(gap.duration / 2),
                span: gap.duration * 1.6),
            gaps: [gap],
            trustBoundary: nil,
            level: .events,
            selected: nil,
            hiddenByFilter: 312,
            onSelect: { _ in }, onZoomTo: { _ in })

        EventList(
            events: [],
            window: TimelineWindow(
                history: MockLedger.limit,
                centredOn: gap.start.addingTimeInterval(gap.duration / 2),
                span: gap.duration * 1.6),
            gaps: [gap],
            trustBoundary: nil,
            hiddenByFilter: 312,
            selected: nil,
            newEventTime: nil,
            onSelect: { _ in }, onJumpToNew: {})
            .frame(height: 320)
    }
    .padding(Metrics.space4)
    .frame(width: 900)
    .background(Palette.canvas)
}

/// The same window with nothing filtered: genuinely empty, and it says so
/// differently. Side by side these two must never be confusable.
#Preview("Timeline — a gap, nothing filtered") {
    let gap = MockLedger.gap
    let window = TimelineWindow(
        history: MockLedger.limit,
        centredOn: gap.start.addingTimeInterval(gap.duration / 2),
        span: gap.duration * 1.6)

    return VStack(alignment: .leading, spacing: Metrics.space4) {
        TimelineCanvas(
            events: [], window: window, gaps: [gap], trustBoundary: nil, level: .events,
            selected: nil, hiddenByFilter: 0, onSelect: { _ in }, onZoomTo: { _ in })

        EventList(
            events: [], window: window, gaps: [gap], trustBoundary: nil, hiddenByFilter: 0,
            selected: nil, newEventTime: nil, onSelect: { _ in }, onJumpToNew: {})
            .frame(height: 320)
    }
    .padding(Metrics.space4)
    .frame(width: 900)
    .background(Palette.canvas)
}

// MARK: - The chip row

#Preview("Filter bar — heavy filtering") {
    FilterBar(
        filter: .heavyFixtureFilter,
        counts: Dictionary(
            grouping: MockLedger.events, by: \.kind
        ).mapValues(\.count),
        passingCounts: [.session: 2, .files: 4, .power: 3, .drives: 3],
        severityCounts: Dictionary(grouping: MockLedger.events, by: \.severity).mapValues(\.count),
        lockedSources: LockedSource.allCases,
        openCategory: nil,
        categoryDetail: [],
        presets: FilterPreset.all,
        savedFilters: [
            SavedFilter(name: "Ignore builds", filter: .heavyFixtureFilter),
            SavedFilter(name: "Security only", filter: .heavyFixtureFilter),
        ],
        activeSavedFilter: SavedFilter(name: "Ignore builds", filter: .heavyFixtureFilter),
        onToggle: { _ in }, onOpenDetail: { _ in }, onCloseDetail: {},
        onSetValue: { _, _, _ in }, onClearFacet: { _ in }, onSetMinimumSeverity: { _ in },
        onApplyPreset: { _ in }, onApplySaved: { _ in }, onDeleteSaved: { _ in },
        onSaveCurrent: { _ in }, onExplainEditions: {}
    )
    .padding()
    .frame(width: 1200)
    .background(Palette.canvas)
}
