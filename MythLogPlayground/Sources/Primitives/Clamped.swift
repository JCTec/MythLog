import Foundation

/// Confines a value to a range at the point of assignment, so out-of-range is
/// not a state the type can be in.
///
/// # Why this earns its place
///
/// The alternative is a validating initialiser plus a `mutating` setter that
/// re-validates, plus the discipline to remember both. That is three places to
/// keep in agreement and one of them is a habit. The failure mode is specific
/// and this project has it: a timeline window whose span went below
/// ``TimelineWindow/minimumSpan`` divides by a number close to zero when mapping
/// dates to x-positions, and the canvas draws events at ±10^6 points. The bug
/// does not look like "a bad span"; it looks like the timeline exploding.
///
/// With `@Clamped` the span is a stored property that *cannot* hold an invalid
/// value, whatever arithmetic produced the assignment. There is no validation
/// step to forget because there is no window between assignment and validity.
///
/// # Why not just clamp at the call site
///
/// Because there are six call sites — zoom in, zoom out, reset, click-to-zoom,
/// each range preset, and the initial window — and they are in three files. The
/// wrapper moves the invariant next to the data it constrains.
///
/// # What it deliberately does not do
///
/// It does not report that clamping happened. A window asked to zoom past the
/// end of history should silently stop at the end of history; that is the
/// correct interaction, not an error. A wrapper that threw, or that exposed a
/// `didClamp` flag callers had to check, would be a validator wearing a
/// wrapper's clothes.
///
/// Bounds are carried per instance rather than as a generic parameter because
/// the upper bound is the length of the user's recorded history, which is only
/// known at runtime.
@propertyWrapper
struct Clamped<Value: Comparable> {
    private var storage: Value

    /// The permitted range. Exposed through `$` so a view can ask "can I still
    /// zoom out?" without duplicating the bound.
    let bounds: ClosedRange<Value>

    init(wrappedValue: Value, _ bounds: ClosedRange<Value>) {
        self.bounds = bounds
        self.storage = Self.clamp(wrappedValue, to: bounds)
    }

    var wrappedValue: Value {
        get { storage }
        set { storage = Self.clamp(newValue, to: bounds) }
    }

    var projectedValue: ClosedRange<Value> { bounds }

    /// True when the value sits hard against a bound — the honest answer to
    /// "is the zoom-out button still meaningful?".
    var isAtLowerBound: Bool { storage <= bounds.lowerBound }
    var isAtUpperBound: Bool { storage >= bounds.upperBound }

    private static func clamp(_ value: Value, to bounds: ClosedRange<Value>) -> Value {
        min(max(value, bounds.lowerBound), bounds.upperBound)
    }
}

/// Two clamped values are equal when they hold the same value under the same
/// bounds. Comparing the value alone would make windows over different
/// histories compare equal, and the window drives cache keys.
extension Clamped: Equatable where Value: Equatable {}

/// `Sendable` when the value is, by the ordinary value-type rule: the wrapper
/// stores only `Value` and a `ClosedRange<Value>`.
extension Clamped: Sendable where Value: Sendable {}
