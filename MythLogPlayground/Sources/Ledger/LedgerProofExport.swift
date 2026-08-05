import Foundation

/// What an exported proof bundle contains, described for the person who has to
/// read it a year from now.
struct LedgerProofBundle: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var exportedAt: Date
    var ledgerPath: String
    var proofDirectoryPath: String
    var verification: LedgerVerification
    var firstEventAt: Date?
    var lastEventAt: Date?
    var anchorComparison: LedgerAnchorComparison?

    init(
        schemaVersion: Int = 1,
        exportedAt: Date,
        ledgerPath: String,
        proofDirectoryPath: String,
        verification: LedgerVerification,
        firstEventAt: Date?,
        lastEventAt: Date?,
        anchorComparison: LedgerAnchorComparison? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.ledgerPath = ledgerPath
        self.proofDirectoryPath = proofDirectoryPath
        self.verification = verification
        self.firstEventAt = firstEventAt
        self.lastEventAt = lastEventAt
        self.anchorComparison = anchorComparison
    }
}

/// Writes a self-contained bundle: the records, the verification result, and a
/// plain-English summary.
///
/// # Why the copy streams
///
/// The obvious implementation reads the ledger into `Data` and writes it out.
/// That is fine at ten thousand records and fatal at ten million — and the
/// moment a user most wants to export a proof is when something has gone wrong
/// on a Mac that has been recording for years.
///
/// So the events file is copied segment by segment, in fixed-size chunks, with a
/// cancellation check between each. Peak memory is one chunk regardless of
/// history length.
struct LedgerProofExporter {
    let store: LedgerStore
    private static let chunkBytes = 1 << 20

    init(store: LedgerStore) {
        self.store = store
    }

    @discardableResult
    func export(
        to destination: URL,
        exportedAt: Date = .now,
        anchor: LedgerHashAnchor? = nil,
        fileManager: sending FileManager = FileManager()
    ) async throws -> LedgerProofBundle {
        let chain = try await store.chain()
        let verification = try await store.verify()

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destination.path)

        // Named after the ledger it came from rather than a literal, so the
        // bundle mirrors whatever the user's ledger is actually called — and so
        // this file is not a second place that decides what a ledger is named.
        // `Scripts/check-layering.sh` enforces the second half.
        let eventsURL = destination.appendingPathComponent(store.activeURL.lastPathComponent)
        let span = try await copyRecords(chain: chain, to: eventsURL, fileManager: fileManager)

        let comparison = anchor.map { anchor in
            LedgerAnchorComparison.compare(
                recordCount: verification.recordCount,
                hashAtAnchoredPosition: verification.recordCount == anchor.recordCount
                    ? verification.lastHash : nil,
                anchor: anchor
            )
        }

        let bundle = LedgerProofBundle(
            exportedAt: exportedAt,
            ledgerPath: store.activeURL.path,
            proofDirectoryPath: destination.path,
            verification: verification,
            firstEventAt: span.first,
            lastEventAt: span.last,
            anchorComparison: comparison
        )

        try write(
            try CanonicalJSON.makeReadableEncoder().encode(bundle),
            to: destination.appendingPathComponent("verification.json"),
            fileManager: fileManager
        )
        try write(
            Data(summary(for: bundle).utf8),
            to: destination.appendingPathComponent("summary.txt"),
            fileManager: fileManager
        )
        try write(
            Data((verification.lastHash + "\n").utf8),
            to: destination.appendingPathComponent("last-hash.txt"),
            fileManager: fileManager
        )

        return bundle
    }

    /// Copies every segment into one `events.jsonl`, chunk by chunk, and returns
    /// the timestamps of the first and last event seen.
    ///
    /// The two timestamps are read from the first and last records rather than
    /// from the copy, so this makes exactly one pass over the bytes.
    private func copyRecords(
        chain: LedgerChain,
        to destination: URL,
        fileManager: FileManager
    ) async throws -> (first: Date?, last: Date?) {
        fileManager.createFile(atPath: destination.path, contents: nil)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)

        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        for segment in chain.segments {
            try Task.checkCancellation()
            let source = try await LockedFile.openForReading(segment.url)
            defer { source.close() }

            while true {
                try Task.checkCancellation()
                guard let chunk = try source.handle.read(upToCount: Self.chunkBytes), !chunk.isEmpty else { break }
                try output.write(contentsOf: chunk)
            }
        }

        var first: Date?
        var last: Date?
        for try await entry in LedgerRecordSequence(segments: chain.segments.prefix(1).map { $0 }) {
            first = entry.event.observedAt
            break
        }
        if let lastSegment = chain.segments.last {
            for try await entry in LedgerRecordSequence(segments: [lastSegment]) {
                try Task.checkCancellation()
                last = entry.event.observedAt
            }
        }
        return (first, last)
    }

    private func write(_ data: Data, to url: URL, fileManager: FileManager) throws {
        try data.write(to: url, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func summary(for bundle: LedgerProofBundle) -> String {
        let first = bundle.firstEventAt?.formatted(.iso8601) ?? "none"
        let last = bundle.lastEventAt?.formatted(.iso8601) ?? "none"
        let verdict =
            bundle.verification.isValid
            ? "Every one of the \(bundle.verification.recordCount) records verifies."
            : """
            Records #1 – #\(bundle.verification.lastTrustedOrdinal) verify and remain trustworthy. \
            \(bundle.verification.issues.count) issue(s) were found after that point.
            """

        return """
            MythLog Ledger Proof
            Exported:    \(bundle.exportedAt.formatted(.iso8601))
            Ledger:      \(bundle.ledgerPath)
            Segments:    \(bundle.verification.segmentCount)
            Records:     \(bundle.verification.recordCount)
            First event: \(first)
            Last event:  \(last)
            Chain head:  \(bundle.verification.lastHash)

            \(verdict)

            \(bundle.verification.issues.map(\.message).joined(separator: "\n"))
            """
    }
}
