import SwiftUI

extension AgentHealthLevel {
    var tintColor: Color {
        switch self {
        case .healthy: .green
        case .warning: .orange
        case .critical: .red
        case .unknown: .secondary
        }
    }

    /// Shape backup for `tintColor`. Green, orange, and red collapse to near-identical grays under a
    /// grayscale color filter, so the recorder's health also has a distinct silhouette per level.
    var symbolName: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .critical: "exclamationmark.triangle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}
