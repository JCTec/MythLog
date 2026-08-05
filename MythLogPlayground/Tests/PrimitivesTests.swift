import Foundation
import Testing

@testable import MythLog

@Suite("Canonical encoding and the additive-only schema")
struct CanonicalEncodingTests {

    private let sampleEvent = AlarmEvent(
        id: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!,
        observedAt: Date(timeIntervalSince1970: 1_700_000_000),
        host: "test-host",
        source: "filesystem",
        name: "path.changed",
        severity: .warning,
        metadata: ["path": "/Users/test/Documents/a b.txt", "kind": "modified"]
    )

    /// The shape `AlarmEvent` had when the first ledger was written.
    ///
    /// If someone adds a non-optional field to `AlarmEvent`, this stops matching
    /// and the test fails — which is the point. Every ledger a user already has
    /// would otherwise stop verifying, silently, in the field. See the doc
    /// comment on ``AlarmEvent``.
    private struct EventAsOriginallyShipped: Encodable {
        var id: UUID
        var observedAt: Date
        var host: String
        var source: String
        var name: String
        var severity: String
        var metadata: [String: String]
    }

    @Test("the encoded event has exactly the fields the shipping format defines")
    func schemaHasNotGrown() throws {
        let original = EventAsOriginallyShipped(
            id: sampleEvent.id,
            observedAt: sampleEvent.observedAt,
            host: sampleEvent.host,
            source: sampleEvent.source,
            name: sampleEvent.name,
            severity: sampleEvent.severity.rawValue,
            metadata: sampleEvent.metadata
        )

        #expect(try CanonicalJSON.encode(sampleEvent) == CanonicalJSON.encode(original))
    }

    @Test("keys are sorted, slashes are unescaped, and dates are ISO 8601")
    func encodingIsCanonical() throws {
        let json = String(decoding: try CanonicalJSON.encode(sampleEvent), as: UTF8.self)

        // Sorted keys: `host` precedes `id` precedes `metadata`.
        #expect(json.range(of: "\"host\"")!.lowerBound < json.range(of: "\"id\"")!.lowerBound)
        #expect(json.range(of: "\"id\"")!.lowerBound < json.range(of: "\"metadata\"")!.lowerBound)

        #expect(json.contains("/Users/test/Documents/a b.txt"))
        #expect(!json.contains("\\/"))
        #expect(json.contains("2023-11-14T22:13:20Z"))
    }

    @Test("encoding is byte-stable across repeated calls")
    func encodingIsStable() throws {
        let first = try CanonicalJSON.encode(sampleEvent)
        for _ in 0..<20 {
            #expect(try CanonicalJSON.encode(sampleEvent) == first)
        }
    }

    @Test("a record round-trips through canonical JSON unchanged")
    func recordRoundTrips() throws {
        let record = LedgerRecord(
            event: sampleEvent,
            previousHash: LedgerHashChain.zeroHash,
            hash: String(repeating: "a", count: 64)
        )
        let data = try CanonicalJSON.encode(record)
        let decoded = try CanonicalJSON.decode(LedgerRecord.self, from: data)
        // Not `record == decoded` alone: the hash is over the *bytes*, so what
        // matters is that re-encoding produces the same bytes.
        #expect(try CanonicalJSON.encode(decoded) == data)
    }

    @Test("the same event and predecessor always hash to the same value")
    func hashingIsDeterministic() throws {
        let key = try LedgerHashChain.symmetricKey(from: Data("key".utf8))
        let first = try LedgerHashChain.hash(event: sampleEvent, previousHash: LedgerHashChain.zeroHash, key: key)
        let second = try LedgerHashChain.hash(event: sampleEvent, previousHash: LedgerHashChain.zeroHash, key: key)
        #expect(first == second)
        #expect(first.count == 64)

        // A different predecessor is a different hash — that is the chain.
        let third = try LedgerHashChain.hash(
            event: sampleEvent, previousHash: String(repeating: "1", count: 64), key: key)
        #expect(third != first)
    }
}

@Suite("Hex encoding")
struct HexEncodingTests {

    @Test("round-trips arbitrary bytes")
    func roundTrips() throws {
        let bytes = Data((0...255).map { UInt8($0) })
        #expect(try Data(hexEncoded: bytes.hexEncodedString) == bytes)
    }

    @Test("encodes lowercase, two characters per byte")
    func encodesLowercase() {
        #expect(Data([0x00, 0x0F, 0xA5, 0xFF]).hexEncodedString == "000fa5ff")
    }

