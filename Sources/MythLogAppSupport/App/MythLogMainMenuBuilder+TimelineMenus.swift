import AppKit

extension MythLogMainMenuBuilder {
    func viewMenuItem() -> (item: NSMenuItem, viewItems: MythLogViewMenuItems) {
        let factory = MythLogMenuItemFactory(target: target)
        let item = NSMenuItem()
        let menu = NSMenu(title: "View")
        menu.delegate = target

        let showInspector = factory.command(
            title: "Show Inspector",
            action: #selector(MythLogApplicationDelegate.toggleInspector(_:)),
            keyEquivalent: "i"
        )
        showInspector.keyEquivalentModifierMask = [.command, .option]

        let autoOpenInspector = factory.command(
            title: "Open Inspector When Selecting Events",
            action: #selector(MythLogApplicationDelegate.toggleInspectorAutoOpen(_:)),
            keyEquivalent: ""
        )

        let showInspectorSummaryHeader = factory.command(
            title: "Show Pinned Event Summary",
            action: #selector(MythLogApplicationDelegate.toggleInspectorSummaryHeader(_:)),
            keyEquivalent: ""
        )

        menu.addItem(showInspector)
        menu.addItem(autoOpenInspector)
        menu.addItem(
            factory.command(
                title: "Show Ledger Integrity",
                action: #selector(MythLogApplicationDelegate.showLedgerIntegrity(_:))
            ))
        menu.addItem(.separator())
        menu.addItem(showInspectorSummaryHeader)
        item.submenu = menu

        return (
            item,
            MythLogViewMenuItems(
                showInspector: showInspector,
                inspectorAutoOpen: autoOpenInspector,
                inspectorSummaryHeader: showInspectorSummaryHeader
            )
        )
    }

    func timelineMenuItem() -> NSMenuItem {
        let factory = MythLogMenuItemFactory(target: target)
        let item = NSMenuItem()
        let menu = NSMenu(title: "Timeline")
        menu.addItem(
            factory.command(
                title: TimeRangePreset.last15Minutes.menuTitle,
                action: #selector(MythLogApplicationDelegate.showLast15Minutes(_:))
            ))
        menu.addItem(
            factory.command(
                title: TimeRangePreset.lastHour.menuTitle,
                action: #selector(MythLogApplicationDelegate.showLastHour(_:))
            ))
        menu.addItem(
            factory.command(
                title: TimeRangePreset.last6Hours.menuTitle,
                action: #selector(MythLogApplicationDelegate.showLast6Hours(_:))
            ))
        menu.addItem(
            factory.command(
                title: TimeRangePreset.last24Hours.menuTitle,
                action: #selector(MythLogApplicationDelegate.showLast24Hours(_:))
            ))
        menu.addItem(
            factory.command(
                title: TimeRangePreset.last7Days.menuTitle,
                action: #selector(MythLogApplicationDelegate.showLast7Days(_:))
            ))
        menu.addItem(.separator())
        menu.addItem(
            factory.command(
                title: "Zoom In",
                action: #selector(MythLogApplicationDelegate.zoomIn(_:)),
                keyEquivalent: "+"
            ))
        menu.addItem(
            factory.command(
                title: "Zoom Out",
                action: #selector(MythLogApplicationDelegate.zoomOut(_:)),
                keyEquivalent: "-"
            ))
        item.submenu = menu
        return item
    }
}
