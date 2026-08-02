import SwiftUI

/// Honors the system "Reduce Motion" setting.
///
/// The timeline leans on movement to explain itself: nodes spring and scale on selection and hover,
/// the canvas slides sideways when a new event arrives, and the inspector flies in from the trailing
/// edge. For someone with a vestibular disorder that is not polish, it is a reason to close the app.
///
/// Under Reduce Motion the same state changes still happen — nothing becomes unreachable, and no
/// information is lost — they just arrive instantly or as a cross-fade instead of travelling.
enum ReducedMotion {
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// Movement and scale transitions collapse to a plain fade, which is what macOS itself
    /// substitutes for its own animations under this setting.
    static func transition(_ transition: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : transition
    }

    /// Scale effects are dropped outright rather than softened: a smaller bounce is still a bounce.
    static func scale(_ scale: CGFloat, reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 1 : scale
    }
}
