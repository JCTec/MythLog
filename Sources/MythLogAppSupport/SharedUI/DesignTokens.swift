import SwiftUI

/// Layout spacing — the gaps *between* separate elements.
///
/// Deliberately fixed. Dynamic Type exists to make text bigger; if the gaps between elements grew at
/// the same rate, a window whose text already needs more room would spend that room on whitespace
/// instead. Nothing clips when these stay put.
///
/// For the space *inside* a control — between a label and its own background — use `ScaledSpacing`,
/// which does grow, because that padding is what stops text colliding with its own border.
enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
}

enum AppRadius {
    static let control: CGFloat = 8
    static let card: CGFloat = 8
}

/// Padding *inside* a control, which has to grow with the text it wraps.
///
/// `@ScaledMetric` cannot live on a `static` — it is a `DynamicProperty`, and SwiftUI only refreshes
/// those when they are stored on a view. Declaring this type as a `DynamicProperty` instead lets
/// SwiftUI walk into it and update the metrics inside, so a view gets scaling from one property:
///
/// ```swift
/// struct Badge: View {
///     private var space = ScaledSpacing()
///     var body: some View {
///         Text("…").padding(.horizontal, space.sm)
///     }
/// }
/// ```
///
/// The rungs are the 8-based design scale and should be preferred in new code. The `fixed(_:)`
/// escape hatch scales an arbitrary value for the controls whose padding was hand-tuned off the
/// scale (7, 9, 10, …) — those keep their exact appearance at the default text size and are left for
/// a deliberate design pass rather than being snapped here.
struct ScaledSpacing: DynamicProperty {
    @ScaledMetric(relativeTo: .body) var xs: CGFloat = 4
    @ScaledMetric(relativeTo: .body) var sm: CGFloat = 8
    @ScaledMetric(relativeTo: .body) var md: CGFloat = 16
    @ScaledMetric(relativeTo: .body) var lg: CGFloat = 32

    /// Ratio against the design scale, used to scale off-scale values without changing them at the
    /// default text size. `sm` is 8 by declaration, so `sm / 8` is 1 at default settings.
    private var ratio: CGFloat { sm / 8 }

    func fixed(_ value: CGFloat) -> CGFloat {
        value * ratio
    }
}
