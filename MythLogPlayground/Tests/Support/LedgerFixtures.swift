import Foundation

@testable import MythLog

/// Locating and copying the on-disk fixtures.
///
/// Every test that reads a fixture copies it to a temporary directory first.
/// Reading a ledger writes ordinal sidecars beside its segments, and the
/// fixtures live in the repository — a test that read them in place would dirty
/// the working tree on every run.
enum LedgerFixtures {
    /// The fixture written by the **shipping** engine
    /// (`Sources/MythLogCore/HashChainLedger.swift`), not by this one. It is the
    /// cross-implementation gate: if the port drifts from the format the
    /// recorder writes, this fixture stops verifying.
    static var shippingLedgerDirectory: URL {
        testsDirectory
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("shipping-ledger", isDirectory: true)
    }

    static var testsDirectory: URL {
        // `#filePath` is this file, `Tests/Support/LedgerFixtures.swift`.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// What the shipping engine reported when it wrote the fixture. The port has
    /// to agree with all of it.
    struct Manifest: Decodable, Sendable {
        var appendedEvents: String
        var recordCount: String
        var segmentCount: String
        var lastHash: String
        var isValid: String

        var records: Int { Int(recordCount) ?? -1 }
        var segments: Int { Int(segmentCount) ?? -1 }
    }

    static func shippingManifest() throws -> Manifest {
        let data = try Data(contentsOf: shippingLedgerDirectory.appendingPathComponent("manifest.json"))
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    static func shippingHMACKey() throws -> Data {
        let hex = try String(contentsOf: shippingLedgerDirectory.appendingPathComponent("hmac-key.hex"), encoding: .utf8)
        return try Data(hexEncoded: hex.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// A directory that deletes itself.
///
/// A `final class` rather than a `struct` so cleanup can hang off `deinit` — a
/// test that fails part-way still leaves nothing behind.
final class TemporaryDirectory {
    let url: URL

    init(name: String = UUID().uuidString) throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mythlog-tests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Copies the shipping fixture in and returns the active ledger URL.
    func copyShippingLedger() throws -> URL {
        let destination = url.appendingPathComponent("ledger", isDirectory: true)
        try FileManager.default.copyItem(at: LedgerFixtures.shippingLedgerDirectory, to: destination)
        return destination.appendingPathComponent("events.jsonl")
    }

    func appendingPathComponent(_ component: String) -> URL {
        url.appendingPathComponent(component)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

extension LedgerStore {
    /// Streams the whole ledger into an array. Only ever used by tests, where
    /// the ledgers are small by construction — production code streams.
    func allEntries() async throws -> [LedgerEntry] {
        var collected = [LedgerEntry]()
        for try await entry in try await entries() {
            collected.append(entry)
        }
        return collected
    }
}
