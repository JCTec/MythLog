import Foundation
import OSLog

/// Diagnostic logging for MythLog's own behavior.
///
/// IMPORTANT: the subsystem is `com.jctec.mythlog.diagnostics`, NOT
/// `com.jctec.mythlog.custom`. The agent polls unified logs for the custom
/// subsystem to ingest user-emitted events; diagnostics must never match that
/// predicate, or the agent would record its own debug output into the ledger.
///
/// Conventions:
/// - `.error`: an operation failed and behavior degrades.
/// - `.warning`/`.notice`: unexpected but recovered (fallback taken, reattach).
/// - `.info`: sparse lifecycle milestones (started, stopped, rotated, installed).
/// - `.debug`: investigation detail; discarded by macOS unless streaming.
/// - Mark only non-content values `.public` (counts, durations, booleans,
///   error descriptions, event source/name). Event metadata, user paths, and
///   config values stay `.private` (the default).
///
/// View live: `log stream --predicate 'subsystem == "com.jctec.mythlog.diagnostics"' --level debug`
public enum MythLogDiagnostics {
    public static let subsystem = "com.jctec.mythlog.diagnostics"

    public static let agent = Logger(subsystem: subsystem, category: "agent")
    public static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    public static let ledger = Logger(subsystem: subsystem, category: "ledger")
    public static let anchor = Logger(subsystem: subsystem, category: "anchor")
    public static let rules = Logger(subsystem: subsystem, category: "rules")
    public static let notify = Logger(subsystem: subsystem, category: "notify")
    public static let sources = Logger(subsystem: subsystem, category: "sources")
    public static let launchAgent = Logger(subsystem: subsystem, category: "launchagent")
    public static let telegram = Logger(subsystem: subsystem, category: "telegram")
    public static let cli = Logger(subsystem: subsystem, category: "cli")
    public static let appShell = Logger(subsystem: subsystem, category: "appshell")
    public static let timeline = Logger(subsystem: subsystem, category: "timeline")
    public static let health = Logger(subsystem: subsystem, category: "health")
    public static let installer = Logger(subsystem: subsystem, category: "installer")

    /// Interval signposts for performance-sensitive paths (timeline layout,
    /// derivation). Use intervals instead of log lines in hot loops.
    public static let signposter = OSSignposter(subsystem: subsystem, category: "performance")
}
