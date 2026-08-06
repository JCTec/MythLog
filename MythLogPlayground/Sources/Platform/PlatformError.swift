import Foundation

/// Failures in working out *where things are* and *what this process may do*.
///
/// Every case here exists so that a capability which cannot run says so. The
/// alternative — returning a plausible-looking path that nothing writes to — is
/// how the 1.0.0 bug shipped: the viewer reported "Recorder Not Running" for
/// months while the recorder was healthy, because a silently-wrong path reads
/// exactly like an empty ledger.
enum PlatformError: Error, Equatable, LocalizedError, Sendable {
    /// The App Group container could not be resolved while sandboxed. Never
    /// recovered from, never substituted.
    case appGroupUnavailable(group: String)
    case entitlementsUnreadable(detail: String)
    /// The place anchors were meant to go cannot be resolved right now. Never
    /// recovered from by writing somewhere else — an anchor in the wrong place
    /// looks like protection that is on.
    case anchorDestinationUnavailable(detail: String)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable(let group):
            SandboxEnvironment.unavailableReason("the app group container '\(group)' could not be resolved")
                + " Confirm the App Groups capability and provisioning for this signed build."
        case .entitlementsUnreadable(let detail):
            "This process's own code-signing entitlements could not be read: \(detail)"
        case .anchorDestinationUnavailable(let detail):
            "Anchors cannot be written: \(detail). Nothing has been written elsewhere — an anchor in the "
                + "wrong place would look like protection that is on."
        }
    }
}
