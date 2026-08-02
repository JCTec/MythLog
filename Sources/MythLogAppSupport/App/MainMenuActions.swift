import AppKit
import SwiftUI

extension MythLogApplicationDelegate {
    @objc func showTimelineMenuAction(_ sender: Any?) {
        showTimelineWindow()
    }

    @objc func copySelectedCSV(_ sender: Any?) {
        store.copySelectedCSV()
    }

    @objc func copyVisibleCSV(_ sender: Any?) {
        store.copyVisibleCSV()
    }

    /// Menu handlers live outside the SwiftUI view tree, so they read Reduce Motion from AppKit
    /// rather than from `\.accessibilityReduceMotion`.
    var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    @objc func toggleInspector(_ sender: Any?) {
        withAnimation(ReducedMotion.animation(.easeOut(duration: 0.2), reduceMotion: prefersReducedMotion)) {
            store.toggleInspector()
        }
        refreshInspectorMenuState()
    }

    @objc func toggleInspectorAutoOpen(_ sender: Any?) {
        store.toggleInspectorAutoOpen()
        refreshInspectorMenuState()
    }

    @objc func toggleInspectorSummaryHeader(_ sender: Any?) {
        withAnimation(ReducedMotion.animation(.easeOut(duration: 0.18), reduceMotion: prefersReducedMotion)) {
            store.toggleInspectorSummaryHeader()
        }
        refreshInspectorMenuState()
    }

    @objc func showLedgerIntegrity(_ sender: Any?) {
        store.ledgerIntegrityVisible = true
        showTimelineWindow()
    }

    @objc func showNotificationDiagnostics(_ sender: Any?) {
        store.notificationDiagnosticsVisible = true
        showTimelineWindow()
    }

    @objc func showTelegramSettings(_ sender: Any?) {
        store.telegramSettingsVisible = true
        showTimelineWindow()
    }

    @objc func showLast15Minutes(_ sender: Any?) {
        store.timeRange = TimeRangePreset.last15Minutes.seconds
    }

    @objc func showLastHour(_ sender: Any?) {
        store.timeRange = TimeRangePreset.lastHour.seconds
    }

    @objc func showLast6Hours(_ sender: Any?) {
        store.timeRange = TimeRangePreset.last6Hours.seconds
    }

    @objc func showLast24Hours(_ sender: Any?) {
        store.timeRange = TimeRangePreset.last24Hours.seconds
    }

    @objc func showLast7Days(_ sender: Any?) {
        store.timeRange = TimeRangePreset.last7Days.seconds
    }

    @objc func selectPreviousEvent(_ sender: Any?) {
        store.selectAdjacentEvent(offset: -1)
    }

    @objc func selectNextEvent(_ sender: Any?) {
        store.selectAdjacentEvent(offset: 1)
    }

    @objc func selectOldestEvent(_ sender: Any?) {
        store.selectOldestEvent()
    }

    @objc func selectNewestEvent(_ sender: Any?) {
        store.selectNewestEvent()
    }

    @objc func zoomIn(_ sender: Any?) {
        store.zoom = TimelineZoomLevel.next(after: store.zoom)
    }

    @objc func zoomOut(_ sender: Any?) {
        store.zoom = TimelineZoomLevel.previous(before: store.zoom)
    }

    func refreshInspectorMenuState() {
        showInspectorMenuItem?.title = store.inspectorVisible ? "Hide Inspector" : "Show Inspector"
        showInspectorMenuItem?.state = store.inspectorVisible ? .on : .off
        showInspectorMenuItem?.isEnabled =
            store.inspectorVisible || store.selectedRecord != nil || !store.visibleRecords.isEmpty
        inspectorAutoOpenMenuItem?.state = store.inspectorAutoOpens ? .on : .off
        inspectorSummaryHeaderMenuItem?.state = store.inspectorSummaryHeaderVisible ? .on : .off
    }
}

extension MythLogApplicationDelegate: NSMenuItemValidation {
    /// The event-selection commands are bound to option-arrow, which is also "move by word" in a
    /// text field. AppKit offers a menu item its key equivalent *before* the field editor sees the
    /// key, so without this the search field would silently lose word-wise cursor movement — a
    /// keyboard regression introduced by a keyboard feature.
    ///
    /// A disabled menu item does not consume its key equivalent, so declining here hands the
    /// keystroke back to the responder chain and the text field behaves normally.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action, Self.eventSelectionActions.contains(action) else {
            return true
        }

        return !isEditingText
    }

    private static let eventSelectionActions: Set<Selector> = [
        #selector(selectPreviousEvent(_:)),
        #selector(selectNextEvent(_:)),
        #selector(selectOldestEvent(_:)),
        #selector(selectNewestEvent(_:)),
    ]

    private var isEditingText: Bool {
        // Field editors are NSTextView, which is an NSText, so this covers the search field and
        // every text field in the settings sheets.
        guard let editor = NSApp.keyWindow?.firstResponder as? NSText else {
            return false
        }

        return editor.isEditable
    }
}
