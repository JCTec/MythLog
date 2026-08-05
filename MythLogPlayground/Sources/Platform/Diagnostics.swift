import Foundation
import OSLog

/// MythLog's logging about its own behaviour.
///
/// # The subsystem is load-bearing
///
/// It is `com.jctec.mythlog.diagnostics`, and it must never be
/// `com.jctec.mythlog.custom`. The recorder polls the unified log for the
/// *custom* subsystem in order to ingest user-emitted events into the ledger. If
/// diagnostics shared that subsystem the recorder would ingest its own debug
/// output as user events — a feedback loop that writes noise into the one file
/// whose value is that it is trustworthy.
///
/// # Conventions
///
/// - `.error` — an operation failed and behaviour is degraded.
/// - `.notice` — unexpected but recovered.
/// - `.info` — sparse lifecycle milestones.
/// - `.debug` — investigation detail; macOS discards it unless streaming.
///
/// Only non-content values are marked `.public`: counts, durations, booleans,
/// error descriptions, event source and name. Paths, metadata, and config values
/// stay private, which is the default.
///
/// `Logger` is a `Sendable` value type, so these `static let`s are shared state
/// with no mutability — the thing that made the shipping app's `DateFormatter`
/// statics a problem does not apply.
///
/// Watch live:
/// `log stream --predicate 'subsystem == "com.jctec.mythlog.diagnostics"' --level debug`
enum Diagnostics {
    static let subsystem = "com.jctec.mythlog.diagnostics"

    /// The subsystem the recorder *ingests*. Named here only so the distinction
    /// is visible at the point someone would be tempted to reuse it.
    static let ingestedSubsystem = "com.jctec.mythlog.custom"

    static let ledger = Logger(subsystem: subsystem, category: "ledger")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let config = Logger(subsystem: subsystem, category: "config")
    static let timeline = Logger(subsystem: subsystem, category: "timeline")
}
