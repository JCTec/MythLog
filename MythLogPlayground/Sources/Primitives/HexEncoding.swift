import Foundation

enum HexDecodingError: Error, Equatable, LocalizedError, Sendable {
    case oddLength(count: Int)
    case invalidCharacter(String)

    var errorDescription: String? {
        switch self {
        case .oddLength(let count):
            "Hexadecimal string has an odd length (\(count) characters)."
        case .invalidCharacter(let text):
            "Not a hexadecimal byte: \"\(text)\"."
        }
    }
}

extension Data {
    /// Lowercase hex, two characters per byte, no separators. This is the form
    /// every hash in the ledger is stored in.
    ///
    /// Built by table lookup rather than `String(format:)`: verification hexes
    /// two 32-byte digests per record, so on a 100k-record ledger this runs
    /// 6.4 million times and `String(format:)`'s parser is the dominant cost.
    var hexEncodedString: String {
        let digits: [UInt8] = Array("0123456789abcdef".utf8)
        var out = [UInt8]()
        out.reserveCapacity(count * 2)
        for byte in self {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    init(hexEncoded string: String) throws {
        let characters = Array(string.utf8)
        guard characters.count.isMultiple(of: 2) else {
            throw HexDecodingError.oddLength(count: characters.count)
        }

        var bytes = [UInt8]()
        bytes.reserveCapacity(characters.count / 2)

        var index = 0
        while index < characters.count {
            guard let high = Data.nibble(characters[index]), let low = Data.nibble(characters[index + 1]) else {
                let pair = String(decoding: characters[index...(index + 1)], as: UTF8.self)
                throw HexDecodingError.invalidCharacter(pair)
            }
            bytes.append(high << 4 | low)
            index += 2
        }

        self = Data(bytes)
    }

    private static func nibble(_ character: UInt8) -> UInt8? {
        switch character {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): character - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): character - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): character - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}
