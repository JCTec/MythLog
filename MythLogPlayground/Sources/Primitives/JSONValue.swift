import Foundation

/// A JSON value of unknown shape, preserved exactly.
///
/// # Why a document format needs this
///
/// `Codable` silently discards keys it does not model. For a settings struct
/// that is fine; for a *file the user owns*, edited by more than one version of
/// more than one program, it is data loss. A config written by a newer build of
/// the shipping recorder, loaded and saved by this one, would quietly come back
/// smaller.
///
/// So `EngineConfig` models the sections this build actually uses and keeps
/// everything else here, verbatim, re-emitting it untouched. That makes the
/// round trip lossless in the direction that matters: forwards.
///
/// # Why integers are distinguished from doubles
///
/// `JSONEncoder` writes `Double(60)` as `60` and `Double(60.5)` as `60.5`, so
/// collapsing everything to `Double` would round-trip most values correctly and
/// mangle large integers past 2^53. Decoding tries `Int` first and falls back,
/// which reproduces the input in both cases.
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Not a JSON value.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Every string anywhere beneath this value, with the key path that reached
    /// it. Used by validation to find path-shaped strings in sections this build
    /// does not model — a tilde in `filesystem.watchedPaths` is worth a warning
    /// even though nothing here interprets that section.
    func strings(prefix: String = "") -> [(path: String, value: String)] {
        switch self {
        case .string(let value):
            [(prefix, value)]
        case .array(let values):
            values.enumerated().flatMap { $0.element.strings(prefix: "\(prefix)[\($0.offset)]") }
        case .object(let values):
            values.sorted { $0.key < $1.key }.flatMap {
                $0.value.strings(prefix: prefix.isEmpty ? $0.key : "\(prefix).\($0.key)")
            }
        case .null, .bool, .int, .double:
            []
        }
    }
}
