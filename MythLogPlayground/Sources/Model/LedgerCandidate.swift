import Foundation

/// A ledger the app could open, described well enough to choose between them.
///
/// # Found is not opened
///
/// A candidate is the result of looking, and looking is cheap: it stats a file
/// and reads a small config beside it. Nothing here reads a record. That
/// separation is the whole point — this app is used for screenshots and design
/// work, and it must be possible to launch it on somebody's Mac without their
/// personal history appearing on screen.
struct LedgerCandidate: Identifiable, Equatable, Sendable {
    /// Where this candidate came from, which is what the interface has to be
    /// able to say at all times.
    enum Origin: Equatable, Sendable {
        /// Found where an install would put it, via ``StorageLocations``.
        case installed(StorageLocations.Origin)
        /// Chosen by hand in the file picker.
        case chosen
        /// Named by `MYTHLOG_LEDGER`. Automation and the tamper tests.
        case environment
    }

    var id: String
    var origin: Origin
    var ledgerURL: URL
    /// The HMAC key, when it was found beside the ledger. `nil` means the
    /// ledger can be read but not verified, and the interface must say so.
    var hmacKey: Data?
    /// The heartbeat interval the recorder was configured with, which sets what
    /// counts as a coverage gap. See ``CoverageAnalysis``.
    var heartbeatInterval: TimeInterval
    var title: String
    var detail: String
    /// Size on disk of the whole chain, for a sense of scale before opening.
    var byteSize: Int?

    var canVerify: Bool { hmacKey != nil }

    /// A one-line description of what is loaded, for the header. Never absent:
    /// the interface must always be able to say which ledger it is showing.
    var badge: String {
        switch origin {
        case .installed: "Installed ledger"
        case .chosen: "Opened ledger"
        case .environment: "MYTHLOG_LEDGER"
        }
    }

    var loaded: LoadedLedger {
        LoadedLedger(badge: badge, title: title, path: ledgerURL.path, isRealHistory: true)
    }

    var sizeLabel: String? {
        byteSize.map { ByteCountFormatStyle(style: .file).format(Int64($0)) }
    }
}

extension LedgerCandidate {
    /// Builds the thing that reads this ledger.
    ///
    /// Lives here rather than in the view because constructing a `LedgerStore`
    /// means touching the `Ledger/` layer, which `DesignSystem/` may not do.
    /// The chooser hands back a candidate; this turns it into something to read.
    func makeSource() throws -> any TimelineSource {
        let store = try LedgerStore(
            ledgerURL: ledgerURL,
            // An unverifiable ledger is still worth reading, so a missing key is
            // not a refusal. The placeholder is never used to judge anything:
            // `loadRequest` turns verification off when there is no real key, so
            // the state stays `.unverified` rather than becoming a false
            // accusation that every record failed its HMAC.
            hmacKey: hmacKey ?? Data("no-key-present".utf8)
        )
        return LedgerTimelineSource(store: store, describedOrigin: ledgerURL.path)
    }

    var loadRequest: TimelineLoadRequest {
        TimelineLoadRequest(
            gapThreshold: HeartbeatConfig(intervalSeconds: heartbeatInterval).gapThreshold,
            verify: canVerify
        )
    }
}
