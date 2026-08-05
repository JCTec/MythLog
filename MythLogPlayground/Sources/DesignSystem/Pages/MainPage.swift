import SwiftUI

/// The template filled with mock data and wired to real interaction.
struct MainPage: View {
    @State private var model = Model()

    var body: some View {
        MainWindowTemplate {
            HeaderBar(
                edition: "App Store edition",
                integrity: model.integrity,
                recordCount: MockLedger.totalRecords,
                since: MockLedger.since,
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
                    gap: MockLedger.gap,
                    level: model.level,
                    selected: model.selected,
                    onSelect: { model.selected = $0 },
                    onZoomTo: model.zoom(to:)
                )
            }
        } list: {
            EventList(
                events: model.visibleEvents,
                window: model.window,
                gap: MockLedger.gap,
                selected: model.selected,
                newEventTime: "14:37",
                onSelect: { model.selected = $0 },
                onJumpToNew: { model.selected = model.visibleEvents.last }
            )
        } inspector: {
            InspectorPanel(event: model.selected, integrity: model.integrity)
        }
        .frame(minWidth: 1240, minHeight: 820)
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
                canZoomIn: model.window.span > TimelineWindow.minimumSpan,
                canZoomOut: model.window.span < MockLedger.limit.upperBound.timeIntervalSince(MockLedger.limit.lowerBound),
                onZoomIn: model.zoomIn,
                onZoomOut: model.zoomOut,
                presets: Model.presets,
                activePreset: model.activePreset,
                onPreset: model.apply(preset:)
            )
        }
    }
}

#Preview {
    MainPage()
}
