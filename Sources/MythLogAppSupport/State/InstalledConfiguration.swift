import Foundation
import MythLogCore

/// Single resolution point for the storage paths the viewer app reads.
///
/// The viewer must read exactly the files the recorder writes. Under the App
/// Sandbox that is the **App Group container**, not `~/Library`: a tilde path
/// expands to each process's own private container, so the viewer and the
/// recorder would silently resolve different files and neither would ever see
/// the other's writes.
///
/// A bare `MythLogConfig()` carries the historical tilde defaults
/// (`~/Library/Application Support/MythLog/...`). Using it to locate the ledger
/// or the runtime status file is therefore correct unsandboxed and wrong under
/// the sandbox — and wrong *quietly*, because a missing file reads as "recorder
/// not running" rather than as an error. That produced a shipped bug where the
/// App Store build showed "Recorder Not Running" forever while the recorder was
/// registered and running normally.
///
/// Resolve through this type instead of constructing paths from
/// `MythLogConfig()`. It prefers the config written at install time and falls
/// back to `MythLogConfig.installedDefault(paths:)`, which is container-aware,
/// never to the raw tilde defaults.
enum InstalledConfiguration {
    /// The recorder's LaunchAgent label, and the key the installation paths are
    /// derived from. Matches `MythLogInstallationPaths`' own default.
    static let defaultLabel = "com.jctec.mythlog.agent"

    /// Installation paths for the recorder, sandbox-aware.
    static func paths(label: String = defaultLabel) -> MythLogInstallationPaths {
        MythLogInstallationPaths(label: label)
    }

    /// The effective config: the one written at install time when it is readable,
    /// otherwise the container-aware default for this environment.
    ///
    /// Never falls back to `MythLogConfig()`, whose tilde paths point outside the
    /// App Group container under the sandbox.
    static func config(label: String = defaultLabel) -> MythLogConfig {
        let paths = paths(label: label)
        if let installed = try? MythLogConfig.load(from: paths.configURL) {
            return installed
        }
        return MythLogConfig.installedDefault(paths: paths)
    }

    /// Location of the ledger the recorder appends to.
    static func ledgerURL(label: String = defaultLabel) -> URL {
        PathResolver.fileURL(config(label: label).storage.ledgerPath)
    }

    /// Location of the runtime status file the recorder heartbeats into.
    static func statusURL(label: String = defaultLabel) -> URL {
        PathResolver.fileURL(config(label: label).storage.runtimeDirectory)
            .appendingPathComponent("status.json")
    }
}
