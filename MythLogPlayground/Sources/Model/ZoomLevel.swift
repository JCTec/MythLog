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

    /// The most events that can be drawn as individual nodes without overlapping
    /// into a smear.
    static let individualNodeLimit = 48

    /// Chosen from population first, span second.
    ///
    /// # Why population comes first
    ///
    /// The span thresholds exist for one reason: to stop a wide window with
    /// thousands of events in it from drawing thousands of overlapping nodes.
    /// They are a proxy for population, and once the population is known
    /// directly the proxy is not needed — twelve events spread across a fortnight
    /// have nothing to overlap with, and drawing them as density bars twelve
    /// pixels high throws away everything a person could have read.
    ///
    /// This matters most under a filter. "Show me only screen unlocks" over a
    /// week leaves five events, and the whole point of asking is to see them
    /// individually: a sparse row of marks is the right shape for that question.
    /// With span deciding first, that window resolved to Density and the answer
    /// arrived as five indistinguishable bars.
    ///
    /// Above the limit the span still decides, and the old reasoning stands:
    /// zooming into a burst stays clustered rather than exploding into overlap.
    static func resolve(window: TimelineWindow, visibleCount: Int) -> ZoomLevel {
        if visibleCount <= individualNodeLimit { return .events }
        return window.span / 60 > 720 ? .density : .clusters
    }
}
