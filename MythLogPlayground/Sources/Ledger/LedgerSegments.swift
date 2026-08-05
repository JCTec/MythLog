import Foundation

/// One file in the chain: either an archived rotation segment or the active
/// ledger.
///
/// `baseOrdinal` is the number of records in every segment before this one, so
/// the *n*-th record of this segment (0-based) has cumulative ordinal
/// `baseOrdinal + n + 1`.
struct LedgerSegment: Equatable, Sendable, Identifiable {
    var index: Int
    var url: URL
    var isActive: Bool
    var baseOrdinal: Int

    var id: URL { url }

    func ordinal(offsetInSegment offset: Int) -> Int {
        baseOrdinal + offset + 1
    }
}

/// The whole chain, in order, with ordinals already resolved.
struct LedgerChain: Equatable, Sendable {
    var segments: [LedgerSegment]

    /// Records in every segment except the active one. The active segment's
    /// count is deliberately absent: it changes under us, so anything that needs
    /// it must count it now rather than trust a stored number.
    var rotatedRecordCount: Int {
        segments.last?.baseOrdinal ?? 0
    }

    static let empty = LedgerChain(segments: [])
}

/// The naming convention the shipping recorder rotates into, reproduced exactly
/// so a ledger it wrote is discovered here without migration.
///
/// `events.jsonl` rotates to `events-rotated-<UTC stamp>-<counter>.jsonl`, and
/// lexical order of those names is chain order because the stamp is fixed-width
/// and big-endian.
enum LedgerSegmentNaming {
    static func rotatedPrefix(for activeURL: URL) -> String {
        activeURL.deletingPathExtension().lastPathComponent + "-rotated-"
    }

    static func rotatedSuffix(for activeURL: URL) -> String {
        activeURL.pathExtension.isEmpty ? "" : ".\(activeURL.pathExtension)"
    }

    /// Sidecar holding a rotated segment's record count. See
    /// ``SegmentRecordCounter`` for why it lives beside the segment.
    static func countSidecar(for segmentURL: URL) -> URL {
        segmentURL.appendingPathExtension("ordinals.json")
    }

    static func isCountSidecar(_ url: URL) -> Bool {
        url.lastPathComponent.hasSuffix(".ordinals.json")
    }

    /// Rotated segments in chain order. Never includes the active file, and
    /// never includes sidecars.
    static func rotatedSegmentURLs(for activeURL: URL, fileManager: FileManager) throws -> [URL] {
        let parent = activeURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: parent.path) else { return [] }

        let prefix = rotatedPrefix(for: activeURL)
        let suffix = rotatedSuffix(for: activeURL)

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
        } catch {
            throw LedgerError.unreadableSegment(path: parent.path, underlying: String(describing: error))
        }

        return
            contents
            .filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix(prefix) && name.hasSuffix(suffix) && !isCountSidecar(url)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

/// A rotated segment's record count, computed once and remembered.
struct SegmentCountRecord: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var recordCount: Int
    /// Fingerprint of the file the count was taken from. A rotated segment is
    /// supposed to be immutable, so a change here means the file was replaced —
    /// and a cache that trusted the old count would report wrong ordinals for
    /// every record after it.
    var byteSize: Int
    var modifiedAt: Date
}

/// Counts records per segment, once per segment.
///
/// # Why this exists
///
/// Cumulative ordinals need the record count of every segment that precedes the
/// one being read. Recomputing those on every load means re-reading two years of
/// history to display the last hour — which is precisely the cost streaming was
/// introduced to avoid.
///
/// # Why the cache lives beside the segment
///
/// A rotated segment never changes again. Its count is a permanent property of
/// that file, so it is stored as a sidecar next to it
/// (`events-rotated-…​.jsonl.ordinals.json`) and survives relaunches. The
/// sidecar is validated against the segment's size and modification date on
/// every read: it is a cache, never a source of truth, and a mismatch silently
/// recomputes rather than trusting the stored number.
///
/// The sidecar's extension keeps it out of ``LedgerSegmentNaming/rotatedSegmentURLs(for:fileManager:)``,
/// and out of the shipping recorder's equivalent scan, which filters on the same
/// `.jsonl` suffix. Writing it is best-effort — a read-only volume or a
/// container the viewer cannot write degrades to the in-memory cache, which is
/// still correct, just per-launch.
///
/// # Why this is a namespace of `static` functions and a plain cache
///
/// The obvious shape is a `final class SegmentRecordCounter` holding both the
/// cache and a `FileManager`. Swift 6 rejects it, correctly: `FileManager` is
/// not `Sendable`, so an instance of that class is not `Sendable` either, and
/// calling an `async` method on it from inside ``LedgerStore`` would send the
/// counter out of the actor's isolation domain for the duration of the call.
/// The diagnostic — "sending 'self.counter' risks causing data races" — is not a
/// false positive: the file I/O really does suspend, and the actor really could
/// service another request against the same cache meanwhile.
///
/// The fix is to stop having an object that spans the boundary. The cache is a
/// value (``SegmentCountCache``) stored directly on the actor, so mutating it is
/// actor-isolated by construction; the I/O is `static` and takes only `Sendable`
/// arguments, so it can suspend without carrying anything across.
enum SegmentRecordCounting {
    /// Read in 1 MiB slices. Large enough that syscall overhead disappears,
    /// small enough that a segment of any size never materialises in memory.
    static let chunkBytes = 1 << 20
    static let schemaVersion = 1

