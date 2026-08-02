import MythLogCore
import SwiftUI

extension AlarmSeverity {
    var timelineColor: Color {
        switch self {
        case .debug: Color(nsColor: .secondaryLabelColor)
        case .info: Color(nsColor: .tertiaryLabelColor)
        case .notice: Color(red: 0.10, green: 0.58, blue: 0.42)
        case .warning: Color(red: 0.88, green: 0.58, blue: 0.16)
        case .critical: Color(red: 0.82, green: 0.18, blue: 0.22)
        }
    }

    /// Spoken and written form of the severity. `rawValue` is lowercase and reads poorly mid-sentence.
    var accessibilityTitle: String {
        switch self {
        case .debug: "Debug"
        case .info: "Info"
        case .notice: "Notice"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }

    /// Shape backup for the severity ring, so amber-versus-red survives grayscale displays, color
    /// filters, and color blindness.
    ///
    /// Only the two severities the design actually emphasizes get a badge. Debug, info, and notice
    /// are the quiet band — they share one flat treatment on screen by design, and a user who needs
    /// to tell them apart gets the exact word from VoiceOver and from the inspector's severity tag.
    var timelineBadgeSymbolName: String? {
        switch self {
        case .debug, .info, .notice: nil
        case .warning: "exclamationmark.circle.fill"
        case .critical: "exclamationmark.triangle.fill"
        }
    }

    /// Fill for the inspector's severity tag. `timelineColor` is tuned for a thin ring on the canvas;
    /// the two lightest values fail contrast behind the tag's white text, so they fall back to the
    /// tag's readable secondary styling.
    var timelineTagColor: Color {
        switch self {
        case .debug, .info: .secondary
        case .notice, .warning, .critical: timelineColor
        }
    }
}
