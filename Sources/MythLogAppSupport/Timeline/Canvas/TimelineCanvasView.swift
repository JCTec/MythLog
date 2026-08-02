import SwiftUI

struct TimelineCanvasView: View {
    let records: [TimelineDisplayRecord]
    let zoom: Double
    let selectedID: TimelineRecord.ID?
    let searchText: String
    let select: (TimelineRecord) -> Void
    @State private var layoutState = TimelineCanvasLayoutState.empty
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let request = TimelineLayoutRequest(
                records: records,
                viewportWidth: geometry.size.width,
                viewportHeight: geometry.size.height,
                zoom: zoom
            )
            let signature = request.signature
            let activeLayout = layoutState.activeLayout(for: request, signature: signature)

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    TimelineCanvasContent(
                        layout: activeLayout,
                        records: records,
                        selectedID: selectedID,
                        select: select
                    )
                }
                .onChange(of: records.last?.id) { _, newValue in
                    guard let newValue, searchText.isEmpty else { return }
                    // The canvas slides sideways on its own whenever a new event lands. Under Reduce
                    // Motion it jumps instead, which keeps the newest event in view without the
                    // unprompted travel.
                    withAnimation(ReducedMotion.animation(.easeOut(duration: 0.35), reduceMotion: reduceMotion)) {
                        proxy.scrollTo(newValue, anchor: .trailing)
                    }
                }
            }
            .task(id: signature) {
                let result = await MythLogBackgroundTask.value(priority: .userInitiated) {
                    TimelineLayoutEngine().layoutIfNotCancelled(request: request)
                }

                guard let result, !Task.isCancelled else {
                    return
                }
                layoutState.apply(result)
            }
        }
        .overlay {
            if records.isEmpty {
                EmptyTimelineState()
            }
        }
        .overlay(alignment: .trailing) {
            LiveEdge()
        }
    }
}
