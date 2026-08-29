import SwiftUI

/// The template filled with mock data and wired to real interaction.
struct MainPage: View {
    @State private var model: Model

    /// Whether the search field is being edited. It gates the Timeline menu:
    /// while a text field has the keyboard, the arrow keys belong to it.
    @FocusState private var isSearching: Bool

    /// What is loaded, so the header can always say so. The page still cannot
    /// tell a fixture from a real ledger by looking at the *data* — which is
    /// what keeps the design honest — it is simply told which it was handed.
    private let loaded: LoadedLedger?
    private let onClose: (() -> Void)?

    /// The data source is injected, never reached for.
    init(
        source: any TimelineSource,
        request: TimelineLoadRequest = TimelineLoadRequest(),
        loaded: LoadedLedger? = nil,
        onClose: (() -> Void)? = nil
    ) {
        _model = State(initialValue: Model(source: source, request: request))
        self.loaded = loaded
        self.onClose = onClose
    }

    var body: some View {
        MainWindowTemplate {
            HeaderBar(
                edition: "App Store edition",
                integrity: model.integrity,
                recordCount: model.snapshot.totalRecords,
                since: model.snapshot.since,
                loaded: loaded,
                onClose: onClose,
                query: $model.query,
                queryFocus: $isSearching
            )
        } filters: {
            VStack(alignment: .leading, spacing: Metrics.space2) {
                FilterBar(
                    filter: model.filter,
                    counts: model.counts,
                    passingCounts: model.passingCounts,
                    severityCounts: model.severityCounts,
                    lockedSources: LockedSource.allCases,
                    openCategory: model.openCategory,
                    categoryDetail: model.categoryDetail,
                    presets: FilterPreset.all,
                    savedFilters: model.savedFilters,
                    activeSavedFilter: model.activeSavedFilter,
                    onToggle: model.toggle,
                    onOpenDetail: model.openDetail(for:),
                    onCloseDetail: model.closeDetail,
                    onSetValue: { facet, value, state in model.setState(state, for: value, in: facet) },
                    onClearFacet: model.clear(_:),
                    onSetMinimumSeverity: { model.minimumSeverity = $0 },
                    onApplyPreset: { preset in Task { await model.apply(preset) } },
                    onApplySaved: model.apply(_:),
                    onDeleteSaved: model.delete(_:),
                    onSaveCurrent: model.saveCurrentFilter(named:),
                    onExplainEditions: {}
                )

                // Directly above the timeline it qualifies, never in a corner and
                // never behind a disclosure: a filtered view of somebody's
                // history has to announce itself where they are already looking.
                FilterStateBanner(
                    filter: model.filter,
                    totalInWindow: model.derived.totalInWindow,
                    hiddenInWindow: model.hiddenInWindow,
                    forcedUntrustedCount: model.forcedUntrustedCount,
                    restored: model.restored,
                    presetNotice: model.presetNotice,
                    queryProblems: model.queryProblems,
                    onRemove: model.remove(_:),
                    onShowEverything: model.showEverything,
                    onAcknowledgeRestored: model.acknowledgeRestoredFilter,
                    onDismissPresetNotice: model.dismissPresetNotice
                )
            }
        } timeline: {
            VStack(alignment: .leading, spacing: Metrics.space3) {
                timelineHeader
                canvas
                HistoryPositionBar(
                    window: model.window,
                    isLive: model.isFollowingLive,
                    onScrub: model.scrub(toFraction:),
                    onJumpToNow: model.jumpToNow
                )
            }
        } list: {
            VStack(spacing: Metrics.space3) {
                // Above the history it is about, never over it: "which records
                // changed?" is answered by the list, not by a dialog covering it.
                if model.integrity.needsBanner {
                    IntegrityBanner(
                        state: model.integrity,
                        onPrimary: { Task { await model.reverify() } },
                        onSecondary: {}
                    )
                }

                EventList(
                    events: model.visibleEvents,
                    window: model.window,
                    gaps: model.gaps,
                    trustBoundary: model.trustBoundary,
                    // The list carries the hidden count too. The banner above is
                    // the loud statement; this is the one still on screen when
                    // somebody has scrolled the list and is reading rows.
                    hiddenByFilter: model.hiddenInWindow,
                    selected: model.selected,
                    newEventTime: "14:37",
                    onSelect: { model.selected = $0 },
                    // Both halves of the request: the newest record, and the
                    // live edge it lives at.
                    onJumpToNew: model.jumpToNewest
                )
            }
        } inspector: {
            InspectorPanel(
                event: model.selected,
                integrity: model.integrity,
                trustBoundary: model.trustBoundary,
                isOutsideWindow: model.isSelectionOffscreen,
                onReveal: model.revealSelection
            )
        }
        .frame(minWidth: 1240, minHeight: 820)
        // The load starts when the page appears and is cancelled with it, so
        // closing the window during a two-year read stops the read.
        .task { await model.load() }
        // Zoom must never be gesture-only: gestures are not keyboard-reachable
        // and not operable under VoiceOver.
        .onKeyPress(keys: ["=", "+", "-", "0"]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            switch press.key.character {
            case "=", "+": model.zoomIn()
            case "-": model.zoomOut()
            default: model.resetZoom()
            }
            return .handled
        }
        // Published while this page is the active scene's content — and
        // deliberately *not* while the search field is being edited, so ⌘← and
        // ⌥← stay "beginning of line" and "back one word" in a text field. See
        // ``MainPage/Commands``.
        .focusedSceneValue(
            \.timelineCommands,
            isSearching
                ? nil
                : Commands(
                    panEarlier: model.panEarlier,
                    panLater: model.panLater,
                    jumpToStart: model.jumpToStart,
                    jumpToNow: model.jumpToNow,
                    selectPrevious: model.selectPreviousEvent,
                    selectNext: model.selectNextEvent,
                    canPanEarlier: model.canPanEarlier,
                    canPanLater: model.canPanLater
                )
        )
    }

