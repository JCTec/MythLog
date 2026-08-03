import Foundation
import MythLogCore

struct MythLogNotificationService: Sendable {
    func authorizationSnapshot() async -> NotificationAuthorizationSnapshot {
        let notifier = await notifier()
        return await notifier.authorizationSnapshot()
    }

    func requestAuthorization() async -> LocalNotificationAuthorization {
        let notifier = await notifier()
        return await notifier.requestAuthorization()
    }

    func sendTestNotification(message: String = "MythLog notification system is working") async throws
        -> NotificationTestResult
    {
        let context = try await diagnosticContext()
        let runner = try NotificationTestRunner(
            config: context.config,
            hmacKey: context.hmacKey
        )
        return try await runner.run(
            message: message,
            origin: "MythLog.app notification diagnostics",
            notifier: notifier(config: context.config)
        )
    }

    static func testAlarm(message: String) -> Alarm {
        NotificationTestRunner.testAlarm(
            message: message,
            origin: "MythLog.app notification diagnostics"
        )
    }

    private func notifier() async -> ResilientLocalNotifier {
        let config = await loadConfig()
        return notifier(config: config)
    }

    private func notifier(config: MythLogConfig) -> ResilientLocalNotifier {
        return ResilientLocalNotifier(
            soundEnabled: config.notifications.sound,
            useAppleScriptFallback: config.notifications.appleScriptFallback
        )
    }

    private func diagnosticContext() async throws -> NotificationDiagnosticContext {
        try await MythLogBackgroundTask.throwing(priority: .utility) {
            let config = Self.loadConfig()
            return NotificationDiagnosticContext(
                config: config,
                hmacKey: try AgentFactory.hmacKey(
                    for: config,
                    secretStore: FileSecretStore.installedStore(for: config)
                )
            )
        }
    }

    private func loadConfig() async -> MythLogConfig {
        await MythLogBackgroundTask.value(priority: .utility) {
            Self.loadConfig()
        }
    }

    private static func loadConfig() -> MythLogConfig {
        let paths = MythLogInstallationPaths()
        guard FileManager.default.fileExists(atPath: paths.configURL.path),
            let config = try? MythLogConfig.load(from: paths.configURL)
        else {
            // installedDefault, not MythLogConfig(): the bare default's tilde
            // paths resolve outside the App Group container under the sandbox.
            return MythLogConfig.installedDefault(paths: paths)
        }

        return config
    }
}

private struct NotificationDiagnosticContext: Sendable {
    var config: MythLogConfig
    var hmacKey: Data
}
