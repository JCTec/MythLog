import Foundation

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

    /// How loudly this state asks to be noticed.
    ///
    /// Named rather than expressed as a colour, because the view layer owns
    /// colour and because **colour cannot be the only carrier**. Every severity
    /// here also gets its own symbol and its own shape treatment, so the
    /// interface still reads in greyscale, in bright sunlight, and to the
    /// roughly one man in twelve who cannot separate the amber from the red.
    enum Severity: Equatable, Sendable, Comparable {
        /// Nothing is wrong, or nothing is known yet.
        case calm
        /// Trust is reduced but the history is intact.
        case caution
        /// Part of the history cannot be trusted, or none of it can be read.
        case alarm

        private var rank: Int {
            switch self {
            case .calm: 0
            case .caution: 1
            case .alarm: 2
            }
        }

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }
    }

    var severity: Severity {
        switch self {
        case .verified, .unverified: .calm
        case .anchorOffline: .caution
        // Truncation is an alarm, not a caution: records were removed from the
        // end and the chain cannot see it. That is the attack the anchor exists
        // to catch, so the one time it fires it must not read as a nuisance.
        case .truncated, .failed, .unreadable: .alarm
        }
    }

    /// A distinct symbol per state, not per severity.
    ///
    /// Two states that share a colour must not share a glyph, or the only thing
    /// telling them apart is the sentence — and the sentence is the part people
    /// skip.
    var symbol: String {
        switch self {
        case .unverified: "clock.badge.questionmark"
        case .verified: "checkmark.shield"
        case .failed: "exclamationmark.shield"
        case .truncated: "scissors"
        case .anchorOffline: "icloud.slash"
        case .unreadable: "questionmark.folder"
        }
    }

    /// Whether this state warrants the banner above the event list.
    ///
    /// `.unverified` deliberately does not. It is the state during loading, and
    /// a banner that appears and vanishes on every launch teaches people to
    /// dismiss banners — which is the last habit this app wants to build. The
    /// header badge says "Verifying…" and that is enough.
    var needsBanner: Bool {
        switch self {
        case .verified, .unverified: false
        case .failed, .truncated, .anchorOffline, .unreadable: true
        }
    }

    /// The last record that still verifies, when part of the history does not.
    ///
    /// `nil` means the question does not apply — either everything verifies or
    /// nothing has been checked. `0` means nothing verifies, which is a
    /// different statement from "not applicable" and must stay distinguishable.
    var lastTrustedOrdinal: Int? {
        switch self {
        case .failed(let lastTrusted, _, _): lastTrusted
        case .unreadable: 0
        // Truncation removes records from the *end*: everything still present
        // verifies, so there is no boundary inside what is on screen.
        case .verified, .unverified, .truncated, .anchorOffline: nil
        }
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

    /// The second thing worth offering, where there is one.
    ///
    /// Only on the states where evidence is at stake. Exporting a proof bundle
    /// while a ledger is failing captures the verified span *and* the point of
    /// failure — and the longer someone waits, the more likely whatever damaged
    /// the ledger damages it further.
    var bannerSecondaryAction: String? {
        switch self {
        case .failed, .truncated: "Export proof bundle"
        case .verified, .unverified, .anchorOffline, .unreadable: nil
        }
    }

    /// What the banner is telling you, in one line, for VoiceOver and for the
    /// person who reads exactly one sentence.
    var accessibilitySummary: String {
        bannerTitle.isEmpty ? headerText : "\(bannerTitle). \(bannerBody)"
    }
}
