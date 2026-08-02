import Foundation

extension TimelineStore {
    func select(_ record: TimelineRecord) {
        selectedID = record.id
        if inspectorAutoOpens {
            inspectorVisible = true
        }
    }

    /// Keyboard traversal of the canvas.
    ///
    /// The timeline is a horizontal scatter of buttons, so tabbing through it means tabbing through
    /// every event in the window. These step through `visibleRecords`, which is already sorted
    /// oldest-first, so a step matches the direction the events read on screen and the order
    /// VoiceOver walks them in. With nothing selected, stepping backwards starts at the newest event
    /// and stepping forwards starts at the oldest, so the first keypress always lands somewhere.
    func selectAdjacentEvent(offset: Int) {
        let records = visibleRecords
        guard !records.isEmpty else {
            return
        }

        guard let selectedID, let currentIndex = records.firstIndex(where: { $0.id == selectedID }) else {
            select(offset < 0 ? records[records.count - 1] : records[0])
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), records.count - 1)
        guard nextIndex != currentIndex else {
            return
        }

        select(records[nextIndex])
    }

    func selectOldestEvent() {
        guard let record = visibleRecords.first else {
            return
        }

        select(record)
    }

    func selectNewestEvent() {
        guard let record = visibleRecords.last else {
            return
        }

        select(record)
    }

    func hideInspector() {
        inspectorVisible = false
    }

    func toggleInspector() {
        if inspectorVisible {
            inspectorVisible = false
            return
        }

        if selectedID == nil {
            selectedID = visibleRecords.last?.id
        }

        inspectorVisible = selectedRecord != nil
    }

    func toggleInspectorAutoOpen() {
        inspectorAutoOpens.toggle()
    }

    func toggleInspectorSummaryHeader() {
        inspectorSummaryHeaderVisible.toggle()
    }

    func clearMissingSelection() {
        guard selectedID != nil, selectedRecord == nil else {
            return
        }

        selectedID = nil
        inspectorVisible = false
    }
}
