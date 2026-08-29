import AppKit
import Foundation
import SwiftUI
import Testing

@testable import MythLog

/// Where the shots go, and the switch that turns them on. Set through the scheme
/// from a build setting of the same name — see `project.yml`. Empty on an
/// ordinary run, which is what disables the suite.
///
/// A file-scope constant rather than a static member, because a `@Suite`
/// condition that reads a static member of its own type is a circular macro
/// reference.
private let renderDestination = ProcessInfo.processInfo.environment["MYTHLOG_RENDER_SHOTS"] ?? ""

/// A way to *look* at the interface from a process that is not allowed to
/// photograph the screen.
///
/// Screen capture and accessibility are both TCC-gated, and a headless review
/// has neither — `screencapture` answers "could not create image from window"
/// and System Events refuses to enumerate the app's windows. Neither is needed
/// to see the layout: the views can be hosted in this process, in a real
/// `NSWindow` at a real size, and read straight back out of the view hierarchy.
/// The window is fully transparent and nothing outside this process is touched.
///
/// A real window rather than `ImageRenderer`, because `.task` and `onAppear` do
/// not run under `ImageRenderer` — and this page's entire content arrives from
/// an async load started by `.task`, so it would have rendered the empty state
/// and called it a screenshot.
///
/// Off by default. It writes files, it is slow, and it asserts nothing a machine
/// can check — its output is for a person. Run it deliberately:
///
///     xcodebuild … test -only-testing:MythLogEngineTests/RenderShots \
///       MYTHLOG_RENDER_SHOTS=/tmp/mythlog-shots
@Suite("Render shots", .enabled(if: !renderDestination.isEmpty))
@MainActor
struct RenderShots {

    private var directory: URL { URL(fileURLWithPath: renderDestination) }

    /// Hosts `view` at `size`, lets it settle, and writes what it drew.
    ///
    /// - Parameter settle: how long to let it run before reading it back. The
    ///   page loads its history asynchronously and re-derives on a second hop,
    ///   so a snapshot taken immediately catches a spinner.
    private func shoot(
        _ view: some View, size: CGSize, named name: String, settle: TimeInterval = 2.5
    ) async throws {
        let hosting = NSHostingView(
            rootView:
                view
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
        )
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        // On screen, because `.task` and `onAppear` do not run in a window that
        // never appears — and this page's entire content arrives from a `.task`.
        // Fully transparent so nothing is put in front of whoever is at this
        // Mac; `cacheDisplay` reads the view's own drawing, not the screen, so
        // the alpha costs nothing.
        window.alphaValue = 0
        window.orderFrontRegardless()

        // `await`, not a run-loop pump. The page loads from a `.task`, which is
        // main-actor work; a synchronous wait holds the main actor for its whole
        // duration, so the load can never be scheduled and the shot is of an
        // empty page. Suspending here is what lets it run — the first version of
        // this spun the run loop for two and a half seconds and photographed
        // "0 records · no records" every time.
        try await Task.sleep(for: .seconds(settle))
        hosting.layoutSubtreeIfNeeded()

        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("no bitmap for \(name)")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("no PNG for \(name)")
            return
        }
        try png.write(to: directory.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }

    // MARK: - The whole page, at both ends of its width

    /// Criterion one: nothing truncated at the default width, and the filter
    /// band *wraps* rather than ellipsizing when there is not room for it.
    ///
    /// 1000 is below the window's stated 1240 minimum on purpose. At 1240 the
    /// band still fits on one line, so the wrap — the entire reason `FlowRow` is
    /// there — is never exercised, and a layout that would have ellipsized
    /// instead looks identical to one that wraps.
    @Test("the whole page at 1420, at its 1240 minimum, and narrower still")
    func wholePage() async throws {
        for width in [1420.0, 1240.0, 1000.0] {
            try await shoot(
                MainPage(source: MockTimelineSource(gapWasGraceful: false), request: .fixtureRequest),
                size: CGSize(width: width, height: 900),
                named: "page-\(Int(width))"
            )
        }
    }

    /// The case the window label was rewritten for, which the fixture cannot
    /// reach: its history is under fifteen hours, and the contradiction only
    /// appears once a window crosses a midnight. Six days from 12:37 used to
    /// print `12:37 – 21:59` beside a chip reading `Density · 6 d`.
    @Test("a window spanning several days")
    func multiDayWindow() async throws {
        try await shoot(
            MainPage(source: SpreadLedger(), request: .fixtureRequest),
            size: CGSize(width: 1420, height: 900),
            named: "page-multiday"
        )
    }

    /// The wrap itself, which the page cannot show.
    ///
    /// `MainPage` carries `.frame(minWidth: 1240)`, and at 1240 the filter band
    /// still fits on one line — so at every width the *window* can be, `FlowRow`
    /// never wraps, and a layout that would ellipsize instead is
    /// indistinguishable from one that does not. Rendering the band on its own,
    /// below that floor, is the only way to see which of the two is in there.
    @Test("the filter band on its own, narrow enough to have to wrap")
    func filterBandWrapping() async throws {
        for width in [1180.0, 900.0, 700.0] {
            try await shoot(
                FilterBar(
                    filter: EventFilter(),
                    counts: [.session: 5, .power: 3, .apps: 8, .files: 316, .drives: 3, .health: 43],
                    passingCounts: [
                        .session: 5, .power: 3, .apps: 8, .files: 316, .drives: 3, .health: 43,
                    ],
                    severityCounts: [.info: 300, .notice: 60, .warning: 18],
                    lockedSources: LockedSource.allCases,
                    openCategory: nil,
                    categoryDetail: [],
                    presets: FilterPreset.all,
                    savedFilters: [],
                    activeSavedFilter: nil,
                    onToggle: { _ in },
                    onOpenDetail: { _ in },
                    onCloseDetail: {},
                    onSetValue: { _, _, _ in },
                    onClearFacet: { _ in },
                    onSetMinimumSeverity: { _ in },
                    onApplyPreset: { _ in },
                    onApplySaved: { _ in },
                    onDeleteSaved: { _ in },
                    onSaveCurrent: { _ in },
                    onExplainEditions: {}
                )
                .padding(Metrics.space4)
                .background(Palette.canvas),
                size: CGSize(width: width, height: 240),
                named: "filters-\(Int(width))",
                settle: 0.6
            )
        }
    }

