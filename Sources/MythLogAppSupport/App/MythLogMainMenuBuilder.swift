import AppKit

struct MythLogMainMenuBuildResult {
    var menu: NSMenu
    var viewItems: MythLogViewMenuItems
}

struct MythLogViewMenuItems {
    var showInspector: NSMenuItem
    var inspectorAutoOpen: NSMenuItem
    var inspectorSummaryHeader: NSMenuItem
}

struct MythLogMainMenuBuilder {
    let target: MythLogApplicationDelegate

    func build() -> MythLogMainMenuBuildResult {
        let mainMenu = NSMenu(title: "Main Menu")
        let viewMenu = viewMenuItem()

        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(viewMenu.item)
        mainMenu.addItem(timelineMenuItem())
        mainMenu.addItem(notificationsMenuItem())
        mainMenu.addItem(agentMenuItem())

        return MythLogMainMenuBuildResult(menu: mainMenu, viewItems: viewMenu.viewItems)
    }
}
