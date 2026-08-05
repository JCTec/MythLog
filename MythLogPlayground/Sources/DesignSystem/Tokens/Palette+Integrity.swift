import SwiftUI

/// Colour for the integrity states, resolved here so no view declares a literal
/// and no view maps a state to a colour twice.
///
/// Severity is a *model* concept — see ``IntegrityState/Severity`` — and this is
/// the one place it becomes pigment.
extension Palette {
    static func tint(for severity: IntegrityState.Severity) -> Color {
        switch severity {
        case .calm: accent
        case .caution: warning
        case .alarm: critical
        }
    }

    /// Behind a banner or a strip. Low enough that body text over it keeps its
    /// contrast, present enough that the block reads as one object.
    static func wash(for severity: IntegrityState.Severity) -> Color {
        tint(for: severity).opacity(0.10)
    }

    static func edge(for severity: IntegrityState.Severity) -> Color {
        tint(for: severity).opacity(0.42)
    }

    /// Over the span of the timeline that cannot be trusted. Fainter than the
    /// wash because it sits under drawn content rather than under text.
    static let untrustedSpan = Color(hex: 0xE5534B).opacity(0.12)
}