    // MARK: - States the fixture does not reach on its own

    /// The explanation appears once. The fixture has a single gap, so the case
    /// the decision exists for has to be built by hand.
    @Test("several gaps in a list")
    func gapList() async throws {
        let base = Date(timeIntervalSince1970: 1_770_000_000)
        let gaps = [
            CoverageGap(
                start: base, end: base.addingTimeInterval(4 * 3600 + 24 * 60),
                lastRecordBefore: 4_628, firstRecordAfter: 4_713, evidence: .unexplained),
            CoverageGap(
                start: base.addingTimeInterval(9 * 3600),
                end: base.addingTimeInterval(9 * 3600 + 18 * 60),
                lastRecordBefore: 4_900, firstRecordAfter: 4_912,
                evidence: .recordedStop(ordinal: 4_900)),
            CoverageGap(
                start: base.addingTimeInterval(20 * 3600),
                end: base.addingTimeInterval(42 * 3600 + 25 * 60),
                lastRecordBefore: 5_100, firstRecordAfter: 5_101, evidence: .unexplained),
        ]

        try await shoot(
            VStack(spacing: Metrics.space2) {
                ForEach(Array(gaps.enumerated()), id: \.offset) { index, gap in
                    CoverageGapBanner(gap: gap, isFirst: index == 0)
                }
                Spacer()
            }
            .padding(Metrics.space4)
            .background(Palette.canvas),
            size: CGSize(width: 900, height: 420),
            named: "gaps",
            settle: 0.6
        )
    }

    /// The facet panel at both ends of what a category can hold.
    ///
    /// `.fixedSize()` inside a window taller than either panel is what makes the
    /// PNG worth looking at: the panel takes the height it would ask a popover
    /// for, so the drawn height *is* the measurement under test. The short one
    /// must hug its two rows; the long one must stop at
    /// `Metrics.facetPanelMaxHeight` and still carry the "not listed" line.
    @Test("the facet panel, short and long")
    func facetPanel() async throws {
        let short = [
            FacetValues(
                facet: .type, kind: .session,
                values: [
                    FacetValue(value: "session.unlock", count: 3),
                    FacetValue(value: "session.lock", count: 2),
                ],
                omitted: 0)
        ]
        // The same values the committed preview shows, so the picture and the
        // preview cannot drift apart.
        let long = [FilterPreviewFixtures.buildStormFiles]

        for (name, values) in [("facet-panel-short", short), ("facet-panel-long", long)] {
            try await shoot(
                VStack {
                    FilterFacetPanel(
                        kind: .session, facetValues: values, filter: EventFilter(),
                        onSet: { _, _, _ in }, onClear: { _ in }
                    )
                    .fixedSize()
                    Spacer(minLength: 0)
                }
                .background(Palette.canvas),
                size: CGSize(width: Metrics.facetPanelWidth, height: 700),
                named: name,
                settle: 1.0
            )
        }
    }

    /// A payload with a path long enough to have been truncated inside its own
    /// quotes, which is the thing that made the block worth checking.
    @Test("an inspector holding a long path")
    func inspector() async throws {
        let event = TimelineEvent(
            record: 34_396,
            at: Date(timeIntervalSince1970: 1_770_000_000),
            kind: .files,
            label: "Build artefact written",
            detail: "~/Projects/mythlog/.build/artifact-311.o",
            source: "com.jctec.mythlog.recorder.files",
            payloadKind: "files.written"
        )

        try await shoot(
            InspectorPanel(event: event, integrity: .verified(recordCount: 34_396))
                .frame(width: 320)
                .background(Palette.surface),
            size: CGSize(width: 340, height: 700),
            named: "inspector",
            settle: 0.6
        )
    }
}

/// Six days of history beginning at 12:37 — the shape the window label and the
/// zoom pill used to disagree about. Sparse on purpose: the point is the axis
/// and the two labels, not the bars.
private struct SpreadLedger: TimelineSource {
    var describedOrigin: String { "six days, generated" }

    func load(_ request: TimelineLoadRequest) async throws -> TimelineSnapshot {
        let start = Calendar.current.date(
            from: DateComponents(year: 2026, month: 6, day: 10, hour: 12, minute: 37))!
        let events = (0..<720).map { index in
            TimelineEvent(
                record: index + 1,
                at: start.addingTimeInterval(Double(index) * 12 * 60),
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
            history: events[0].at...events[events.count - 1].at,
            totalRecords: events.count,
            omittedOlderRecords: 0,
            firstRetainedAt: events[0].at,
            integrity: .verified(recordCount: events.count),
            origin: describedOrigin
        )
    }
}
