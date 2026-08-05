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

/// A span with no recording at all. Never mistakable for a quiet period, and
/// never hideable by a filter — an absence of recording is not an event.
struct CoverageGap: Equatable, Sendable {
    var start: Date
    var end: Date
    var stoppedRecord: Int
    var restartedRecord: Int

    var label: String {
        "no coverage \(start.clockText) – \(end.clockText)"
    }
}

/// Ledger trust, as the header and banner present it.
enum IntegrityState: String, CaseIterable, Identifiable, Sendable {
    case verified
    case failed
    case truncated
    case anchorOffline

    var id: String { rawValue }

    var isHealthy: Bool { self == .verified }

    var headerText: String {
        switch self {
        case .verified: "Ledger verified · #5,362"
        case .failed: "Verification failed"
        case .truncated: "History truncated"
        case .anchorOffline: "Verified · anchor paused"
        }
    }

    var symbol: String {
        isHealthy ? "checkmark.shield" : "exclamationmark.shield"
    }

    var bannerTitle: String {
        switch self {
        case .verified: ""
        case .failed: "Verification failed at record #3,201"
        case .truncated: "The local history is shorter than its iCloud anchor"
        case .anchorOffline: "Anchoring paused — iCloud Drive is signed out"
        }
    }

    var bannerBody: String {
        switch self {
        case .verified: ""
        case .failed:
            "Records #1 – #3,200 verify against the chain and remain trustworthy. Everything after #3,201 has been altered, removed, or reordered and cannot be trusted. Export a proof bundle now — it captures the verified span and the point of failure."
        case .truncated:
            "The anchor written at 14:00 covers 5,410 records; this Mac holds 5,362. 48 records have been removed from the end of the ledger. The remaining records still verify record-to-record."
        case .anchorOffline:
            "The chain still verifies record-to-record on this Mac, but the copy of the chain head kept outside it is not being updated, so a truncated history would be harder to detect. Sign in to iCloud to restore full tamper evidence."
        }
    }

    var bannerAction: String {
        self == .anchorOffline ? "Open iCloud Settings" : "Re-verify"
    }
}
