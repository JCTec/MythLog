import Foundation
import Testing

@testable import MythLog

/// Damage detection.
///
/// Every test here starts from the ledger the shipping app wrote, breaks it in
/// one specific way, and asserts the port says so — at the right cumulative
/// ordinal, and **as a failing ledger rather than an empty one**. The second
/// half of that sentence is the one that matters: a viewer that renders a
/// corrupted history as "nothing recorded" is worse than one that crashes.
@Suite("A damaged ledger is reported as damaged")
struct LedgerIntegrityTests {

    /// Rewrites one line of a ledger segment in place.
    private func editLine(_ url: URL, at index: Int, transform: (String) -> String?) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // `split` leaves a trailing empty component for the final newline.
        if lines.last == "" { lines.removeLast() }
        if let replacement = transform(lines[index]) {
            lines[index] = replacement
        } else {
            lines.remove(at: index)
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func rotatedSegments(in ledgerURL: URL) throws -> [URL] {
        try LedgerSegmentNaming.rotatedSegmentURLs(for: ledgerURL, fileManager: FileManager())
    }

    @Test("an altered event is reported as an altered record, at its cumulative ordinal")
    func tamperedRecordIsDetected() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try temporary.copyShippingLedger()
        let key = try LedgerFixtures.shippingHMACKey()

        // Pick a record in the middle of a rotated segment so the finding has to
        // survive the base-ordinal arithmetic to land in the right place.
        let chain = try await LedgerStore(ledgerURL: ledgerURL, hmacKey: key).chain()
        let target = chain.segments[3]
        // Second line of the fourth segment: `baseOrdinal` + 2 in the cumulative
        // numbering the inspector shows.
        let tamperedOrdinal = target.ordinal(offsetInSegment: 1)

        try editLine(target.url, at: 1) { line in
            // A single character inside the event: the hash covers the whole
            // event, so this is enough.
            line.replacingOccurrences(of: "\"fixture-host\"", with: "\"someone-elses\"")
        }

        let store = try LedgerStore(ledgerURL: ledgerURL, hmacKey: key)
        let verification = try await store.verify()

        #expect(!verification.isValid)
        #expect(verification.issues.contains { $0.kind == .recordHashMismatch && $0.ordinal == tamperedOrdinal })
        // The record after it still links to a hash that is genuinely there, so
        // only the altered record is implicated — not the rest of the history.
        #expect(verification.lastTrustedOrdinal == tamperedOrdinal - 1)
        // Not empty. The whole history is still counted and reported.
        #expect(verification.recordCount == (try LedgerFixtures.shippingManifest()).records)
    }

    @Test("a truncated final line is reported as a failing ledger, not as a shorter one")
    func truncatedLedgerIsDetected() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try temporary.copyShippingLedger()
        let key = try LedgerFixtures.shippingHMACKey()

        let intact = try await LedgerStore(ledgerURL: ledgerURL, hmacKey: key).verify()

        // Chop the active segment mid-record: the byte pattern a power loss
        // during an append leaves behind.
        let data = try Data(contentsOf: ledgerURL)
        try data.prefix(data.count - 40).write(to: ledgerURL)

        let store = try LedgerStore(ledgerURL: ledgerURL, hmacKey: key)
        let verification = try await store.verify()

        #expect(!verification.isValid)
        #expect(verification.issues.contains { $0.kind == .undecodableRecord })

