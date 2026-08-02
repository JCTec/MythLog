import AppKit

@MainActor
public enum MythLogViewerApplication {
    private static var delegate: MythLogApplicationDelegate?

    public static func main() {
        let app = NSApplication.shared
        let delegate = MythLogApplicationDelegate()
        Self.delegate = delegate

        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class MythLogApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let store = TimelineStore()
    let healthStore = AgentHealthStore()
    var window: NSWindow?
    var showInspectorMenuItem: NSMenuItem?
    var inspectorAutoOpenMenuItem: NSMenuItem?
    var inspectorSummaryHeaderMenuItem: NSMenuItem?

    let launchAgentLabel = "com.jctec.mythlog.agent"

    let watchedFolders = WatchedFolderBookmarks()
    lazy var watchService = WatchService(bookmarks: watchedFolders, label: launchAgentLabel)
    var watchedFoldersWindowController: WatchedFoldersWindowController?

    var agentInstaller: MythLogAgentInstaller {
        MythLogAgentInstaller(launchAgentLabel: launchAgentLabel)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureNotificationPresentation()
        configureMainMenu()
        store.start()
        healthStore.start()
        watchService.start()
        showTimelineWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        healthStore.stop()
        watchService.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showTimelineWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshInspectorMenuState()
    }
}
