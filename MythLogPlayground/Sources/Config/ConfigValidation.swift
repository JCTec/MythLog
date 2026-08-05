import Foundation

/// One thing wrong with a config, said plainly.
///
/// Validation *reports*; it never repairs. Silently correcting a user's config
/// is how a wrong path becomes invisible — the config on disk says one thing,
/// the program does another, and the two never disagree out loud.
struct ConfigIssue: Equatable, Sendable, Identifiable {
    enum Severity: String, Equatable, Sendable, Comparable {
        /// The config as written cannot work. Something will be wrong and it
        /// will not look wrong.
        case error
        /// It will work, but not the way the user probably expects.
        case warning

        private var rank: Int { self == .error ? 1 : 0 }
        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }
    }

    var id: String { "\(severity.rawValue):\(field)" }

    var severity: Severity
    var field: String
    var message: String
}

/// Checks a config against the environment it will actually run in.
///
/// # Why the environment is a parameter
///
/// Almost every rule here is conditional on the sandbox. `~/Library/...` is a
/// perfectly good path in an unsandboxed build and a silent catastrophe in a
/// sandboxed one, because `~` expands to a process-private container and the
/// recorder, the viewer, and the CLI each get a different file. A validator that
/// could not see the environment would have to either pass everything or fail
/// correct configs.
///
/// # Why it is synchronous
///
/// It is pure computation over values already in memory. Making it `async`
/// would add a suspension point in front of something that never waits.
enum ConfigValidator {

    static func issues(
        in config: EngineConfig,
        environment: SandboxEnvironment,
        container: SharedContainer = .system
    ) -> [ConfigIssue] {
        var issues = [ConfigIssue]()

        issues.append(contentsOf: schemaIssues(config))
        issues.append(contentsOf: storageIssues(config, environment: environment))
        issues.append(contentsOf: secretIssues(config))
        issues.append(contentsOf: heartbeatIssues(config))
        issues.append(contentsOf: anchorIssues(config, environment: environment, container: container))
        issues.append(contentsOf: unmodelledPathIssues(config, environment: environment))

        return issues.sorted {
            $0.severity == $1.severity ? $0.field < $1.field : $0.severity > $1.severity
        }
    }

    static func isUsable(_ config: EngineConfig, environment: SandboxEnvironment) -> Bool {
        !issues(in: config, environment: environment).contains { $0.severity == .error }
    }

    // MARK: - Rules

    private static func schemaIssues(_ config: EngineConfig) -> [ConfigIssue] {
        guard config.schemaVersion != 1 else { return [] }
        return [
            ConfigIssue(
                severity: .warning,
                field: "schemaVersion",
                message: "This config declares schema version \(config.schemaVersion); this build understands "
                    + "version 1. Sections it does not recognise are preserved unchanged, but not interpreted."
            )
        ]
    }

    /// The 1.0.0 rule.
    private static func storageIssues(
        _ config: EngineConfig, environment: SandboxEnvironment
    ) -> [ConfigIssue] {
        guard let storage = config.storage else { return [] }

        var issues = [ConfigIssue]()

        for (field, path) in storage.configuredPaths {
            guard isTildeRooted(path) else {
                if !path.hasPrefix("/") {
                    issues.append(
                        ConfigIssue(
                            severity: .error,
                            field: field,
                            message: "\"\(path)\" is a relative path. Storage paths must be absolute, because "
                                + "the recorder, the viewer, and mythlogctl do not share a working directory."
                        ))
                }
                continue
            }

            if environment.isSandboxed {
                issues.append(
                    ConfigIssue(
                        severity: .error,
                        field: field,
                        message: SandboxEnvironment.unavailableReason(
                            "\"\(path)\" begins with ~, which expands to this process's own private container "
                                + "rather than the shared one")
                            + " The recorder, the viewer, and mythlogctl would each resolve a different file, "
                            + "and the mismatch reads as an empty history rather than as an error. This build "
                            + "resolves storage through the App Group container and ignores this value."
                    ))
            } else {
                issues.append(
                    ConfigIssue(
                        severity: .warning,
                        field: field,
                        message: "\"\(path)\" begins with ~. It resolves correctly in this unsandboxed build, "
                            + "but the same config under the App Sandbox would point every process at a "
                            + "different file. This build resolves storage through StorageLocations regardless."
                    ))
            }
        }

        if let maximum = storage.maxLedgerFileBytes, maximum > 0, maximum < 64 * 1024 {
            issues.append(
                ConfigIssue(
                    severity: .warning,
                    field: "storage.maxLedgerFileBytes",
                    message: "Rotating every \(maximum) bytes produces a very large number of segments, each "
                        + "of which is verified separately. Verification stays correct but gets slower."
                ))
        }

        return issues
    }

