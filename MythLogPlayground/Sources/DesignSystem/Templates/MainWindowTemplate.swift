import SwiftUI

/// Pure layout. Knows where things sit and nothing about what they mean, so the
/// arrangement can be judged independently of the data.
struct MainWindowTemplate<Header: View, Filters: View, Timeline: View, List: View, Inspector: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var filters: Filters
    @ViewBuilder var timeline: Timeline
    @ViewBuilder var list: List
    @ViewBuilder var inspector: Inspector

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space3) {
            header
            filters
            timeline
                .padding(Metrics.space4)
                .panelSurface()

            HStack(alignment: .top, spacing: Metrics.space3) {
                list
                inspector
            }
            .frame(maxHeight: .infinity)
        }
        .padding(Metrics.windowPadding)
        .background(WindowBackground())
    }
}

/// Near-black with two soft glows — green top-left, blue bottom-right.
struct WindowBackground: View {
    var body: some View {
        ZStack {
            Palette.canvas
            RadialGradient(
                colors: [Palette.glowGreen.opacity(0.55), .clear],
                center: .topLeading, startRadius: 0, endRadius: 620
            )
            RadialGradient(
                colors: [Palette.glowBlue.opacity(0.45), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 560
            )
        }
        .ignoresSafeArea()
    }
}
