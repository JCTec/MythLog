import SwiftUI

/// Where the visible window sits inside the whole history, and whether it is at
/// the live edge.
///
/// # Why this exists now and did not before
///
/// Without panning, the window could only be where zoom had put it, and zoom
/// keeps the centre — so "where am I?" had a short answer the user already knew.
/// Panning makes it possible to be genuinely lost: eleven days of history, a
/// four-hour window, and no way to tell whether you are looking at Tuesday
/// morning or a fortnight ago except by reading the clock labels and doing
/// arithmetic. This answers it as a picture, which is what a position is.
///
/// It also carries the live state, because that is a position too — the one at
/// the right-hand end — and "I am watching now" versus "I am reading history"
/// is a distinction the interface must not leave to inference. New records
/// arrive at the live edge; a user parked in March needs to know that is why
/// nothing is moving.
///
/// # Draggable, deliberately
///
/// A track with a filled segment looks like a scrollbar, and a control that
/// looks draggable and is not is a small lie that costs a user one confused
/// attempt each time. So it drags. It is coarse by construction — over a
/// two-year history one point is about a day — and that is why it is an
/// *addition* to the keyboard and the presets rather than the way to move
/// anywhere in particular.
struct HistoryPositionBar: View {
    var window: TimelineWindow
    var isLive: Bool
    /// A drag, reported as the fraction of the history where the window should
    /// start.
    var onScrub: (Double) -> Void
    var onJumpToNow: () -> Void

    /// Where inside the thumb the drag started, as a fraction of the track.
    ///
    /// Without it, grabbing the middle of the thumb snaps its left edge to the
    /// pointer — the window jumps by half its own width before it starts
    /// following, which reads as a bug rather than as a control.
    @State private var grabOffset: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space2) {
            HStack(spacing: Metrics.space2) {
                liveState
                Spacer(minLength: 0)
                // A pan affordance is invisible otherwise, exactly as the pinch
                // affordance is — and for the same reason it is spelled out
                // beside the zoom controls.
                // Lifted off `textQuiet`. Keyboard hints are the only discovery
                // route for people who cannot use the gestures, so they are the
                // last text in the app that should be set at the dimmest step on
                // the scale — a hint nobody can read is decoration.
                Text("← → pan · two-finger scroll · ⌘← ⌘→ ends")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
                Text(rangeLabel)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .monospacedDigit()
            }
            track
        }
        .accessibilityElement(children: .contain)
    }

    private var liveState: some View {
        HStack(spacing: Metrics.space2) {
            Circle()
                .fill(isLive ? Palette.accent : Palette.textQuiet)
                .frame(width: 6, height: 6)
            Text(isLive ? "Live — new records arrive here" : "Reading history")
                .font(Typography.hint)
                .foregroundStyle(isLive ? Palette.accent : Palette.textTertiary)

            if !isLive {
                Button(action: onJumpToNow) {
                    Text("Jump to now  ⌘→")
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Jump to now, and follow new records again")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var track: some View {
        GeometryReader { geo in
            let position = window.positionInHistory
            let x = position.lowerBound * geo.size.width
            // A window narrower than the whole history can still be a sliver of
            // it — a ten-minute window over two years is a thousandth of a
            // point. It is shown at a minimum width rather than not at all: the
            // point of the bar is to say where you are, and nowhere is not an
            // answer.
            let w = max(Metrics.historyBarMinimumThumb, (position.upperBound - position.lowerBound) * geo.size.width)

            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surfaceSunken)

                // # The thumb is never green
                //
                // It used to fill with the accent whenever the window was live —
                // and a window showing the whole history is live *and* full
                // width, so the commonest state in the app was a saturated green
                // bar spanning the window. That is a progress bar. It reads as
                // "83% complete", or as a loading state, and it says nothing
                // about position because it is always full.
                //
                // Position is a neutral fact and gets a neutral colour. Liveness
                // is not a span at all — it is the single point where new
                // records arrive — so it is drawn as a point, below.
                Capsule()
                    .fill(Palette.textQuiet.opacity(0.75))
                    .frame(width: min(w, geo.size.width))
                    .offset(x: min(x, geo.size.width - min(w, geo.size.width)))

                liveEdge(width: geo.size.width)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let width = max(1, geo.size.width)
                        let grabbed = value.startLocation.x / width
                        // Grabbing the thumb keeps the point you grabbed under
                        // the pointer; grabbing the empty track jumps the
                        // window's start to it, which is what a click on a
                        // scrollbar's track means everywhere else.
                        let offset =
                            grabOffset
                            ?? (position.contains(grabbed) ? grabbed - position.lowerBound : 0)
                        if grabOffset == nil { grabOffset = offset }
                        onScrub(value.location.x / width - offset)
                    }
                    .onEnded { _ in grabOffset = nil }
            )
        }
        .frame(height: Metrics.historyBarHeight)
        .accessibilityLabel("Position in history")
        .accessibilityValue(rangeLabel)
    }

    /// The live edge: a tick and a dot at the right-hand end of the track.
    ///
    /// It is there whether or not the window is at it — that is the point. The
    /// mark says "new records arrive here"; the thumb's distance from it says
    /// how far back you are reading. Lighting the mark up only when you happen to
    /// be parked on it would remove the reference exactly when it is needed.
    private func liveEdge(width: CGFloat) -> some View {
        Circle()
            .fill(isLive ? Palette.accent : Palette.textQuiet)
            .frame(width: Metrics.historyBarHeight + 2, height: Metrics.historyBarHeight + 2)
            .overlay(
                Rectangle()
                    .fill(isLive ? Palette.accent : Palette.textQuiet)
                    .frame(width: Metrics.hairline, height: Metrics.historyBarHeight + 8)
            )
            .offset(x: width - (Metrics.historyBarHeight + 2) / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Where the window sits, qualified by the history it sits in — unless it
    /// *is* the history, in which case qualifying it with itself says nothing.
    private var rangeLabel: String {
        guard !window.showsWholeHistory else { return window.label }
        let whole = RangeLabel.text(
            from: window.history.lowerBound, to: window.history.upperBound)
        return "\(window.label) of \(whole)"
    }
}

#Preview("History position") {
    let history = Date(timeIntervalSince1970: 1_770_000_000)...Date(timeIntervalSince1970: 1_770_864_000)
    return VStack(alignment: .leading, spacing: Metrics.space6) {
        HistoryPositionBar(
            window: TimelineWindow(history: history, mostRecent: 4 * 3600),
            isLive: true, onScrub: { _ in }, onJumpToNow: {}
        )
        HistoryPositionBar(
            window: TimelineWindow(
                history: history,
                centredOn: history.lowerBound.addingTimeInterval(3 * 3600),
                span: 4 * 3600),
            isLive: false, onScrub: { _ in }, onJumpToNow: {}
        )
        HistoryPositionBar(
            window: TimelineWindow(showingAllOf: history),
            isLive: true, onScrub: { _ in }, onJumpToNow: {}
        )
    }
    .padding(Metrics.space6)
    .frame(width: 720)
    .background(Palette.canvas)
    .preferredColorScheme(.dark)
}
