import Foundation

/// **The** answer to "where does everything live".
///
/// # This is the single resolution point, and that is enforced
///
/// No other type in this app may derive a storage path. `Scripts/check-layering.sh`
/// fails the build if `"events.jsonl"`, a tilde-rooted path literal, or
/// `homeDirectoryForCurrentUser` appears anywhere else under `Sources/`.
///
/// The rule exists because of a specific shipped bug. In 1.0.0 the viewer
/// resolved the ledger from a bare default config carrying
/// `~/Library/Application Support/MythLog/events.jsonl`, while the recorder
/// wrote to the App Group container. Under the sandbox `~` expands to a
/// *process-private* container, so the two paths named different files. The
/// viewer found no ledger, concluded the recorder was not running, and said so —
/// for months, while the recorder was registered and healthy. Nothing crashed.
/// Nothing logged an error. A wrong path is indistinguishable from an empty
/// history unless something refuses to guess.
///
/// So: one type, one `base`, everything else derived from it, and a lint gate
/// that makes the second resolution point a build failure rather than a
/// discovery.
///
/// # Why it throws instead of falling back
///
/// When sandboxed and the container will not resolve, this raises
/// ``PlatformError/appGroupUnavailable(group:)``. There is no tilde fallback and
/// no sentinel path, because both turn "we do not know where the ledger is" into
/// "the ledger is empty" — the same failure in a different costume.
struct StorageLocations: Equatable, Sendable {
    /// Where the paths came from. Carried so the UI and the diagnostics can say
    /// *why* a location is what it is, rather than just printing it.
    enum Origin: Equatable, Sendable {
        /// Sandboxed: the App Group container shared by app, recorder, and CLI.
        case appGroupContainer(group: String)
        /// Unsandboxed: the historical `~/Library` layout, unchanged.
        case userLibrary
    }

    /// Everything below hangs off this and nothing else. Absolute, never
    /// tilde-rooted.
    let base: URL
    let origin: Origin

    var ledgerURL: URL { base.appendingPathComponent("events.jsonl") }
    var configURL: URL { base.appendingPathComponent("config.json") }
    var runtimeDirectory: URL { base.appendingPathComponent("runtime", isDirectory: true) }
    var spoolDirectory: URL { base.appendingPathComponent("spool", isDirectory: true) }
    var outboxDirectory: URL { base.appendingPathComponent("outbox", isDirectory: true) }

    /// Where the recorder keeps the ledger HMAC key. Beside the ledger, so a
    /// directory somebody copies is self-sufficient — see ``SecretStore``.
    var secretsDirectory: URL { base.appendingPathComponent("secrets", isDirectory: true) }
    var logDirectory: URL { logBase.appendingPathComponent("MythLog", isDirectory: true) }

    private let logBase: URL

    private init(base: URL, logBase: URL, origin: Origin) {
        self.base = base
        self.logBase = logBase
        self.origin = origin
    }

    /// Resolves every location from the environment.
    ///
    /// Synchronous and pure apart from the container lookup: this is a decision
    /// about paths, not I/O, and making it `async` would put a suspension point
    /// in front of a computation that does not wait for anything.
    static func resolve(
        environment: SandboxEnvironment,
        container: SharedContainer = .system,
        home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) throws -> StorageLocations {
        guard environment.isSandboxed else {
            let library = home.appendingPathComponent("Library", isDirectory: true)
            return StorageLocations(
                base: library
                    .appendingPathComponent("Application Support", isDirectory: true)
                    .appendingPathComponent("MythLog", isDirectory: true),
                logBase: library.appendingPathComponent("Logs", isDirectory: true),
                origin: .userLibrary
            )
        }

        // Throws rather than falling back. See the type's doc comment.
        let containerURL = try container.url()
        return StorageLocations(
            base: containerURL
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("MythLog", isDirectory: true),
            logBase: containerURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Logs", isDirectory: true),
            origin: .appGroupContainer(group: SharedContainer.groupIdentifier)
        )
    }

