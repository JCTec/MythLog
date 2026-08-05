import CryptoKit
import Foundation

/// The chain arithmetic, and nothing else.
///
/// Every function here is pure and synchronous. Hashing 32 bytes is nanoseconds
/// of in-memory computation; making it `async` would add a suspension point that
/// buys nothing and costs the reader a question ("what is this waiting for?").
/// The asynchrony in this layer belongs to the file I/O around it, not to this.
enum LedgerHashChain {
    /// What the first record's `previousHash` must be. 64 hex characters, the
    /// width of a SHA-256 digest.
    static let zeroHash = String(repeating: "0", count: 64)

    /// The bytes that are actually authenticated: the event, plus the hash of
    /// the record before it. The record's own hash is obviously not included.
    ///
    /// This is a private nested type on purpose — it is the wire format of the
    /// hash input, and nothing outside this file should be able to construct
    /// something that looks like one.
    private struct HashInput: Encodable {
        var event: AlarmEvent
        var previousHash: String
    }

    /// HMAC-SHA256 of the canonical JSON of `(event, previousHash)`.
    ///
    /// HMAC rather than a plain digest because the chain has to resist an
    /// attacker who can write the file: with a bare SHA-256 anyone could delete
    /// a record and recompute every hash after it. With a key they cannot,
    /// unless they also have the key.
    static func hash(event: AlarmEvent, previousHash: String, key: SymmetricKey) throws -> String {
        let data = try CanonicalJSON.encode(HashInput(event: event, previousHash: previousHash))
        return Data(HMAC<SHA256>.authenticationCode(for: data, using: key)).hexEncodedString
    }

    static func symmetricKey(from data: Data) throws -> SymmetricKey {
        guard !data.isEmpty else { throw LedgerError.emptyHMACKey }
        return SymmetricKey(data: data)
    }

    /// Checks one record against the hash it should have and the record before
    /// it, returning every way in which it disagrees.
    ///
    /// Both checks run — a record can be both altered *and* out of order, and
    /// reporting only the first would understate the damage.
    static func issues(
        for record: LedgerRecord,
        ordinal: Int,
        expectedPreviousHash: String?,
        key: SymmetricKey
    ) throws -> [LedgerIssue] {
        var issues = [LedgerIssue]()

        if let expectedPreviousHash, record.previousHash != expectedPreviousHash {
            issues.append(
                LedgerIssue(
                    kind: .previousHashMismatch,
                    ordinal: ordinal,
                    detail: "expected \(expectedPreviousHash), found \(record.previousHash)"
                ))
        }

        let recomputed = try hash(event: record.event, previousHash: record.previousHash, key: key)
        if record.hash != recomputed {
            issues.append(
                LedgerIssue(
                    kind: .recordHashMismatch,
                    ordinal: ordinal,
                    detail: "expected \(recomputed), found \(record.hash)"
                ))
        }

        return issues
    }
}
