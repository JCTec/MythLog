import Foundation
import Testing

@testable import MythLog

/// Writing, rotating, streaming, cancelling — the port exercised on its own
/// output rather than on a fixture.
@Suite("Writing and rotating a ledger")
struct LedgerWriteTests {

    private func makeStore(in temporary: TemporaryDirectory, maxFileBytes: Int? = nil) throws -> LedgerStore {
        try LedgerStore(
            ledgerURL: temporary.appendingPathComponent("events.jsonl"),
            hmacKey: Data("write-tests-key".utf8),
            maxFileBytes: maxFileBytes
        )
    }

    private func event(_ index: Int) -> AlarmEvent {
        AlarmEvent(
            observedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 60),
            host: "test-host",
            source: "test",
            name: "event.\(index)",
            severity: .info,
            metadata: ["index": "\(index)"]
        )
    }

    @Test("a freshly written chain verifies and ordinals run 1…n")
    func appendedChainVerifies() async throws {
        let temporary = try TemporaryDirectory()
        let store = try makeStore(in: temporary)

        for index in 0..<25 {
            try await store.append(event(index))
        }

        let verification = try await store.verify()
        #expect(verification.isValid)
        #expect(verification.recordCount == 25)
        #expect(verification.segmentCount == 1)
        #expect(try await store.allEntries().map(\.ordinal) == Array(1...25))
    }

    @Test("the first record chains to the zero hash")
    func firstRecordChainsToZero() async throws {
        let temporary = try TemporaryDirectory()
        let store = try makeStore(in: temporary)
        try await store.append(event(0))

        let entries = try await store.allEntries()
        #expect(entries.first?.record.previousHash == LedgerHashChain.zeroHash)
    }

    @Test("rotation keeps the chain unbroken and ordinals cumulative")
    func rotationPreservesTheChain() async throws {
        let temporary = try TemporaryDirectory()
        // Small enough that a handful of appends forces several rotations.
        let store = try makeStore(in: temporary, maxFileBytes: 900)

        for index in 0..<40 {
            try await store.append(event(index))
        }

        let chain = try await store.chain()
        #expect(chain.segments.count > 1, "the fixture did not actually rotate")

        let verification = try await store.verify()
        #expect(verification.issues.isEmpty, "\(verification.issues.map(\.message))")
        #expect(verification.isValid)
        #expect(verification.segmentCount == chain.segments.count)

        // 40 appended events plus one `ledger.rotated` record per rotation.
        let entries = try await store.allEntries()
        #expect(entries.count == 40 + (chain.segments.count - 1))
        #expect(entries.map(\.ordinal) == Array(1...entries.count))

        // Each rotation seam is itself a record, so the break is visible in the
        // history rather than inferred from a gap in file names.
        let rotations = entries.filter { $0.event.name == "ledger.rotated" }
        #expect(rotations.count == chain.segments.count - 1)
    }

    @Test("appending across a rotation leaves history untouched and every link intact")
    func appendAfterRotationContinuesTheChain() async throws {
        let temporary = try TemporaryDirectory()
        let store = try makeStore(in: temporary, maxFileBytes: 700)

        for index in 0..<20 {
            try await store.append(event(index))
        }

        let before = try await store.allEntries()
        let headBefore = try await store.lastHash()
        #expect(before.last?.record.hash == headBefore)

        // This append may itself trigger a rotation, which writes a
        // `ledger.rotated` record before the event — so the new event is not
        // necessarily what links directly to `headBefore`.
        try await store.append(event(999))
        let after = try await store.allEntries()

        #expect(after.count > before.count)
        // Nothing already written was rewritten by the rotation.
        #expect(after.prefix(before.count).map(\.record) == before.map(\.record))
        // Whatever came next links back to the old head, across the seam.
        #expect(after[before.count].record.previousHash == headBefore)
        // And every link in the whole chain still holds.
        for (previous, next) in zip(after, after.dropFirst()) {
            #expect(next.record.previousHash == previous.record.hash)
        }
        #expect(after.map(\.ordinal) == Array(1...after.count))
        #expect(try await store.verify().isValid)
    }

    @Test("streaming stops promptly when the reading task is cancelled")
    func streamingIsCancellable() async throws {
        let temporary = try TemporaryDirectory()
        let store = try makeStore(in: temporary)
        for index in 0..<200 {
            try await store.append(event(index))
        }

        let sequence = try await store.entries()
        let task = Task { () -> Int in
            var seen = 0
            for try await _ in sequence {
                seen += 1
                if seen == 5 { break }
            }
            // Past the break the task is still alive; cancel below must make the
            // next read throw rather than run to completion.
            var afterCancel = 0
            for try await _ in sequence {
                afterCancel += 1
            }
            return afterCancel
        }

        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("a proof bundle streams the whole chain and records the verification verdict")
    func proofBundleExports() async throws {
        let temporary = try TemporaryDirectory()
        let store = try makeStore(in: temporary, maxFileBytes: 900)
        for index in 0..<30 {
            try await store.append(event(index))
        }

        let destination = temporary.appendingPathComponent("proof")
        let bundle = try await LedgerProofExporter(store: store).export(to: destination)

        #expect(bundle.verification.isValid)
        #expect(bundle.verification.recordCount > 30)

        let exported = try String(
            contentsOf: destination.appendingPathComponent("events.jsonl"), encoding: .utf8)
        let exportedLines = exported.split(separator: "\n").count
        #expect(exportedLines == bundle.verification.recordCount)

        // The exported copy is itself a ledger, and it must verify on its own.
        let reexported = try LedgerStore(
            ledgerURL: destination.appendingPathComponent("events.jsonl"),
            hmacKey: Data("write-tests-key".utf8)
        )
        #expect(try await reexported.verify().isValid)

        let summary = try String(contentsOf: destination.appendingPathComponent("summary.txt"), encoding: .utf8)
        #expect(summary.contains(bundle.verification.lastHash))
    }

    @Test("verification of a damaged export names the last trustworthy record")
    func proofBundleReportsPartialTrust() async throws {
        let temporary = try TemporaryDirectory()
        let store = try makeStore(in: temporary)
        for index in 0..<10 {
            try await store.append(event(index))
        }

        let ledgerURL = temporary.appendingPathComponent("events.jsonl")
        var lines = try String(contentsOf: ledgerURL, encoding: .utf8).split(separator: "\n").map(String.init)
        lines[6] = lines[6].replacingOccurrences(of: "\"test-host\"", with: "\"other-host\"")
        try (lines.joined(separator: "\n") + "\n").write(to: ledgerURL, atomically: true, encoding: .utf8)

        let verification = try await store.verify()
        #expect(!verification.isValid)
        #expect(verification.lastTrustedOrdinal == 6)
        #expect(verification.recordCount == 10)
    }
}
