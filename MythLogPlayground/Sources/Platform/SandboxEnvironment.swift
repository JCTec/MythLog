import Foundation

/// Whether this process runs under the macOS App Sandbox, and the one phrasing
/// used whenever the sandbox is why something cannot happen.
///
/// # Why this is a value, not a global
///
/// The shipping app spells this as an `enum` with static computed properties and
/// a `nonisolated(unsafe) static var overrideIsSandboxed` that tests reach in and
/// mutate. Under Swift 6 that is process-wide mutable state with no
/// synchronisation; the justification given — "only mutated from single-threaded
/// test setup" — is a convention rather than a mechanism, which is exactly what
/// `nonisolated(unsafe)` is documented as *not* being for.
///
/// Making it a `Sendable` value removes the problem instead of annotating past
/// it. Production code calls ``current()`` once and passes the result down;
/// tests construct ``sandboxed(containerIdentifier:)`` or ``unsandboxed``
/// directly. There is no global to override, so there is nothing to leak between
/// tests and nothing to race on.
struct SandboxEnvironment: Equatable, Sendable {
    /// The environment variable macOS sets on every App-Sandboxed process. Its
    /// *presence* is the signal; its value is the container id.
    static let containerVariable = "APP_SANDBOX_CONTAINER_ID"

    /// The uniform prefix on every "the sandbox forbids this" message. Grep for
    /// this exact string to find every attributed-failure surface in the app.
    ///
    /// One vocabulary, deliberately: a capability that *cannot run* must never
    /// be indistinguishable from a capability that *found nothing*.
    static let unavailablePrefix = "unavailable under App Sandbox"

    let isSandboxed: Bool
    let containerIdentifier: String?

    private init(isSandboxed: Bool, containerIdentifier: String?) {
        self.isSandboxed = isSandboxed
        self.containerIdentifier = containerIdentifier
    }

    /// Reads the real environment. Called once, at startup, and passed down.
    static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> SandboxEnvironment {
        guard let identifier = environment[containerVariable] else {
            return .unsandboxed
        }
        return SandboxEnvironment(isSandboxed: true, containerIdentifier: identifier)
    }

    static let unsandboxed = SandboxEnvironment(isSandboxed: false, containerIdentifier: nil)

    static func sandboxed(containerIdentifier: String = "com.jctec.mythlog") -> SandboxEnvironment {
        SandboxEnvironment(isSandboxed: true, containerIdentifier: containerIdentifier)
    }

    /// Renders as `"unavailable under App Sandbox: <detail>"`, so logs, ledger
    /// events, config-validation issues and UI copy all say the same thing.
    static func unavailableReason(_ detail: String) -> String {
        "\(unavailablePrefix): \(detail)."
    }
}
