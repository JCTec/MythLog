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

    /// Names a directory to use as the container instead of asking macOS, or —
    /// when empty — declares that this process has no shared container at all.
    ///
    /// # Why an override exists, and why it is not a convenience
    ///
    /// Reading another application's group container is gated by TCC: the first
    /// time this app opens a file in `~/Library/Group Containers/<group>/`,
    /// macOS puts up *"MythLog would like to access data from other apps"* and
    /// blocks the read in the kernel until somebody answers.
    ///
    /// That is correct behaviour, and it is fatal to a test run twice over.
    /// TCC records its answer against the app's **code-signing identity**, and
    /// this playground is signed ad-hoc — the identity changes with every
    /// rebuild, so the answer never applies to the binary that asked. Worse,
    /// under `xcodebuild test` the test host puts up that dialog with nobody in
    /// front of it: the read blocks forever, the runner never connects, and the
    /// failure reads as *"The test runner hung before establishing connection"*,
    /// which names neither the app, the file, nor the permission.
    ///
    /// So the test scheme sets this, and a test run resolves a directory of its
    /// own. That is not merely a workaround for a dialog. This app is run on
    /// other people's Macs for design work, and the same rule that makes
    /// discovery an *offer* rather than a load — see ``LedgerDiscovery`` — says
    /// a test suite has no business reading somebody's real config and history
    /// in order to check its own arithmetic.
    static let containerOverrideKey = "MYTHLOG_CONTAINER"

    /// The real one. Uses a fresh `FileManager` rather than `.default`, which is
    /// shared process-wide and non-`Sendable`.
    ///
    /// The environment is consulted per resolution rather than captured once:
    /// nothing here should behave differently depending on how early it was
    /// first asked.
    static let system = SharedContainer { identifier in
        if let override = ProcessInfo.processInfo.environment[containerOverrideKey] {
            // Empty means "no container", which is a real state — a Mac with no
            // MythLog installed — and the one a test run should be in.
            return override.isEmpty ? nil : URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager().containerURL(forSecurityApplicationGroupIdentifier: identifier)
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
