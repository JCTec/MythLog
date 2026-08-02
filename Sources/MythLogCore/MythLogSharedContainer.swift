import Foundation

/// Resolves the App Group container that holds every piece of shared MythLog
/// state under the sandbox.
///
/// The viewer app, the recorder login-item helper, and `mythlogctl` each run in
/// their own *private* sandbox container. The only directory all three can read
/// and write in common is the App Group container. So under the sandbox the
/// ledger, config, secrets, runtime status, outbox, and the event spool must all
/// live here — resolving them into any private container would give three
/// processes three different ledgers (the "split-brain" P1/P2 forbid).
///
/// The group identifier is `<TeamID>.com.jctec.mythlog.shared`, matching the
/// `com.apple.security.application-groups` entitlement in both
/// `Xcode/MythLog.entitlements` and `Xcode/MythLogHelper.entitlements`. If the
/// team changes, update this constant and both entitlements together.
public enum MythLogSharedContainer {
    /// Apple Developer team identifier (`DEVELOPMENT_TEAM` in project.yml). The
    /// App Group id is prefixed with it, as macOS requires.
    public static let teamIdentifier = "S8662L649U"

    /// Suffix shared with the entitlement files.
    public static let groupSuffix = "com.jctec.mythlog.shared"

    /// Fully-qualified App Group identifier passed to
    /// `containerURL(forSecurityApplicationGroupIdentifier:)`.
    public static var groupIdentifier: String {
        "\(teamIdentifier).\(groupSuffix)"
    }

    /// Test seam. When non-nil, `containerURL()` returns this instead of probing
    /// the real App Group container, letting tests exercise the sandboxed path on
    /// an unsandboxed machine. Reset to `nil` to restore real resolution.
    nonisolated(unsafe) public static var overrideContainerURL: URL?

    /// Test seam. When true, `containerURL()` throws `appGroupUnavailable` as if
    /// the real container resolution returned nil, so the loud attributed-failure
    /// path can be exercised deterministically (macOS synthesizes a Group
    /// Containers URL even for unentitled processes, so the nil case cannot be
    /// reproduced by probing alone).
    nonisolated(unsafe) public static var overrideForceUnavailable = false

    /// Resolves the App Group container URL.
    ///
    /// Throws `MythLogError.appGroupUnavailable` when the container cannot be
    /// resolved — the loud, attributed failure that replaces any silent fallback
    /// to a private container.
    public static func containerURL() throws -> URL {
        if overrideForceUnavailable {
            MythLogDiagnostics.installer.error(
                "\(SandboxEnvironment.unavailableReason("app group '\(Self.groupIdentifier)' container is nil"), privacy: .public)"
            )
            throw MythLogError.appGroupUnavailable(groupIdentifier)
        }
        if let overrideContainerURL {
            return overrideContainerURL
        }
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            MythLogDiagnostics.installer.error(
                "\(SandboxEnvironment.unavailableReason("app group '\(Self.groupIdentifier)' container is nil"), privacy: .public)"
            )
            throw MythLogError.appGroupUnavailable(groupIdentifier)
        }
        return url
    }

    /// Whether `path` resolves inside the App Group container. Used to decide
    /// which configured watch paths a sandboxed agent can actually observe (only
    /// container-relative ones). Returns false when the container is unresolvable,
    /// so every path is treated as outside.
    public static func isInsideContainer(_ path: String) -> Bool {
        guard let container = try? containerURL() else {
            return false
        }
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        let base = container.standardizedFileURL.path
        return normalized == base || normalized.hasPrefix(base + "/")
    }

    /// Base directory holding all shared MythLog state under the sandbox:
    /// `<App Group container>/Application Support/MythLog`.
    public static func storageDirectory() throws -> URL {
        try containerURL()
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("MythLog", isDirectory: true)
    }

    /// Obviously-invalid base used only when the process is sandboxed but the
    /// group container cannot be resolved. Any write beneath it fails immediately
    /// with `ENOTDIR`, so a misconfigured sandboxed build fails loudly instead of
    /// silently writing into the wrong (private) container. Install and agent
    /// startup guard the container explicitly and surface
    /// `MythLogError.appGroupUnavailable` before reaching real I/O.
    public static let unresolvedSentinelDirectory = URL(fileURLWithPath: "/dev/null", isDirectory: true)
        .appendingPathComponent("com.jctec.mythlog.app-group-unavailable", isDirectory: true)
}
