import Foundation

#if canImport(Security)
    import Security
#endif

/// A snapshot of this process's own code-signing entitlements.
///
/// # Why it is a snapshot
///
/// Entitlements are fixed at signing time and cannot change while the process
/// runs, so reading them once and carrying the result as a value is not a cache
/// — it is the accurate model. It also means there is no global to override:
/// tests construct ``declaring(_:)``. The shipping app instead exposes
/// `nonisolated(unsafe) static var overrideNetworkClient`, which is unsynchronised
/// process-wide mutable state describing something that is, in fact, immutable.
///
/// # What it is for
///
/// Attributing capability gaps. Telegram delivery under the sandbox needs
/// `com.apple.security.network.client`; if a build ships without it we want a
/// loud, attributed failure rather than a network error nobody can explain.
/// Reading uses the public `SecCode` API — no private SPI.
struct ProcessEntitlements: Equatable, Sendable {
    static let networkClientKey = "com.apple.security.network.client"

    private let booleans: [String: Bool]

    private init(booleans: [String: Bool]) {
        self.booleans = booleans
    }

    /// Reads the running binary's signature. Returns an empty set when the
    /// signature cannot be inspected — an unsigned development build, typically —
    /// which reads as "no entitlements", the conservative answer.
    static func current() -> ProcessEntitlements {
        #if canImport(Security)
            guard let entitlements = signedEntitlements() else {
                return ProcessEntitlements(booleans: [:])
            }
            return ProcessEntitlements(booleans: entitlements.compactMapValues { $0 as? Bool })
        #else
            return ProcessEntitlements(booleans: [:])
        #endif
    }

    /// A stated set, for tests and for describing a build that has not been
    /// signed yet.
    static func declaring(_ booleans: [String: Bool]) -> ProcessEntitlements {
        ProcessEntitlements(booleans: booleans)
    }

    static let none = ProcessEntitlements(booleans: [:])

    func bool(_ key: String) -> Bool? { booleans[key] }

    var hasNetworkClient: Bool { bool(Self.networkClientKey) ?? false }

    #if canImport(Security)
        private static func signedEntitlements() -> [String: Any]? {
            var code: SecCode?
            guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }

            var staticCode: SecStaticCode?
            guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else {
                return nil
            }

            var information: CFDictionary?
            let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
            guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
                let dictionary = information as? [String: Any]
            else {
                return nil
            }

            return dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        }
    #endif
}
