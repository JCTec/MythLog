import Foundation

/// One line of the ledger file: an event, the hash of the record before it, and
/// its own hash.
///
/// The stored shape is fixed by the hash chain. See ``AlarmEvent`` for why this
/// type may only ever gain optional fields.
struct LedgerRecord: Codable, Equatable, Sendable {
    var event: AlarmEvent
    var previousHash: String
    var hash: String

    init(event: AlarmEvent, previousHash: String, hash: String) {
        self.event = event
        self.previousHash = previousHash
        self.hash = hash
    }
}

/// A record together with where it sits in the whole chain.
///
/// # Ordinals are cumulative, not line numbers
///
/// The inspector shows `#4629 · chained to #4628`. That number must count from
/// the first record the user ever recorded, across every rotated segment — a
/// line index within the active file would restart at 1 after each rotation, so
/// two different records would both be `#1` and the "chained to" reference
/// would point at nothing.
///
/// The ordinal is derived, not stored: it is ``LedgerSegment/baseOrdinal`` plus
/// the record's position within its segment. Storing it inside the record would
/// put it in the hashed bytes, which would mean a ledger written before ordinals
/// existed could never verify again — the mistake ``AlarmEvent`` describes.
///
/// Ordinals are 1-based, because the first record a user has is `#1`.
struct LedgerEntry: Equatable, Sendable, Identifiable {
    var ordinal: Int
    var segmentIndex: Int
    var record: LedgerRecord

    var id: UUID { record.event.id }
    var event: AlarmEvent { record.event }

    /// The ordinal this record claims to be chained to. `nil` for the very first
    /// record in the ledger, which is chained to the zero hash instead.
    var previousOrdinal: Int? { ordinal > 1 ? ordinal - 1 : nil }
}

/// The result of checking a whole chain.
struct LedgerVerification: Codable, Equatable, Sendable {
    var isValid: Bool
    var recordCount: Int
    var segmentCount: Int
    var lastHash: String
    var issues: [LedgerIssue]

    /// The ordinal of the last record that verifies. Everything up to and
    /// including it is still trustworthy, which is the sentence the failure
    /// banner has to be able to say truthfully.
    var lastTrustedOrdinal: Int {
        guard let first = issues.map(\.ordinal).min() else { return recordCount }
        return max(0, first - 1)
    }

    static func empty() -> LedgerVerification {
        LedgerVerification(
            isValid: true,
            recordCount: 0,
            segmentCount: 0,
            lastHash: LedgerHashChain.zeroHash,
            issues: []
        )
    }
}

/// The result of checking one segment's *internal* chain, before the seams
/// between segments are considered.
///
/// Carries its own `index` because a `TaskGroup` yields results "in any order"
/// — the parent sorts by this to reassemble the chain.
struct SegmentVerification: Sendable {
    var index: Int
    var recordCount: Int
    /// The `previousHash` of this segment's first record — what the previous
    /// segment must have ended with.
    var firstPreviousHash: String?
    /// The hash of this segment's last record — what the next segment must
    /// start from.
    var lastHash: String?
    var issues: [LedgerIssue]
}
