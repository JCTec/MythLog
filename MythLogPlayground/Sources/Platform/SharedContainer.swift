import Foundation

/// Resolves the App Group container — the only directory the viewer, the
/// recorder helper, and `mythlogctl` can all read and write.
///
/// # Why this matters more than it looks
///
/// Under the sandbox each of those three processes gets its own *private*
/// container, and `~` expands into it. Three processes resolving
/// `~/Library/Application Support/MythLog/events.jsonl` get three different
/// files. That is the split-brain the App Group exists to prevent, and it is the
/// mechanism behind the 1.0.0 bug: the viewer read a ledger that existed, was
/// empty, and was not the one the recorder was writing.
///
/// The group identifier is `<TeamID>.com.jctec.mythlog.shared` and must match
/// the `com.apple.security.application-groups` entitlement in both
/// `Xcode/MythLog.entitlements` and `Xcode/MythLogHelper.entitlements`. Change
/// the team and all three change together.
struct SharedContainer: Sendable {
    /// Apple Developer team identifier. macOS requires the group id to carry it.
    static let teamIdentifier = "S8662L649U"
    static let groupSuffix = "com.jctec.mythlog.shared"

    static var groupIdentifier: String { "\(teamIdentifier).\(groupSuffix)" }

    /// How the container URL is obtained.
    ///
    /// A `@Sendable` closure rather than a `nonisolated(unsafe)` override
    /// variable: tests supply their own resolver by constructing a different
    /// value, so no global exists to be mutated, raced on, or left set by a
    /// failing test.
    private let resolver: @Sendable (String) -> URL?

    private init(resolver: @escaping @Sendable (String) -> URL?) {
        self.resolver = resolver
    }

    /// The real one. Uses a fresh `FileManager` rather than `.default`, which is
    /// shared process-wide and non-`Sendable`.
    static let system = SharedContainer { identifier in
        FileManager().containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Always resolves to `url`. For tests that need the sandboxed path on an
    /// unsandboxed machine.
    static func fixed(_ url: URL) -> SharedContainer {
        SharedContainer { _ in url }
    }

    /// Never resolves. Exercises the loud-failure branch, which cannot be
    /// reproduced by probing: macOS synthesises a Group Containers URL even for
    /// processes that are not entitled to one.
    static let unavailable = SharedContainer { _ in nil }

    /// - Throws: ``PlatformError/appGroupUnavailable(group:)`` when the container
    ///   cannot be resolved.
    ///
    /// There is deliberately no fallback. The shipping app returns a
    /// `/dev/null/...` sentinel path so that writes fail with `ENOTDIR`, which is
    /// clever but still turns a configuration problem into an I/O error several
    /// layers away from its cause. Throwing here names the actual problem at the
    /// point it is known.
    func url() throws -> URL {
        guard let url = resolver(Self.groupIdentifier) else {
            Diagnostics.storage.error(
                "\(SandboxEnvironment.unavailableReason("app group '\(Self.groupIdentifier)' resolved to nil"), privacy: .public)"
            )
            throw PlatformError.appGroupUnavailable(group: Self.groupIdentifier)
        }
        return url
    }

    /// Whether `path` lies inside the container. Used to decide which configured
    /// watch paths a sandboxed process could actually observe. Returns false when
    /// the container is unresolvable, so everything is treated as outside — the
    /// conservative answer.
    func contains(_ path: String) -> Bool {
        guard let container = try? url() else { return false }
        let normalised = URL(fileURLWithPath: path).standardizedFileURL.path
        let base = container.standardizedFileURL.path
        return normalised == base || normalised.hasPrefix(base + "/")
    }
}
