import Foundation
import Testing

@testable import MythLog

/// The Wave 1 gate: **a ledger written by the shipping app verifies here**, with
/// correct cumulative ordinals across rotated segments.
///
/// The fixture in `Tests/Fixtures/shipping-ledger` was produced by
/// `Sources/MythLogCore/HashChainLedger.swift` — the code that is live on the
/// App Store — not by anything in this target. It is 153 records across 14
/// segments, so the seams and the ordinal arithmetic are both genuinely
/// exercised rather than implied.
@Suite("Ledger written by the shipping app")
struct ShippingLedgerCompatibilityTests {

    @Test("verifies, with the record count, segment count and chain head the shipping engine reported")
    func verifiesAgainstShippingManifest() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try temporary.copyShippingLedger()
        let manifest = try LedgerFixtures.shippingManifest()

        let store = try LedgerStore(ledgerURL: ledgerURL, hmacKey: try LedgerFixtures.shippingHMACKey())
        let verification = try await store.verify()

        #expect(verification.issues.isEmpty, "\(verification.issues.map(\.message))")
        #expect(verification.isValid)
        #expect(verification.recordCount == manifest.records)
        #expect(verification.segmentCount == manifest.segments)
        #expect(verification.lastHash == manifest.lastHash)
    }

    @Test("assigns ordinals cumulatively across every rotated segment")
    func ordinalsAreCumulativeAcrossSegments() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try temporary.copyShippingLedger()
        let manifest = try LedgerFixtures.shippingManifest()

        let store = try LedgerStore(ledgerURL: ledgerURL, hmacKey: try LedgerFixtures.shippingHMACKey())
        let entries = try await store.allEntries()

        #expect(entries.count == manifest.records)

        // The property that a line index within one file cannot have: 1, 2, 3 …
        // straight through every rotation, with no restart and no gap.
        #expect(entries.map(\.ordinal) == Array(1...manifest.records))

        // And it really does span segments — otherwise the assertion above would
        // pass trivially on a single-file ledger.
        let segmentIndices = Set(entries.map(\.segmentIndex))
        #expect(segmentIndices.count == manifest.segments)

        // Every record links to the ordinal before it, which is what the
        // inspector's "#4629 · chained to #4628" line renders.
        for entry in entries.dropFirst() {
            #expect(entry.previousOrdinal == entry.ordinal - 1)
        }
        #expect(entries.first?.previousOrdinal == nil)
    }

    @Test("gives a segment's first record the ordinal after the last record of the segment before it")
    func segmentBaseOrdinalsAreContiguous() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try temporary.copyShippingLedger()

        let store = try LedgerStore(ledgerURL: ledgerURL, hmacKey: try LedgerFixtures.shippingHMACKey())
        let chain = try await store.chain()
        let entries = try await store.allEntries()

        for segment in chain.segments {
            let inSegment = entries.filter { $0.segmentIndex == segment.index }
            #expect(!inSegment.isEmpty, "segment \(segment.index) unexpectedly empty")
            #expect(inSegment.first?.ordinal == segment.baseOrdinal + 1)
            #expect(inSegment.last?.ordinal == segment.baseOrdinal + inSegment.count)
        }
    }

    @Test("reports the same record count whether it is counted or streamed")
    func countedAndStreamedTotalsAgree() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try temporary.copyShippingLedger()

        let store = try LedgerStore(ledgerURL: ledgerURL, hmacKey: try LedgerFixtures.shippingHMACKey())
        let counted = try await store.recordCount()
        let streamed = try await store.allEntries().count

        // The counter never decodes JSON and the stream decodes every line; if
        // they ever disagree, ordinals are wrong somewhere.
        #expect(counted == streamed)
    }

    @Test("reads the chain head without streaming the whole history")
    func lastHashMatchesTheFinalRecord() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try temporary.copyShippingLedger()

        let store = try LedgerStore(ledgerURL: ledgerURL, hmacKey: try LedgerFixtures.shippingHMACKey())
        let head = try await store.lastHash()
        let entries = try await store.allEntries()

        #expect(head == entries.last?.record.hash)
        #expect(head == (try LedgerFixtures.shippingManifest()).lastHash)
    }

    @Test("caches each rotated segment's record count beside it, and re-reads give identical ordinals")
    func ordinalCachePersistsAndStaysCorrect() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try temporary.copyShippingLedger()
        let key = try LedgerFixtures.shippingHMACKey()

        let first = try LedgerStore(ledgerURL: ledgerURL, hmacKey: key)
        let firstOrdinals = try await first.allEntries().map(\.ordinal)

        let directory = ledgerURL.deletingLastPathComponent()
        let sidecars = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { LedgerSegmentNaming.isCountSidecar($0) }
        #expect(!sidecars.isEmpty, "no ordinal sidecar was written beside any rotated segment")

        // A second store shares nothing in memory with the first, so it can only
        // agree by reading the sidecars — or by recounting, which must give the
        // same answer either way.
        let second = try LedgerStore(ledgerURL: ledgerURL, hmacKey: key)
        #expect(try await second.allEntries().map(\.ordinal) == firstOrdinals)
    }

    @Test("ignores ordinal sidecars when discovering segments")
    func sidecarsAreNotMistakenForSegments() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try temporary.copyShippingLedger()
        let key = try LedgerFixtures.shippingHMACKey()

        // First pass writes the sidecars.
        _ = try await LedgerStore(ledgerURL: ledgerURL, hmacKey: key).chain()

        let chain = try await LedgerStore(ledgerURL: ledgerURL, hmacKey: key).chain()
        #expect(chain.segments.count == (try LedgerFixtures.shippingManifest()).segments)
        #expect(chain.segments.allSatisfy { !LedgerSegmentNaming.isCountSidecar($0.url) })
    }
}