    /// Every place an install could be, most likely first.
    ///
    /// # A viewer cannot assume the recorder shares its sandbox
    ///
    /// ``resolve(environment:container:home:)`` answers "where do *my* files
    /// go". That is the right question for a process reading its own state and
    /// the wrong one for a process looking for somebody else's install — which
    /// is what this app does.
    ///
    /// This playground is unsandboxed, so `resolve` returns `~/Library/…`. The
    /// recorder people actually have is the App Store build, which *is*
    /// sandboxed and writes to the App Group container. Asking only our own
    /// convention finds nothing and reports "no install", on a Mac with a
    /// perfectly good one.
    ///
    /// That is the 1.0.0 bug pointed the other way: not a wrong path taken for a
    /// right one, but a right path never looked at. Both have the same symptom —
    /// a viewer confidently reporting an absence that is not there.
    ///
    /// The App Group container comes first because a sandboxed recorder is the
    /// shipping configuration; the Library layout is the historical unsandboxed
    /// one and is checked second.
    static func installedCandidates(
        container: SharedContainer = .system,
        home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> [StorageLocations] {
        var candidates = [StorageLocations]()

        // Resolvable from an unsandboxed process too: macOS hands back
        // `~/Library/Group Containers/<group>` without requiring the entitlement
        // to *read* it, which is exactly why this app can do its job at all.
        if let containerURL = try? container.url() {
            candidates.append(
                StorageLocations(
                    base: containerURL
                        .appendingPathComponent("Application Support", isDirectory: true)
                        .appendingPathComponent("MythLog", isDirectory: true),
                    logBase: containerURL
                        .appendingPathComponent("Library", isDirectory: true)
                        .appendingPathComponent("Logs", isDirectory: true),
                    origin: .appGroupContainer(group: SharedContainer.groupIdentifier)
                ))
        }

        let library = home.appendingPathComponent("Library", isDirectory: true)
        candidates.append(
            StorageLocations(
                base: library
                    .appendingPathComponent("Application Support", isDirectory: true)
                    .appendingPathComponent("MythLog", isDirectory: true),
                logBase: library.appendingPathComponent("Logs", isDirectory: true),
                origin: .userLibrary
            ))

        return candidates
    }

    /// The first candidate location that actually has something in it.
    ///
    /// - Parameter marker: the file whose presence means "an install lives
    ///   here" — the ledger when looking for history, the config when looking
    ///   for settings. They can be in different places when someone has moved
    ///   one by hand, and guessing which to test for would be a third resolution
    ///   rule.
    static func firstInstalled(
        containing marker: (StorageLocations) -> URL,
        container: SharedContainer = .system,
        home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        fileManager: FileManager = FileManager()
    ) -> StorageLocations? {
        installedCandidates(container: container, home: home)
            .first { fileManager.fileExists(atPath: marker($0).path) }
    }

    /// The iCloud Drive folder an unsandboxed build writes anchors into — the
    /// one visible in Finder, so a user can find an anchor and copy it
    /// somewhere safer.
    ///
    /// Here rather than in ``AnchorLocations`` because this file is the single
    /// place permitted to ask where home is, and `Scripts/check-layering.sh`
    /// enforces that. A second type resolving `~` is precisely the shape of the
    /// 1.0.0 bug, whatever it is resolving it for.
    static func iCloudDriveDirectory(
        home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> URL {
        home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
            .appendingPathComponent("MythLog", isDirectory: true)
    }

    /// Locations rooted at an arbitrary directory — for tests, and for opening a
    /// ledger the user picked by hand rather than the installed one.
    ///
    /// Named so it cannot be mistaken for the installed location at a call site.
    static func rooted(at directory: URL) -> StorageLocations {
        StorageLocations(
            base: directory,
            logBase: directory.appendingPathComponent("Logs", isDirectory: true),
            origin: .userLibrary
        )
    }

    /// A sentence for the UI: where these files are and why.
    var explanation: String {
        switch origin {
        case .appGroupContainer(let group):
            "Shared App Group container \(group), because this build runs under the App Sandbox "
                + "and every MythLog process must resolve the same files."
        case .userLibrary:
            "This user's Library folder, because this build does not run under the App Sandbox."
        }
    }
}
