import Foundation

/// Everything the ledger can refuse to do.
///
/// Deliberately distinct from an *integrity issue*: an error means the ledger
/// could not be read, an issue means it was read and it does not verify. The
/// difference is the whole point — a ledger that fails verification must never
/// be presented as an empty one.
enum LedgerError: Error, Equatable, LocalizedError, Sendable {
    case emptyHMACKey
    case unreadableSegment(path: String, underlying: String)
    case malformedRecord(ordinal: Int, path: String, underlying: String)
    case lockUnavailable(path: String, afterSeconds: Double)
    case notAFile(path: String)

    var errorDescription: String? {
        switch self {
        case .emptyHMACKey:
            "The ledger HMAC key is empty; nothing can be verified without it."
        case .unreadableSegment(let path, let underlying):
            "Could not read ledger segment \(path): \(underlying)"
        case .malformedRecord(let ordinal, let path, let underlying):
            "Record #\(ordinal) in \(path) is not a decodable ledger record: \(underlying)"
        case .lockUnavailable(let path, let seconds):
            "Could not take a shared lock on \(path) within \(seconds)s; the recorder may be mid-append."
        case .notAFile(let path):
            "\(path) is not a readable file."
        }
    }
}

/// One way in which a ledger failed to verify, at a known position.
///
/// The ordinal is cumulative across segments — the same number the inspector
/// shows — so "verification failed at record #3,201" in the UI and the issue
/// here are the same record.
struct LedgerIssue: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Equatable, Sendable {
        /// The record's stored hash is not the HMAC of its own contents: the
        /// event was altered after it was written.
        case recordHashMismatch
        /// The record's `previousHash` is not the preceding record's hash: a
        /// record was removed, inserted, or reordered.
        case previousHashMismatch
        /// The first record of a segment does not continue the last record of
        /// the segment before it: a whole segment is missing or out of order.
        case segmentSeamMismatch
        /// A line could not be decoded at all: the file is truncated or corrupt.
        case undecodableRecord
    }

    var id: String { "\(kind.rawValue)@\(ordinal)" }

    var kind: Kind
    var ordinal: Int
    var detail: String

    var message: String {
        switch kind {
        case .recordHashMismatch:
            "Record #\(ordinal) has been altered — its contents no longer match its hash."
        case .previousHashMismatch:
            "Record #\(ordinal) does not follow record #\(ordinal - 1) — a record was removed, inserted, or reordered."
        case .segmentSeamMismatch:
            "The chain breaks at record #\(ordinal), where one ledger segment continues into the next."
        case .undecodableRecord:
            "Record #\(ordinal) could not be read: \(detail)"
        }
    }
}
