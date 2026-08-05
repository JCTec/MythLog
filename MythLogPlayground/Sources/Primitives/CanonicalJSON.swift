import Foundation

/// The one encoding the hash chain is defined over.
///
/// Two independent processes must produce byte-identical JSON for the same
/// value or the HMAC will not match, so these three settings are part of the
/// ledger format, not a preference:
///
/// - `.sortedKeys` — key order is otherwise unspecified, and would differ
///   between runs of the same binary.
/// - `.withoutEscapingSlashes` — `/` in a path would otherwise be emitted as
///   `\/`, which is valid JSON and a different byte sequence.
/// - `.iso8601` dates — the default is a `Double` since the reference date,
///   whose textual form is platform- and precision-dependent.
///
/// These match the shipping recorder exactly. Changing any of them invalidates
/// every ledger in existence, for the reasons spelled out on ``AlarmEvent``.
///
/// The encoder and decoder are created per call rather than shared. `JSONEncoder`
/// is a class with mutable configuration; a shared instance would be exactly the
/// non-`Sendable` process-wide state Swift 6 rejects, and the allocation is
/// irrelevant next to the HMAC and the file write.
enum CanonicalJSON {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Pretty-printed variant for files a human reads (config, proof bundles).
    /// Never used for hashing — the whitespace is not part of the contract.
    static func makeReadableEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func encode(_ value: some Encodable) throws -> Data {
        try makeEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try makeDecoder().decode(type, from: data)
    }

    /// One JSONL line: canonical JSON followed by a single newline.
    static func encodeLine(_ value: some Encodable) throws -> Data {
        var data = try encode(value)
        data.append(0x0A)
        return data
    }
}
