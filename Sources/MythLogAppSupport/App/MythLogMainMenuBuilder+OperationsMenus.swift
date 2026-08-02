import AppKit

extension MythLogMainMenuBuilder {
    func notificationsMenuItem() -> NSMenuItem {
        let factory = MythLogMenuItemFactory(target: target)
        let item = NSMenuItem()
        let menu = NSMenu(title: "Notifications")
        menu.autoenablesItems = false
        menu.addItem(
            factory.command(
                title: "Notification Status",
                action: #selector(MythLogApplicationDelegate.showNotificationDiagnostics(_:))
            ))
        menu.addItem(
            factory.command(
                title: "Enable Notifications...",
                action: #selector(MythLogApplicationDelegate.enableNotifications(_:))
            ))
        menu.addItem(
            factory.command(
                title: "Send Test Notification",
                action: #selector(MythLogApplicationDelegate.sendTestNotification(_:))
            ))
        menu.addItem(.separator())
        menu.addItem(
            factory.command(
                title: "Open System Notification Settings",
                action: #selector(MythLogApplicationDelegate.openNotificationSettings(_:))
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            factory.command(
                title: "Telegram Settings...",
                action: #selector(MythLogApplicationDelegate.showTelegramSettings(_:))
            )
        )
        item.submenu = menu
        return item
    }

    func agentMenuItem() -> NSMenuItem {
        let factory = MythLogMenuItemFactory(target: target)
        let item = NSMenuItem()
        let menu = NSMenu(title: "Recorder")
        menu.addItem(
            factory.command(
                title: "Install Recorder at Login...",
                action: #selector(MythLogApplicationDelegate.installAgent(_:))
            ))
        menu.addItem(
            factory.command(
                title: "Show Recorder Status",
                action: #selector(MythLogApplicationDelegate.showAgentStatus(_:))
            ))
        menu.addItem(
            factory.command(
                title: "Start or Restart Recorder",
                action: #selector(MythLogApplicationDelegate.restartAgent(_:))
            ))
        menu.addItem(
            factory.command(title: "Stop Recorder", action: #selector(MythLogApplicationDelegate.stopAgent(_:))))
        menu.addItem(
            factory.command(
                title: "Uninstall Recorder...",
                action: #selector(MythLogApplicationDelegate.uninstallAgent(_:))
            ))
        menu.addItem(.separator())
        menu.addItem(
            factory.command(
                title: "Watched Folders...",
                action: #selector(MythLogApplicationDelegate.showWatchedFolders(_:))
            ))
        menu.addItem(.separator())
        menu.addItem(
            factory.command(
                title: "Open Recorder Logs",
                action: #selector(MythLogApplicationDelegate.openAgentLogs(_:))
            ))
        menu.addItem(
            factory.command(title: "Reveal Ledger", action: #selector(MythLogApplicationDelegate.revealLedger(_:))))
        item.submenu = menu
        return item
    }
}
