import SwiftUI

/// The template filled with mock data and wired to real interaction.
struct MainPage: View {
    @State private var model: Model

    /// The data source is injected, never reached for. The page cannot tell a
    /// fixture from a real ledger, which is what keeps the design honest.
    init(source: any TimelineSource, request: TimelineLoadRequest = TimelineLoadRequest()) {
        _model = State(initialValue: Model(source: source, request: request))
    }

    var body: some View {
        MainWindowTemplate {
            HeaderBar(
                edition: "App Store edition",
                integrity: model.integrity,
                recordCount: model.snapshot.totalRecords,
                since: model.snapshot.since,
                query: $model.query
            )
        } filters: {
            FilterBar(
                counts: model.counts,
                enabled: model.enabledKinds,
                lockedSources: LockedSource.allCases,
                onToggle: model.toggle,
                onExplainEditions: {}
            )
        } timeline: {
            VStack(alignment: .leading, spacing: Metrics.space3) {
                timelineHeader
                TimelineCanvas(
                    events: model.visibleEvents,
                    window: model.window,
                    gaps: model.gaps,
                    trustBoundary: model.trustBoundary,
                    level: model.level,
                    selected: model.selected,
                    onSelect: { model.selected = $0 },
                    onZoomTo: model.zoom(to:)
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
                    selected: model.selected,
                    newEventTime: "14:37",
                    onSelect: { model.selected = $0 },
                    onJumpToNew: { model.selected = model.visibleEvents.last }
                )
            }
        } inspector: {
            InspectorPanel(
                event: model.selected,
                integrity: model.integrity,
                trustBoundary: model.trustBoundary
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
    }

    private var timelineHeader: some View {
        HStack(spacing: Metrics.space3) {
            Text("TIMELINE")
                .font(Typography.sectionKicker)
                .foregroundStyle(Palette.textTertiary)

            Text("\(model.level.label)·\(model.window.spanLabel)")
                .font(Typography.chip)
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Metrics.space2)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.surfaceRaised))

            HStack(spacing: Metrics.space1) {
                HatchFill(spacing: 3, lineWidth: 1)
                    .frame(width: 13, height: 10)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                Text("no coverage")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
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
