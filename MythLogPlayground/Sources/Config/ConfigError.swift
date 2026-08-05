import Foundation

enum ConfigError: Error, Equatable, LocalizedError, Sendable {
    case unreadable(path: String, underlying: String)
    case malformed(path: String, underlying: String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let path, let underlying):
            "The configuration at \(path) could not be read: \(underlying)"
        case .malformed(let path, let underlying):
            "The configuration at \(path) is not valid JSON: \(underlying)"
        }
    }
}