    /// The canvas, plus the two ways to pan it directly.
    ///
    /// Both are accelerators over the same intent the Timeline menu carries, so
    /// neither is load-bearing on its own:
    ///
    /// - **← and →** while the timeline has focus. `onKeyPress` needs focus, so
    ///   the canvas is focusable and shows a focus ring; the menu covers the
    ///   case where it does not have focus.
    /// - **Two-finger horizontal scroll**, which is what every comparable
    ///   timeline uses and which nothing else on this page wants. Vertical
    ///   scroll passes straight through — see ``ScrollWheelPan``.
    private var canvas: some View {
        TimelineCanvas(
            events: model.visibleEvents,
            window: model.window,
            gaps: model.gaps,
            trustBoundary: model.trustBoundary,
            level: model.level,
            selected: model.selected,
            hiddenByFilter: model.hiddenInWindow,
            onSelect: { model.selected = $0 },
            onZoomTo: model.zoom(to:)
        )
        .background(
            GeometryReader { geo in
                ScrollWheelPan { deltaX in
                    // Points to seconds, through the width the canvas is
                    // actually drawn at — the only place that number is known.
                    //
                    // Negated because the gesture moves the *content*: pushing
                    // the history left with two fingers reports a negative
                    // delta and means "show me later", which is a window that
                    // starts further forward in time.
                    let seconds = -Double(deltaX) / Double(max(geo.size.width, 1)) * model.window.span
                    model.pan(bySeconds: seconds)
                }
            }
        )
        .focusable()
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            // Bare arrows only. ⌥ steps the selection and ⌘ jumps to an end of
            // the history; both are menu commands, and claiming their keys here
            // would fire two things at once.
            guard press.modifiers.isEmpty else { return .ignored }
            if press.key == .leftArrow { model.panEarlier() } else { model.panLater() }
            return .handled
        }
        .accessibilityLabel("Timeline. Left and right arrows pan through history.")
    }

    private var timelineHeader: some View {
        HStack(spacing: Metrics.space3) {
            Text("TIMELINE")
                .font(Typography.sectionKicker)
                .foregroundStyle(Palette.textTertiary)

            // Both halves derive from the same window, so they cannot disagree:
            // the level is resolved from it and the span is measured from it.
            // The contradiction this used to show — "Density · 6 d" beside a
            // footer reading "12:37 – 21:59" — was never in this chip. It was in
            // the footer, which printed clock times for a range spanning six
            // days and dropped the days. See ``TimelineWindow/label``.
            Text("\(model.level.label) · \(model.window.spanLabel)")
                .font(Typography.chip)
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Metrics.space2)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.surfaceRaised))

            // The third place the filtered state is stated, and the one attached
            // to the drawing itself. A screenshot of this timeline has to carry
            // the qualification with it — a cropped image of a quiet hour is
            // exactly how a filtered view becomes a claim about a night.
            if model.hiddenInWindow > 0 {
                HStack(spacing: Metrics.space1) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 9, weight: .bold))
                    Text("\(model.hiddenInWindow.formatted()) hidden")
                        .font(Typography.chip)
                        .monospacedDigit()
                }
                .foregroundStyle(Palette.filtered)
                .padding(.horizontal, Metrics.space2)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.filteredWash))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Palette.filteredEdge, lineWidth: Metrics.hairline))
                .accessibilityLabel(
                    "\(model.hiddenInWindow) records in this window are hidden by a filter")
            }

            // The legend, carrying both forms of the same mark. A short gap is
            // drawn as a dashed tick rather than as hatching — three points of
            // diagonal lines is a smudge — and an unexplained dashed spike
            // beside grey density bars is exactly the ambiguity this names.
            HStack(spacing: Metrics.space2) {
                HStack(spacing: Metrics.space1) {
                    CoverageGapMark(size: CGSize(width: 13, height: 10))
                    Text("no coverage")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize()
                }
                HStack(spacing: Metrics.space1) {
                    Rectangle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                        .foregroundStyle(Palette.textQuiet)
                        .frame(width: 2, height: 11)
                    Text("brief gap")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize()
                }
            }

            Spacer()

            ZoomControls(
                canZoomIn: model.canZoomIn,
                canZoomOut: model.canZoomOut,
                onZoomIn: model.zoomIn,
                onZoomOut: model.zoomOut,
                presets: Model.presets,
                activePreset: model.activePreset,
                onPreset: model.apply(preset:)
            )
        }
    }
}
