import AppKit

extension MythLogMainMenuBuilder {
    func appMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "MythLog")
        menu.addItem(
            NSMenuItem(
                title: "About MythLog", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit MythLog", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.submenu = menu
        return item
    }

    func fileMenuItem() -> NSMenuItem {
        let factory = MythLogMenuItemFactory(target: target)
        let item = NSMenuItem()
        let menu = NSMenu(title: "File")
        menu.autoenablesItems = false
        let showTimeline = factory.command(
            title: "Show Timeline",
            action: #selector(MythLogApplicationDelegate.showTimelineMenuAction(_:)),
            keyEquivalent: "0"
        )
        showTimeline.isEnabled = true
        menu.addItem(showTimeline)
        menu.addItem(.separator())
        let exportProof = factory.shiftCommand(
            title: "Export Proof Bundle...",
            action: #selector(MythLogApplicationDelegate.exportProofBundle(_:)),
            keyEquivalent: "p"
        )
        exportProof.isEnabled = true
        menu.addItem(exportProof)
        item.submenu = menu
        return item
    }

    func editMenuItem() -> NSMenuItem {
        let factory = MythLogMenuItemFactory(target: target)
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")
        menu.addItem(
            factory.shiftCommand(
                title: "Copy Selected Event as CSV",
                action: #selector(MythLogApplicationDelegate.copySelectedCSV(_:)),
                keyEquivalent: "C"
            ))
        menu.addItem(
            factory.shiftCommand(
                title: "Copy Visible Events as CSV",
                action: #selector(MythLogApplicationDelegate.copyVisibleCSV(_:)),
                keyEquivalent: "E"
            )
        )
        item.submenu = menu
        return item
    }
}
