import AppKit
import SwiftUI

/// Two-finger horizontal scroll over the timeline, as a pan.
///
/// # Why this is AppKit
///
/// SwiftUI has no scroll-wheel event on macOS 14. The only SwiftUI answer is a
/// `ScrollView`, and a `ScrollView` is the wrong shape entirely: it needs
/// content as wide as the thing being scrolled, which for a two-year history at
/// the Events level is millions of points of view nobody can render. The window
/// is what moves, not the content — see ``TimelineWindow/panned(by:)``.
///
/// # Why a local event monitor and not `scrollWheel(with:)`
///
/// AppKit routes a scroll event to the view `hitTest` returns. An overlay that
/// answers that hit test also swallows every click underneath it, which would
/// take out click-a-bar-to-zoom and click-a-node-to-select — the two things the
/// canvas is for. Answering `nil` keeps the clicks but gives up the scrolls
/// with them.
///
/// So this view answers `nil` to every hit test and takes no clicks at all,
/// and a local monitor — which sees events before they are dispatched, hit test
/// or no hit test — handles scrolling. The view's own `bounds` decide whether a
/// given scroll belongs to the timeline, so there is no coordinate arithmetic
/// between SwiftUI and AppKit to get wrong.
///
/// # What it does and does not consume
///
/// - **Horizontal** (`|dx| > |dy|`): consumed, and reported in points.
/// - **Vertical**: passed on, so the page scrolls normally over the canvas. A
///   canvas that ate vertical scroll would make the whole window feel broken.
/// - **`⌃` or `⌘` held**: passed on, whatever the direction. That combination is
///   reserved for zoom (`ZoomControls` advertises pinch, which arrives as
///   `⌃`-scroll magnification); claiming it here would take the axis away from
///   the gesture that is meant to have it.
///
/// Never the only way in: ← and → pan by keyboard and the Timeline menu carries
/// ⌘← and ⌘→. A gesture is an accelerator — it is not keyboard-reachable and not
/// operable under VoiceOver, and this app promises both.
struct ScrollWheelPan: NSViewRepresentable {
    /// Horizontal distance in points. Positive means the content should move
    /// later in time, matching the direction the fingers pushed it.
    var onPan: (CGFloat) -> Void

    func makeNSView(context: Context) -> Catcher {
        let view = Catcher()
        view.onPan = onPan
        return view
    }

    func updateNSView(_ view: Catcher, context: Context) {
        view.onPan = onPan
    }

    /// The monitor's teardown hook.
    ///
    /// `deinit` cannot do this: it is nonisolated, and the monitor token is a
    /// non-`Sendable` `Any?` belonging to a `@MainActor` view, so reaching it
    /// from `deinit` is a data race the compiler refuses. This is the hook
    /// SwiftUI provides for the purpose, and it runs on the main actor.
    static func dismantleNSView(_ view: Catcher, coordinator: ()) {
        view.stopMonitoring()
    }

    /// An invisible view that owns a rectangle and a monitor, and nothing else.
    final class Catcher: NSView {
        var onPan: ((CGFloat) -> Void)?
        private var monitor: Any?

        /// Line-based scrolling — a mouse wheel rather than a trackpad — reports
        /// whole lines. Sixteen points is AppKit's usual line, and it keeps a
        /// notched wheel moving the timeline by a visible amount per notch.
        private static let pointsPerLine: CGFloat = 16

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window == nil ? stopMonitoring() : startMonitoring()
        }

        private func startMonitoring() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// Returns `nil` to consume the event, or the event to let it travel on
        /// to whatever would have received it.
        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window else { return event }
            guard event.modifierFlags.intersection([.control, .command]).isEmpty else { return event }

            let local = convert(event.locationInWindow, from: nil)
            guard bounds.contains(local) else { return event }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            guard abs(dx) > abs(dy) else { return event }

            onPan?(event.hasPreciseScrollingDeltas ? dx : dx * Self.pointsPerLine)
            return nil
        }
    }
}