    private static func secretIssues(_ config: EngineConfig) -> [ConfigIssue] {
        var issues = [ConfigIssue]()

        if config.secrets.allowDevelopmentFallbackKey {
            issues.append(
                ConfigIssue(
                    severity: .error,
                    field: "secrets.allowDevelopmentFallbackKey",
                    message: "A fallback HMAC key is enabled. A ledger signed with a key that can be derived "
                        + "rather than held proves nothing: anyone able to edit the file can recompute every "
                        + "hash after their edit. This must be false in any build a user relies on."
                ))
        }

        if config.secrets.hmacKeyAccount.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(
                ConfigIssue(
                    severity: .error,
                    field: "secrets.hmacKeyAccount",
                    message: "No keychain account is named, so the HMAC key cannot be found and nothing can "
                        + "be verified."
                ))
        }

        return issues
    }

    private static func heartbeatIssues(_ config: EngineConfig) -> [ConfigIssue] {
        var issues = [ConfigIssue]()
        let heartbeat = config.heartbeat

        if !heartbeat.enabled {
            issues.append(
                ConfigIssue(
                    severity: .warning,
                    field: "heartbeat.enabled",
                    message: "Heartbeats are off. Coverage gaps are detected from heartbeats that did not "
                        + "arrive, so with them disabled a recorder that was force-quit — which writes no stop "
                        + "record — leaves a silence indistinguishable from a quiet afternoon."
                ))
        }

        if heartbeat.intervalSeconds <= 0 {
            issues.append(
                ConfigIssue(
                    severity: .error,
                    field: "heartbeat.intervalSeconds",
                    message: "A heartbeat interval of \(heartbeat.intervalSeconds)s is not a duration."
                ))
        } else if heartbeat.intervalSeconds > 3600 {
            issues.append(
                ConfigIssue(
                    severity: .warning,
                    field: "heartbeat.intervalSeconds",
                    message: "At one heartbeat every \(Int(heartbeat.intervalSeconds))s, a gap has to last "
                        + "\(Int(heartbeat.gapThreshold / 60)) minutes before it can be detected at all."
                ))
        }

        return issues
    }

    private static func anchorIssues(
        _ config: EngineConfig,
        environment: SandboxEnvironment,
        container: SharedContainer
    ) -> [ConfigIssue] {
        var issues = [ConfigIssue]()
        let anchor = config.hashAnchor

        if !anchor.enabled {
            issues.append(
                ConfigIssue(
                    severity: .warning,
                    field: "hashAnchor.enabled",
                    message: "Anchoring is off. The chain still verifies record to record, but records "
                        + "removed from the end of the ledger become undetectable — a shortened chain "
                        + "verifies perfectly."
                ))
        }

        if anchor.destination == .directory, let directory = anchor.directory {
            if isTildeRooted(directory), environment.isSandboxed {
                issues.append(
                    ConfigIssue(
                        severity: .error,
                        field: "hashAnchor.directory",
                        message: SandboxEnvironment.unavailableReason(
                            "\"\(directory)\" begins with ~, which under the sandbox is a private container")
                            + " An anchor stored inside the container it is meant to protect is not evidence."
                    ))
            } else if container.contains(directory) {
                issues.append(
                    ConfigIssue(
                        severity: .error,
                        field: "hashAnchor.directory",
                        message: "The anchor directory is inside the App Group container, alongside the ledger "
                            + "it describes. Anyone able to truncate the ledger can rewrite the anchor too, so "
                            + "it proves nothing. Anchors belong outside this Mac's trust domain."
                    ))
            }
        }

        return issues
    }

    /// Sections this build does not model can still contain paths, and a tilde
    /// is worth mentioning wherever it appears — `filesystem.watchedPaths`
    /// under the sandbox watches a directory nothing writes to.
    private static func unmodelledPathIssues(
        _ config: EngineConfig, environment: SandboxEnvironment
    ) -> [ConfigIssue] {
        guard environment.isSandboxed else { return [] }

        return config.unmodelled
            .sorted { $0.key < $1.key }
            .flatMap { section, value in
                value.strings(prefix: section)
                    .filter { isTildeRooted($0.value) }
                    .map { entry in
                        ConfigIssue(
                            severity: .warning,
                            field: entry.path,
                            message: SandboxEnvironment.unavailableReason(
                                "\"\(entry.value)\" begins with ~, which resolves inside this process's own "
                                    + "container")
                                + " This build does not interpret this section, and preserves it unchanged."
                        )
                    }
            }
    }

    private static func isTildeRooted(_ path: String) -> Bool {
        path == "~" || path.hasPrefix("~/")
    }
}
