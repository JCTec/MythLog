import Foundation

/// What the recorder last said about itself.
///
/// The recorder writes `runtime/status.json` as it runs. This app only ever
/// reads it — a viewer that wrote to the recorder's status file would be
/// inventing evidence about a process it does not control.
///
/// Only the fields this build actually uses are modelled. The rest of the
/// recorder's status schema is large, changes on its own schedule, and decoding
/// a field in order to ignore it is a way to fail on a file that is fine.
struct RecorderStatus: Decodable, Equatable, Sendable {
    enum State: String, Decodable, Equatable, Sendable {
        case starting
        case running
        case stopping
        case stopped
        case degraded

        /// Whether a process is expected to be alive and holding a config in
        /// memory. `stopping` counts: it has not let go yet.
        var isLive: Bool {
            switch self {
            case .starting, .running, .stopping, .degraded: true
            case .stopped: false
            }
        }
    }

    var state: State
    var generatedAt: Date
    var processID: Int32?

    private enum CodingKeys: String, CodingKey {
        case state, generatedAt, processID
    }
}

/// Reads the recorder's status file, and decides whether to believe it.
///
/// # This is a hint, and is treated as one
///
/// Nothing depends on it for correctness. `config.json` is written atomically
/// whether or not a recorder is running, because the recorder never writes that
/// file — see `docs/CONFIG_OWNERSHIP.md`. What this answers is a narrower
/// question: *does some process currently hold an older copy of the config in
/// memory?* Getting it wrong costs a sentence of interface copy, never a write.
struct RecorderPresence: Sendable {
    /// How stale a status file may be before it stops counting as evidence that
    /// anything is running.
    ///
    /// Judged against the heartbeat interval rather than a constant, for the
    /// same reason coverage gaps are: the heartbeat is what determines how often
    /// the file is refreshed. Three missed refreshes means the process is gone,
    /// and a force-quit recorder leaves its last status file behind for ever —
    /// so a stale file must read as "not running", or the interface would
    /// promise a restart that is never coming.
    static let missedRefreshesBeforeStale = 3.0

    var statusURL: URL
    var heartbeatInterval: TimeInterval

    init(locations: StorageLocations, heartbeatInterval: TimeInterval) {
        self.statusURL = locations.runtimeDirectory.appendingPathComponent("status.json")
        self.heartbeatInterval = heartbeatInterval
    }

    init(statusURL: URL, heartbeatInterval: TimeInterval) {
        self.statusURL = statusURL
        self.heartbeatInterval = heartbeatInterval
    }

    var stalenessThreshold: TimeInterval {
        max(heartbeatInterval, 1) * Self.missedRefreshesBeforeStale
    }

    /// The recorder's last word, or `nil` when there is no readable status file.
    func status(fileManager: FileManager = FileManager()) -> RecorderStatus? {
        guard fileManager.fileExists(atPath: statusURL.path),
            let data = try? Data(contentsOf: statusURL)
        else {
            return nil
        }
        return try? CanonicalJSON.decode(RecorderStatus.self, from: data)
    }

    /// Whether a recorder is running *now*, as far as anything here can tell.
    ///
    /// - Parameter now: injected so the staleness rule is testable without
    ///   waiting.
    func isRecorderRunning(now: Date = .now, fileManager: FileManager = FileManager()) -> Bool {
        guard let status = status(fileManager: fileManager), status.state.isLive else { return false }
        return now.timeIntervalSince(status.generatedAt) <= stalenessThreshold
    }
}
