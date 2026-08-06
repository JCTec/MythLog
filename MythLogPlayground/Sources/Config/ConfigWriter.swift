import Foundation

/// What happened when a change was saved.
///
/// # There is no "probably"
///
/// Three states, and the interface distinguishes all three. A setting that
/// *might* have taken effect is worse than one that refuses to change: the user
/// walks away believing something about their own machine that may not be true,
/// and this app's entire value is being believed.
enum ConfigWriteOutcome: Equatable, Sendable {
    /// Written, and nothing is holding an older copy. Already in effect.
    case written(at: Date)

    /// Written to disk, but a recorder is running with the previous copy in
    /// memory and will keep using it until it restarts.
    ///
    /// Not a failure — the file on disk is correct and permanent. It is a
    /// *timing* fact, and one the user has to be told or they will change a
    /// setting, watch nothing happen, and conclude the app is broken.
    case writtenPendingRecorderRestart(at: Date)

    /// Nothing on disk changed, and here is why.
    case refused(reason: String)

    var didWrite: Bool {
        switch self {
        case .written, .writtenPendingRecorderRestart: true
        case .refused: false
        }
    }

    var writtenAt: Date? {
        switch self {
        case .written(let at), .writtenPendingRecorderRestart(let at): at
        case .refused: nil
        }
    }
}

/// Reads, changes, and writes the installed configuration.
///
/// # Read–modify–write, never construct-and-write
///
/// Every save reads the file that is there, changes only what the user changed,
/// and writes the result. It never builds a config from defaults and saves that.
///
/// This is not fussiness. This build models six of the thirteen sections the
/// recorder writes — `session`, `filesystem`, `unifiedLog`, `notifications`,
/// `telegram`, `remoteCheckpoint` and `rules` are Waves 5–8 and are not
/// interpreted here at all. They survive in ``EngineConfig/unmodelled`` and are
/// re-emitted byte for byte. A save that dropped them would delete a user's
/// watched paths and alarm rules as a side effect of changing where a hash goes.
///
/// # Validated before anything is written
///
/// An invalid config can stop the recorder from starting, and a recorder that
/// does not start is a Mac that is silently not being recorded. So the
/// prospective config is validated *first*, and a validation error means nothing
/// on disk is touched.
struct ConfigWriter: Sendable {
    let configURL: URL
    var environment: SandboxEnvironment

    init(configURL: URL, environment: SandboxEnvironment = .current()) {
        self.configURL = configURL
        self.environment = environment
    }

    /// Applies `change` to the config on disk.
    ///
    /// - Parameters:
    ///   - recorderIsRunning: whether something currently holds an older copy in
    ///     memory. Affects only which successful outcome is reported — the write
    ///     happens either way, because the recorder never writes this file.
    ///   - now: injected so the reported time is testable.
    ///   - change: receives the config as it is on disk and returns the config
    ///     to write. Given the whole value rather than a keypath so a change can
    ///     depend on what is already there.
    func apply(
        recorderIsRunning: Bool,
        now: Date = .now,
        fileManager: sending FileManager = FileManager(),
        _ change: (EngineConfig) -> EngineConfig
    ) -> ConfigWriteOutcome {
        let existing: EngineConfig
        do {
            existing = try EngineConfig.load(from: configURL)
        } catch {
            // Refusing to write over a config that could not be read is the
            // whole point: the alternative replaces a file we do not understand
            // with one built from defaults, which is data loss dressed as a
            // repair.
            return .refused(
                reason: (error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }

        let updated = change(existing)

        // Nothing to do is a success, not a write. Rewriting an unchanged file
        // would churn its modification date, which is one of the things
        // `SegmentRecordCounting` and the recorder's own staleness checks watch.
        guard updated != existing else {
            return recorderIsRunning
                ? .writtenPendingRecorderRestart(at: now) : .written(at: now)
        }

        let issues = ConfigValidator.issues(in: updated, environment: environment)
            .filter { $0.severity == .error }
        guard issues.isEmpty else {
            return .refused(
                reason: issues.map { "\($0.field): \($0.message)" }.joined(separator: "\n\n"))
        }

        do {
            try updated.write(to: configURL, fileManager: fileManager)
        } catch {
            return .refused(
                reason: "The configuration could not be written to \(configURL.path): "
                    + ((error as? LocalizedError)?.errorDescription ?? String(describing: error)))
        }

        return recorderIsRunning ? .writtenPendingRecorderRestart(at: now) : .written(at: now)
    }
}
