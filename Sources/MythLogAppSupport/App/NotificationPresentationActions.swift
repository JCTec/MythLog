import AppKit
import MythLogCore
import UserNotifications

extension MythLogApplicationDelegate: UNUserNotificationCenterDelegate {
    func configureNotificationPresentation() {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    @objc func enableNotifications(_ sender: Any?) {
        let service = MythLogNotificationService()
        Task {
            let result = await service.requestAuthorization()
            switch result {
            case .granted:
                showInfo(
                    title: "Notifications Enabled",
                    message: "macOS authorized MythLog to post local notifications. Live alarms are "
                        + "delivered by the background recorder, so also confirm \u{201C}MythLog Recorder\u{201D} "
                        + "is allowed under System Settings \u{203A} Notifications."
                )
            case .denied, .unavailable:
                presentNotificationOptInGuidance(result)
            }
        }
    }

    private func presentNotificationOptInGuidance(_ result: LocalNotificationAuthorization) {
        var message =
            "macOS has not authorized local notifications yet. The background recorder "
            + "(\u{201C}MythLog Recorder\u{201D}) posts these alerts, so enable it under "
            + "System Settings \u{203A} Notifications. Console and Telegram delivery are unaffected."
        if case .unavailable(let reason) = result {
            message = "\(reason)\n\n\(message)"
        }

        let openSettings = showInfoWithAction(
            title: "Turn On MythLog Notifications",
            message: message,
            actionButtonTitle: "Open Notification Settings"
        )
        if openSettings {
            MythLogSystemSettings.openNotifications()
        }
    }

    @objc func sendTestNotification(_ sender: Any?) {
        let service = MythLogNotificationService()
        Task {
            do {
                let result = try await service.sendTestNotification()
                showInfo(title: notificationResultTitle(result), message: notificationResultMessage(result))
            } catch {
                showError(title: "Notification Test Failed", error: error)
            }
        }
    }

    @objc func openNotificationSettings(_ sender: Any?) {
        MythLogSystemSettings.openNotifications()
    }

    private func notificationResultTitle(_ result: NotificationTestResult) -> String {
        result.delivery.succeeded ? "Test Notification Sent" : "Test Notification Failed"
    }

    private func notificationResultMessage(_ result: NotificationTestResult) -> String {
        [
            "Channel: \(result.delivery.channel)",
            "Succeeded: \(result.delivery.succeeded ? "yes" : "no")",
            "Detail: \(result.delivery.detail)",
            "Authorization: \(result.after.authorizationStatus)",
            "Ledger: \(result.deliveryRecord == nil ? "not recorded" : "recorded")",
        ].joined(separator: "\n")
    }
}