        // The critical assertion: everything before the damage is still read,
        // counted, and reported. A truncated ledger must not read as an empty
        // one.
        #expect(verification.recordCount == intact.recordCount - 1)
        #expect(verification.recordCount > 0)
        #expect(verification.lastTrustedOrdinal == intact.recordCount - 1)
    }

    @Test("truncation at a record boundary leaves a chain that still verifies — which is why anchors exist")
    func cleanTruncationStillVerifies() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try temporary.copyShippingLedger()
        let key = try LedgerFixtures.shippingHMACKey()

        let intact = try await LedgerStore(ledgerURL: ledgerURL, hmacKey: key).verify()

        let text = try String(contentsOf: ledgerURL, encoding: .utf8)
        var lines = text.split(separator: "\n").map(String.init)
        lines.removeLast(2)
        try (lines.joined(separator: "\n") + "\n").write(to: ledgerURL, atomically: true, encoding: .utf8)

        let verification = try await LedgerStore(ledgerURL: ledgerURL, hmacKey: key).verify()

        // The hash chain cannot see this, and pretending otherwise would be a
        // lie about what the chain proves.
        #expect(verification.isValid)
        #expect(verification.recordCount == intact.recordCount - 2)

        // The anchor is what catches it.
        let anchor = LedgerHashAnchor(
            createdAt: .now,
            deviceID: "fixture",
            ledgerPath: ledgerURL.path,
            recordCount: intact.recordCount,
            lastHash: intact.lastHash,
            isLedgerValid: true,
            reason: "test"
        )
        let comparison = LedgerAnchorComparison.compare(
            recordCount: verification.recordCount,
            hashAtAnchoredPosition: nil,
            anchor: anchor
        )
        #expect(comparison.verdict == .truncated)
        #expect(!comparison.matches)
    }

    @Test("a deleted record breaks the link to its successor")
    func deletedRecordIsDetected() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try temporary.copyShippingLedger()
        let key = try LedgerFixtures.shippingHMACKey()

        let segments = try rotatedSegments(in: ledgerURL)
        try editLine(segments[2], at: 1) { _ in nil }

        let verification = try await LedgerStore(ledgerURL: ledgerURL, hmacKey: key).verify()

        #expect(!verification.isValid)
        #expect(verification.issues.contains { $0.kind == .previousHashMismatch })
        #expect(verification.recordCount == (try LedgerFixtures.shippingManifest()).records - 1)
    }

    @Test("a missing segment breaks the seam between the segments around it")
    func removedSegmentIsDetected() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try temporary.copyShippingLedger()
        let key = try LedgerFixtures.shippingHMACKey()

        let segments = try rotatedSegments(in: ledgerURL)
        try FileManager.default.removeItem(at: segments[4])

        let verification = try await LedgerStore(ledgerURL: ledgerURL, hmacKey: key).verify()

        #expect(!verification.isValid)
        #expect(verification.issues.contains { $0.kind == .segmentSeamMismatch })
    }

    @Test("a ledger read with the wrong key fails every record rather than appearing empty")
    func wrongKeyFailsLoudly() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try temporary.copyShippingLedger()

        let store = try LedgerStore(ledgerURL: ledgerURL, hmacKey: Data("not-the-right-key".utf8))
        let verification = try await store.verify()

        #expect(!verification.isValid)
        #expect(verification.recordCount == (try LedgerFixtures.shippingManifest()).records)
        #expect(verification.issues.allSatisfy { $0.kind == .recordHashMismatch })
        #expect(verification.lastTrustedOrdinal == 0)
    }

    @Test("an empty HMAC key is refused at construction, not at read time")
    func emptyKeyIsRefused() throws {
        #expect(throws: LedgerError.emptyHMACKey) {
            _ = try LedgerStore(ledgerURL: URL(fileURLWithPath: "/tmp/none.jsonl"), hmacKey: Data())
        }
    }

    @Test("a ledger that has never been written is empty, not unreadable")
    func absentLedgerIsEmpty() async throws {
        let temporary = try TemporaryDirectory()
        let store = try LedgerStore(
            ledgerURL: temporary.appendingPathComponent("never-written.jsonl"),
            hmacKey: Data("key".utf8)
        )

        let verification = try await store.verify()
        #expect(verification.isValid)
        #expect(verification.recordCount == 0)
        #expect(try await store.allEntries().isEmpty)
        #expect(try await store.lastHash() == LedgerHashChain.zeroHash)
    }
}