    struct Fingerprint: Equatable, Sendable {
        var byteSize: Int
        var modifiedAt: Date
    }

    // MARK: - Counting

    /// Counts non-empty lines without decoding any JSON.
    ///
    /// The ledger is JSONL and `JSONEncoder` emits no newlines outside strings
    /// when it is not pretty-printing, so a newline byte is a record boundary
    /// and nothing else. Counting bytes is roughly two orders of magnitude
    /// cheaper than decoding, and this runs over the entire history the first
    /// time a segment is seen.
    ///
    /// A final line with no trailing newline still counts, because a truncated
    /// record is a record that must be reached, decoded, and reported as
    /// corrupt — not one that quietly does not exist.
    static func countRecords(in url: URL) async throws -> Int {
        let file = try await LockedFile.openForReading(url)
        defer { file.close() }

        var count = 0
        var sawBytesSinceNewline = false

        while true {
            try Task.checkCancellation()

            let chunk: Data?
            do {
                chunk = try file.handle.read(upToCount: chunkBytes)
            } catch {
                throw LedgerError.unreadableSegment(path: url.path, underlying: String(describing: error))
            }
            guard let chunk, !chunk.isEmpty else { break }

            for byte in chunk {
                if byte == 0x0A {
                    if sawBytesSinceNewline { count += 1 }
                    sawBytesSinceNewline = false
                } else {
                    sawBytesSinceNewline = true
                }
            }
        }

        if sawBytesSinceNewline { count += 1 }
        return count
    }

    // MARK: - Fingerprinting and the sidecar

    static func fingerprint(of url: URL, fileManager: FileManager) throws -> Fingerprint {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            throw LedgerError.unreadableSegment(path: url.path, underlying: String(describing: error))
        }
        return Fingerprint(
            byteSize: (attributes[.size] as? NSNumber)?.intValue ?? 0,
            modifiedAt: (attributes[.modificationDate] as? Date) ?? .distantPast
        )
    }

    static func readSidecar(for url: URL) -> SegmentCountRecord? {
        let sidecar = LedgerSegmentNaming.countSidecar(for: url)
        guard let data = try? Data(contentsOf: sidecar) else { return nil }
        return try? CanonicalJSON.decode(SegmentCountRecord.self, from: data)
    }

    /// Best-effort. A failure here costs a recount next launch and nothing else,
    /// so it must never propagate — an unwritable ledger directory is a normal
    /// condition when reading a ledger this process did not create, not an error
    /// in reading it.
    static func writeSidecar(_ record: SegmentCountRecord, for url: URL) {
        guard let data = try? CanonicalJSON.encode(record) else { return }
        try? data.write(to: LedgerSegmentNaming.countSidecar(for: url), options: [.atomic])
    }
}

/// Remembered record counts, keyed by segment.
///
/// A `struct` so it can live directly on ``LedgerStore`` and be mutated under
/// actor isolation without any of it needing to be `Sendable` on its own.
struct SegmentCountCache: Equatable, Sendable {
    private var memory: [URL: SegmentCountRecord] = [:]

    init() {}

    /// The remembered count for `url`, provided the file on disk is still the
    /// one it was taken from. Falls back to the on-disk sidecar, so the first
    /// launch after a relaunch is as cheap as the second.
    mutating func count(
        for url: URL,
        matching fingerprint: SegmentRecordCounting.Fingerprint
    ) -> Int? {
        guard let candidate = memory[url] ?? SegmentRecordCounting.readSidecar(for: url),
            candidate.schemaVersion == SegmentRecordCounting.schemaVersion,
            candidate.byteSize == fingerprint.byteSize,
            candidate.modifiedAt == fingerprint.modifiedAt
        else {
            return nil
        }
        memory[url] = candidate
        return candidate.recordCount
    }

    mutating func remember(
        count: Int,
        for url: URL,
        fingerprint: SegmentRecordCounting.Fingerprint
    ) {
        let record = SegmentCountRecord(
            schemaVersion: SegmentRecordCounting.schemaVersion,
            recordCount: count,
            byteSize: fingerprint.byteSize,
            modifiedAt: fingerprint.modifiedAt
        )
        memory[url] = record
        SegmentRecordCounting.writeSidecar(record, for: url)
    }
}
