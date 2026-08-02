/// Stable accessibility identifiers for every primary interactive control.
///
/// These are test infrastructure, not user-facing copy: nothing here is ever spoken or displayed.
/// They exist so a UI test can target a control by identity instead of by its visible label, which
/// would otherwise make every wording change a test break — and make accessibility copy the risky
/// thing to improve.
///
/// Scheme is `surface.role.name`, lowercase, dot-separated. Where a surface repeats a control per
/// item, the item's own stable id is the last component; the timeline and inspector lists use the
/// row's position instead, because event UUIDs change on every launch.
enum A11yIdentifier {
    // Timeline canvas
    static let timelineCanvas = "timeline.canvas"
    static let timelineEmptyState = "timeline.state.empty"
    static let timelineLiveEdge = "timeline.marker.liveEdge"

    static func timelineEventNode(index: Int) -> String {
        "timeline.event.node.\(index)"
    }

    // Top control bar
    static let toolbarRecorderHealth = "toolbar.button.recorderHealth"
    static let toolbarFilterSettings = "toolbar.button.filterSettings"
    static let toolbarInspectorToggle = "toolbar.button.inspector"
    static let toolbarSearchField = "toolbar.field.search"
    static let toolbarZoomIn = "toolbar.button.zoomIn"
    static let toolbarZoomOut = "toolbar.button.zoomOut"
    static let toolbarZoomSlider = "toolbar.slider.zoom"
    static let toolbarLedgerStatus = "toolbar.button.ledgerStatus"

    static func toolbarCategoryFilter(id: String) -> String {
        "toolbar.filter.\(id)"
    }

    static func toolbarTimeRange(id: String) -> String {
        "toolbar.button.timeRange.\(id)"
    }

    // Recorder setup banner
    static let recorderBannerAction = "banner.button.recorderSetup"

    // Filter settings sheet
    static let filterSettingsClose = "filterSettings.button.close"
    static let filterSettingsRestoreDefaults = "filterSettings.button.restoreDefaults"
    static let filterSettingsDone = "filterSettings.button.done"
    static let filterSettingsCreate = "filterSettings.button.create"

    static func filterSettingsStatePill(id: String) -> String {
        "filterSettings.pill.\(id)"
    }

    // Ledger integrity sheet
    static let ledgerIntegrityRefresh = "ledgerIntegrity.button.refresh"
    static let ledgerIntegrityClose = "ledgerIntegrity.button.close"

    // Notification diagnostics sheet
    static let notificationDiagnosticsRefresh = "notificationDiagnostics.button.refresh"
    static let notificationDiagnosticsClose = "notificationDiagnostics.button.close"

    // Telegram settings sheet
    static let telegramSettingsReload = "telegramSettings.button.reload"
    static let telegramSettingsClose = "telegramSettings.button.close"

    // Inspector
    static func inspectorEventRow(index: Int) -> String {
        "inspector.event.row.\(index)"
    }

    /// AppKit menu items are identified by their action selector rather than their title, for the
    /// same reason: renaming "Show Inspector" should not break a test that opens the inspector.
    /// Applied centrally in `MythLogMenuItemFactory`.
    static func menuCommand(selectorName: String) -> String {
        "menu.command.\(selectorName.replacingOccurrences(of: ":", with: ""))"
    }
}
