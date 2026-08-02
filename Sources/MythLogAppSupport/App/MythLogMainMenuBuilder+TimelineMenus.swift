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
        addEventSelectionItems(to: menu, factory: factory)
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

    /// Keyboard access to the canvas.
    ///
    /// Menu commands rather than bare arrow keys on the canvas: they work without Full Keyboard
    /// Access turned on, they never fight the search field for the same keypress, and — unlike a
    /// hidden gesture — the shortcuts are discoverable by reading the menu.
    private func addEventSelectionItems(to menu: NSMenu, factory: MythLogMenuItemFactory) {
        let previousEvent = factory.command(
            title: "Select Previous Event",
            action: #selector(MythLogApplicationDelegate.selectPreviousEvent(_:)),
            keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        )
        previousEvent.keyEquivalentModifierMask = [.option]

        let nextEvent = factory.command(
            title: "Select Next Event",
            action: #selector(MythLogApplicationDelegate.selectNextEvent(_:)),
            keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!)
        )
        nextEvent.keyEquivalentModifierMask = [.option]

        let oldestEvent = factory.command(
            title: "Select Oldest Event",
            action: #selector(MythLogApplicationDelegate.selectOldestEvent(_:)),
            keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        )
        oldestEvent.keyEquivalentModifierMask = [.command, .option]

        let newestEvent = factory.command(
            title: "Select Newest Event",
            action: #selector(MythLogApplicationDelegate.selectNewestEvent(_:)),
            keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!)
        )
        newestEvent.keyEquivalentModifierMask = [.command, .option]

        menu.addItem(previousEvent)
        menu.addItem(nextEvent)
        menu.addItem(oldestEvent)
        menu.addItem(newestEvent)
    }
}