    @Test("accepts uppercase input")
    func acceptsUppercase() throws {
        #expect(try Data(hexEncoded: "00FFa5") == Data([0x00, 0xFF, 0xA5]))
    }

    @Test("rejects an odd-length string")
    func rejectsOddLength() {
        #expect(throws: HexDecodingError.oddLength(count: 3)) {
            _ = try Data(hexEncoded: "abc")
        }
    }

    @Test("rejects a non-hexadecimal character")
    func rejectsNonHex() {
        #expect(throws: HexDecodingError.invalidCharacter("zz")) {
            _ = try Data(hexEncoded: "00zz")
        }
    }
}

@Suite("@Clamped")
struct ClampedTests {
    private struct Window {
        @Clamped(600...86_400) var span: TimeInterval = 3600
    }

    @Test("an out-of-range initial value is brought into range")
    func clampsAtInitialisation() {
        struct Low { @Clamped(600...86_400) var span: TimeInterval = 1 }
        struct High { @Clamped(600...86_400) var span: TimeInterval = 999_999 }
        #expect(Low().span == 600)
        #expect(High().span == 86_400)
    }

    @Test("an out-of-range assignment is brought into range")
    func clampsOnAssignment() {
        var window = Window()
        window.span = -5
        #expect(window.span == 600)
        window.span = 1_000_000
        #expect(window.span == 86_400)
        window.span = 7200
        #expect(window.span == 7200)
    }

    @Test("the projected value exposes the bounds")
    func projectsBounds() {
        #expect(Window().$span == 600...86_400)
    }

    @Test("bounds are part of equality, so windows over different histories differ")
    func boundsParticipateInEquality() {
        let narrow = Clamped(wrappedValue: 1000.0, 600.0...2000.0)
        let wide = Clamped(wrappedValue: 1000.0, 600.0...86_400.0)
        #expect(narrow.wrappedValue == wide.wrappedValue)
        #expect(narrow != wide)
    }
}

@Suite("@Memoized")
struct MemoizedTests {
    /// The wrapped function cannot capture `self` (see the wrapper's doc
    /// comment), so the call counter is a separate object the closure captures.
    private final class CallCounter {
        var count = 0
    }

    private final class Calculator {
        let counter: CallCounter
        @Memoized var double: (Int) throws -> Int

        init(capacity: Int = 3) {
            let counter = CallCounter()
            self.counter = counter
            _double = Memoized(
                wrappedValue: { value in
                    counter.count += 1
                    return value * 2
                },
                capacity: capacity
            )
        }

        var callCount: Int { counter.count }
    }

    @Test("computes once per distinct key")
    func computesOncePerKey() throws {
        let calculator = Calculator()
        #expect(try calculator.double(2) == 4)
        #expect(try calculator.double(2) == 4)
        #expect(try calculator.double(2) == 4)
        #expect(calculator.callCount == 1)
        #expect(calculator.$double.hits == 2)
        #expect(calculator.$double.misses == 1)
    }

    @Test("evicts the least recently used entry beyond capacity")
    func evictsLeastRecentlyUsed() throws {
        let calculator = Calculator()
        _ = try calculator.double(1)
        _ = try calculator.double(2)
        _ = try calculator.double(3)
        _ = try calculator.double(1)  // 1 is now the most recently used; 2 the least
        _ = try calculator.double(4)  // evicts 2

        let before = calculator.callCount
        _ = try calculator.double(1)
        #expect(calculator.callCount == before, "1 should still be cached")
        _ = try calculator.double(2)
        #expect(calculator.callCount == before + 1, "2 should have been evicted")
    }

    private final class Switch {
        var shouldThrow = true
        var count = 0
    }

    @Test("a thrown error is not cached — a cancelled computation must not poison the entry")
    func doesNotCacheFailures() throws {
        let control = Switch()
        let memo = Memoized<Int, Int>(wrappedValue: { key in
            control.count += 1
            if control.shouldThrow { throw CancellationError() }
            return key
        })

        #expect(throws: CancellationError.self) { _ = try memo.wrappedValue(1) }
        control.shouldThrow = false
        #expect(try memo.wrappedValue(1) == 1)
        #expect(control.count == 2, "the cancelled computation must not have been cached")
        #expect(memo.hits == 0)
    }

    @Test("invalidation drops everything")
    func invalidateClearsCache() throws {
        let calculator = Calculator()
        _ = try calculator.double(7)
        calculator.$double.invalidate()
        _ = try calculator.double(7)
        #expect(calculator.callCount == 2)
    }
}
