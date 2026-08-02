import AppKit

extension MythLogApplicationDelegate {
    func configureMainMenu() {
        let menuBuild = MythLogMainMenuBuilder(target: self).build()

        NSApplication.shared.mainMenu = menuBuild.menu
        showInspectorMenuItem = menuBuild.viewItems.showInspector
        inspectorAutoOpenMenuItem = menuBuild.viewItems.inspectorAutoOpen
        inspectorSummaryHeaderMenuItem = menuBuild.viewItems.inspectorSummaryHeader
        refreshInspectorMenuState()
    }
}
