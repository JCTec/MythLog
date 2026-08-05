import Foundation

/// How the timeline draws itself at the current window.
///
/// The timeline never disappears — it changes what it is made of. One component
/// with three renderers, never three components: selection, the window, and the
/// coverage-gap overlay must behave identically at every level.
enum ZoomLevel: String, Sendable {
    case density
    case clusters
    case events

    var label: String {
        switch self {
        case .density: "Density"
        case .clusters: "Clusters"
        case .events: "Events"
        }
    }

    /// Chosen from span *and* population: zooming into a burst stays clustered
    /// rather than exploding into overlapping nodes.
    static func resolve(window: TimelineWindow, visibleCount: Int) -> ZoomLevel {
        let minutes = window.span / 60
        if minutes > 720 { return .density }
        if minutes > 90 { return .clusters }
        return visibleCount <= 48 ? .events : .clusters
    }
}
