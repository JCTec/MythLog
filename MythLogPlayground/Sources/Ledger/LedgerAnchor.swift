import Foundation

/// A point-in-time record of the chain head, written somewhere the Mac itself
/// does not control.
///
/// # What it is for
///
/// The hash chain proves nobody edited a record *in place*. It cannot prove
/// nobody deleted records from the end — an attacker with the key can truncate
/// the file and the shortened chain still verifies perfectly. The anchor is the
/// answer: a copy of "at 14:00 there were 5,410 records and the head was
/// `abc…`", kept outside this Mac's trust domain. A local history shorter than
/// the anchor saw is truncation, and it is detectable precisely because the
/// evidence is not on the machine that was compromised.
struct LedgerHashAnchor: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var createdAt: Date
    var deviceID: String
    var ledgerPath: String
    var recordCount: Int
    var lastHash: String
    var isLedgerValid: Bool
    var reason: String

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        deviceID: String,
        ledgerPath: String,
        recordCount: Int,
        lastHash: String,
        isLedgerValid: Bool,
        reason: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.deviceID = deviceID
        self.ledgerPath = ledgerPath
        self.recordCount = recordCount
        self.lastHash = lastHash
        self.isLedgerValid = isLedgerValid
        self.reason = reason
    }
}

/// Compares a ledger against an anchor taken earlier.
///
/// Pure computation on two values already in memory, so it is a synchronous
/// function on a value type. Nothing here waits for anything.
struct LedgerAnchorComparison: Codable, Equatable, Sendable {
    enum Verdict: String, Codable, Equatable, Sendable {
        case matches
        /// Fewer records than the anchor saw: records were removed from the end.
        case truncated
        /// The record at the anchored position carries a different hash: the
        /// chain was rewritten.
        case rewritten
    }

    var verdict: Verdict
    var issues: [String]

    var matches: Bool { verdict == .matches }

    /// - Parameters:
    ///   - recordCount: how many records the ledger holds now.
    ///   - hashAtAnchoredPosition: the hash of record `anchor.recordCount`,
    ///     or `nil` when the ledger no longer has that many records.
    ///
    /// Takes the two facts it needs rather than an array of records, so
    /// comparing a two-year ledger does not require materialising it.
    static func compare(
        recordCount: Int,
        hashAtAnchoredPosition: String?,
        anchor: LedgerHashAnchor
    ) -> LedgerAnchorComparison {
        guard anchor.recordCount > 0 else {
            return LedgerAnchorComparison(verdict: .matches, issues: [])
        }

        if recordCount < anchor.recordCount {
            let missing = anchor.recordCount - recordCount
            return LedgerAnchorComparison(
                verdict: .truncated,
                issues: [
                    "The anchor written at \(anchor.createdAt.formatted(.iso8601)) covers "
                        + "\(anchor.recordCount) records; this Mac holds \(recordCount). "
                        + "\(missing) record(s) have been removed from the end of the ledger."
                ]
            )
        }

        guard let hashAtAnchoredPosition else {
            return LedgerAnchorComparison(
                verdict: .truncated,
                issues: ["Record #\(anchor.recordCount) is no longer present in the ledger."]
            )
        }

        guard hashAtAnchoredPosition == anchor.lastHash else {
            return LedgerAnchorComparison(
                verdict: .rewritten,
                issues: [
                    "Record #\(anchor.recordCount) does not match the hash anchored at "
                        + "\(anchor.createdAt.formatted(.iso8601)); the chain has been rewritten."
                ]
            )
        }

        return LedgerAnchorComparison(verdict: .matches, issues: [])
    }
}
