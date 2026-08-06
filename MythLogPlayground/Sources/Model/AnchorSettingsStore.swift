import Foundation

/// The result of saving, as the interface states it.
///
/// Model vocabulary rather than ``ConfigWriteOutcome``, because `DesignSystem/`
/// may reference view models and nothing else — and because the sentence a
/// person reads is a product decision, not a detail of the file format.
struct SettingsSaveResult: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case saved
        /// On disk and permanent, but a running recorder still holds the old
        /// copy. A timing fact, not a failure.
        case savedPendingRecorderRestart
        /// Nothing on disk changed.
        case refused
    }

    var kind: Kind
    var at: Date?
    var message: String

    var isSaved: Bool { kind != .refused }
}

/// Loads and saves the anchor section of the installed configuration.
///
/// # Which config, and why that one
///
/// The *installed* one — the config the recorder reads — not the config beside
/// whatever ledger happens to be open. Changing where anchors go for a
/// copy of a ledger in `/tmp` would mean nothing: the recorder reads the
/// installed config and no other. Pointing this at the open ledger would produce
/// a setting that appears to save and changes nothing, which is the exact
/// failure `docs/CONFIG_OWNERSHIP.md` exists to rule out.
///
/// # Synchronous, deliberately
///
/// One small local file. `StorageLocations` guarantees it is in the App Group
/// container or the user's Library — never a network volume, never somewhere the
/// user picked — so there is no wait to represent. Making it `async` would put a
/// suspension point in front of a couple of microseconds, which is the same
/// mistake as making the hash chain `async`.
struct AnchorSettingsStore: Sendable {
    /// `nil` when no install could be resolved at all — a sandboxed build whose
    /// App Group container is unavailable. Distinct from "resolved, but there is
    /// no config file there yet".
    let locations: StorageLocations?
    var environment: SandboxEnvironment

    init(environment: SandboxEnvironment = .current(), container: SharedContainer = .system) {
        self.environment = environment
        // The install that actually exists, which need not be where *this*
        // process would put one: the playground is unsandboxed and the shipping
        // recorder is not. See
        // ``StorageLocations/installedCandidates(container:home:)``.
        self.locations = StorageLocations.firstInstalled(containing: \.configURL, container: container)
    }

    /// For tests, and for pointing at an install other than this Mac's.
    init(locations: StorageLocations?, environment: SandboxEnvironment = .unsandboxed) {
        self.locations = locations
        self.environment = environment
    }

    var configURL: URL? { locations?.configURL }

    /// Where the change would be written, for the interface to show before
    /// anyone presses anything.
    var targetDescription: String {
        guard let configURL else {
            return "No MythLog install could be found on this Mac."
        }
        return configURL.path
    }

    /// Whether saving is possible at all. False when there is no install, which
    /// is a normal state on a machine used only to look at exported ledgers.
    var canSave: Bool {
        guard let configURL else { return false }
        return FileManager().fileExists(atPath: configURL.path)
    }

    /// The anchor settings as configured, or `nil` when there is no config to
    /// read. `nil` is not "the defaults" — see ``EngineConfig``.
    func load() -> AnchorSettings? {
        guard let configURL, let config = try? EngineConfig.load(from: configURL) else { return nil }
        return AnchorSettings(config: config.hashAnchor)
    }

    /// The heartbeat interval the install is configured with, which sets how
    /// stale a recorder status file may be before it stops counting.
    func heartbeatInterval() -> TimeInterval {
        guard let configURL, let config = try? EngineConfig.load(from: configURL) else {
            return HeartbeatConfig().intervalSeconds
        }
        return config.heartbeat.intervalSeconds
    }

    /// Whether something currently holds an older copy of the config in memory.
    func isRecorderRunning(now: Date = .now) -> Bool {
        guard let locations else { return false }
        return RecorderPresence(locations: locations, heartbeatInterval: heartbeatInterval())
            .isRecorderRunning(now: now)
    }

    /// Writes the anchor settings, preserving every other key.
    func save(_ settings: AnchorSettings, now: Date = .now) -> SettingsSaveResult {
        guard let configURL else {
            return SettingsSaveResult(
                kind: .refused, at: nil,
                message: "There is no MythLog install on this Mac to save into. "
                    + "Anchor settings belong to an install, not to a ledger file.")
        }

        let running = isRecorderRunning(now: now)
        let outcome = ConfigWriter(configURL: configURL, environment: environment)
            .apply(recorderIsRunning: running, now: now) { existing in
                // Read–modify–write: only `hashAnchor` is touched. Every other
                // section, including the seven this build does not model, is
                // carried through untouched.
                var updated = existing
                updated.hashAnchor = settings.applied(to: existing.hashAnchor)
                return updated
            }

        return Self.describe(outcome, configURL: configURL)
    }

    private static func describe(_ outcome: ConfigWriteOutcome, configURL: URL) -> SettingsSaveResult {
        switch outcome {
        case .written(let at):
            return SettingsSaveResult(
                kind: .saved, at: at,
                message: "Saved to \(configURL.path). No recorder is running, so this is already in effect.")

        case .writtenPendingRecorderRestart(let at):
            return SettingsSaveResult(
                kind: .savedPendingRecorderRestart, at: at,
                message: "Saved to \(configURL.path). A recorder is running and is still using the "
                    + "settings it read when it started — it will pick this up the next time it starts. "
                    + "This build cannot restart it for you.")

        case .refused(let reason):
            return SettingsSaveResult(
                kind: .refused, at: nil,
                message: "Nothing was changed. \(reason)")
        }
    }
}

extension AnchorSettings {
    /// These settings written onto an existing anchor config.
    ///
    /// Takes the existing value rather than building a fresh one so fields this
    /// interface does not expose — `anchorEveryHeartbeats` — keep whatever the
    /// user or the installer put there.
    func applied(to existing: HashAnchorConfig) -> HashAnchorConfig {
        var updated = existing
        updated.enabled = isEnabled
        updated.destination = choice.kind
        // Only overwritten when there is something to write. Clearing a
        // perfectly good folder path because the user is currently looking at
        // the iCloud option would be a change they did not ask for.
        if let chosenDirectory, !chosenDirectory.isEmpty {
            updated.directory = chosenDirectory
        }
        return updated
    }
}
