import SwiftUI

/// Colour for the filtered state and for record severity.
///
/// # Why filtering is amber and not accent-green
///
/// Every other persistent band in this app is either calm (green, "verified") or
/// wrong (red, "this cannot be trusted"). A filter is neither: nothing is broken,
/// and the user is nonetheless being shown less than the truth. Amber is the
/// colour this design system already uses for "trust is reduced but the history
/// is intact" — see ``IntegrityState/Severity/caution`` — and that is exactly the
/// claim.
///
/// Green would have been wrong in the way that matters. A filtered timeline
/// dressed in the same colour as a verified one is the interface agreeing that
/// everything is fine, which is the failure the whole feature exists to prevent.
///
/// And colour is never the only carrier: the band has a rule down its left edge,
/// an icon, a number, and a sentence. It reads in greyscale.
extension Palette {
    /// Filtering is active.
    static let filtered = warning
    static let filteredWash = warning.opacity(0.13)
    static let filteredEdge = warning.opacity(0.45)

    /// A restored filter — louder still, because nobody chose it this session.
    static let restoredWash = critical.opacity(0.13)
    static let restoredEdge = critical.opacity(0.5)

    /// A value the user ticked in, and one they subtracted. Two directions of
    /// the same control, so they must not share a colour.
    static let facetIncluded = accent
    static let facetIncludedWash = accent.opacity(0.16)
    static let facetExcluded = critical
    static let facetExcludedWash = critical.opacity(0.16)

    /// Record severity, which is a ``Primitives`` concept and becomes pigment
    /// only here.
    ///
    /// Debug and info are deliberately not coloured: most of a ledger is info,
    /// and tinting the ordinary case leaves nothing for the unusual one.
    static func tint(for severity: AlarmSeverity) -> Color {
        switch severity {
        case .debug: textQuiet
        case .info: textSecondary
        case .notice: accent
        case .warning: warning
        case .critical: critical
        }
    }
}
