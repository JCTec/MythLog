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

/// Ledger trust, as the header and banner present it.
///
/// # Every string here is now derived from a real verification
///
/// These used to be hard-coded sentences with invented record numbers — "#5,362",
/// "record #3,201" — because there was no ledger to ask. Now the case carries
/// what the ledger actually said, so the banner cannot claim a span verified
/// when it did not.
enum IntegrityState: Equatable, Sendable, Identifiable {
    /// Not checked yet. Deliberately distinct from `.verified`: an unverified
    /// ledger is not a verified one, and defaulting to the reassuring answer is
    /// how a viewer ends up lying.
    case unverified
    case verified(recordCount: Int)
    /// Verification found altered, removed, or reordered records.
    /// `lastTrustedOrdinal` is the last record that still verifies.
    case failed(lastTrustedOrdinal: Int, issueCount: Int, recordCount: Int)
    /// The local history is shorter than the anchor saw.
    case truncated(localRecords: Int, anchoredRecords: Int)
    /// The chain verifies, but the anchor is not being updated.
    case anchorOffline(recordCount: Int)
    /// The ledger could not be read at all — which is not the same as its being
    /// empty, and must never be shown as if it were.
    case unreadable(reason: String)

    var id: String { headerText }

    var isHealthy: Bool {
        switch self {
        case .verified: true
        case .unverified, .failed, .truncated, .anchorOffline, .unreadable: false
        }
    }

    var headerText: String {
        switch self {
        case .unverified: "Verifying…"
        case .verified(let count): "Ledger verified · #\(count.formatted())"
        case .failed: "Verification failed"
        case .truncated: "History truncated"
        case .anchorOffline: "Verified · anchor paused"
        case .unreadable: "Ledger unreadable"
        }
    }

    var symbol: String {
        isHealthy ? "checkmark.shield" : "exclamationmark.shield"
    }

    var bannerTitle: String {
        switch self {
        case .unverified, .verified: ""
        case .failed(let lastTrusted, _, _): "Verification failed at record #\((lastTrusted + 1).formatted())"
        case .truncated: "The local history is shorter than its anchor"
        case .anchorOffline: "Anchoring paused — the anchor location is unavailable"
        case .unreadable: "The ledger could not be read"
        }
    }

    var bannerBody: String {
        switch self {
        case .unverified, .verified:
            return ""
        case .failed(let lastTrusted, let issues, _):
            let trusted =
                lastTrusted > 0
                ? "Records #1 – #\(lastTrusted.formatted()) verify against the chain and remain trustworthy. "
                : "No record verifies against the chain. "
            return trusted
                + "\(issues.formatted()) record(s) from #\((lastTrusted + 1).formatted()) onwards have been "
                + "altered, removed, or reordered and cannot be trusted. Export a proof bundle now — it "
                + "captures the verified span and the point of failure."
        case .truncated(let local, let anchored):
            return "The anchor covers \(anchored.formatted()) records; this Mac holds \(local.formatted()). "
                + "\((anchored - local).formatted()) record(s) have been removed from the end of the ledger. "
                + "The remaining records still verify record to record."
        case .anchorOffline:
            return "The chain still verifies record to record on this Mac, but the copy of the chain head kept "
                + "outside it is not being updated, so a truncated history would be harder to detect."
        case .unreadable(let reason):
            return "\(reason)\n\nThis is not an empty history — it is a history that could not be read. "
                + "Nothing here should be taken as evidence that nothing happened."
        }
    }

    var bannerAction: String {
        switch self {
        case .anchorOffline: "Open iCloud Settings"
        default: "Re-verify"
        }
    }
}
