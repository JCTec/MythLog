import Foundation
import MythLogCore

@testable import MythLogAppSupport

extension MythLogTests {
    static func runAccessibilityTests(_ runner: TestRunner) async {
        await runEventLabelAccessibilityTests(runner)
        await runSeverityCueAccessibilityTests(runner)
        await runAccessibilityIdentifierTests(runner)
        await runKeyboardSelectionTests(runner)
        await runReducedMotionTests(runner)
    }

    private static func runReducedMotionTests(_ runner: TestRunner) async {
        await runner.run("reduce motion drops animation rather than shortening it") {
            try expect(
                ReducedMotion.animation(.easeOut(duration: 0.35), reduceMotion: true) == nil,
                "a shorter animation is still motion; it should be removed entirely"
            )
            try expect(
                ReducedMotion.animation(.easeOut(duration: 0.35), reduceMotion: false) != nil,
                "motion should be untouched when the setting is off"
            )
        }

        await runner.run("reduce motion removes scale effects outright") {
            try expect(
                ReducedMotion.scale(1.08, reduceMotion: true) == 1,
                "a selected node should not grow when motion is reduced"
            )
            try expect(
                ReducedMotion.scale(1.08, reduceMotion: false) == 1.08,
                "the selection bump should survive when the setting is off"
            )
        }
    }

    private static func runEventLabelAccessibilityTests(_ runner: TestRunner) async {
        await runner.run("event node label names every severity in words") {
            for severity in AlarmSeverity.allCases {
                let displayRecord = accessibilityDisplayRecord(severity: severity)
                let label = displayRecord.eventNodeAccessibilityLabel

                try expect(
                    label.contains("\(severity.accessibilityTitle) severity."),
                    "label for \(severity.rawValue) should state the severity in words, got: \(label)"
                )
                try expect(
                    label.localizedCaseInsensitiveContains(severity.rawValue),
                    "label for \(severity.rawValue) should contain the severity name"
                )
            }
        }

        await runner.run("event node label tracks the record it describes") {
            let critical = accessibilityDisplayRecord(severity: .critical)
            let info = accessibilityDisplayRecord(severity: .info)

            try expect(
                critical.eventNodeAccessibilityLabel != info.eventNodeAccessibilityLabel,
                "labels should change when the underlying severity changes"
            )
            try expect(
                critical.eventNodeAccessibilityLabel.contains("Critical severity."),
                "a critical record should be announced as critical"
            )
            try expect(
                !critical.eventNodeAccessibilityLabel.contains("Info severity."),
                "a critical record should not carry another severity's wording"
            )
        }

        await runner.run("event node label carries title, detail, and timestamp") {
            let displayRecord = accessibilityDisplayRecord(severity: .notice)
            let label = displayRecord.eventNodeAccessibilityLabel

            try expect(label.hasPrefix("\(displayRecord.title)."), "label should lead with the title")
            try expect(label.contains("\(displayRecord.subtitle)."), "label should include the detail line")
            try expect(
                label.contains(displayRecord.timestamp.inspectorDateString),
                "label should include the full timestamp"
            )
            try expect(label.hasSuffix("."), "label should read as complete sentences")
        }

        await runner.run("event node label omits a subtitle that only repeats the title") {
            let event = AlarmEvent(
                observedAt: Date(timeIntervalSince1970: 12_000),
                source: "session",
                name: "application.activated",
                severity: .notice,
                metadata: [
                    "applicationName": "Finder",
                    "bundleIdentifier": "Finder",
                ]
            )
            let displayRecord = timelineDisplayRecord(index: 0, event: event, displayState: .normal)

            try expect(
                displayRecord.title == displayRecord.subtitle,
                "this fixture exists to make the title and subtitle identical"
            )

            let label = displayRecord.eventNodeAccessibilityLabel
            let titleOccurrences = label.components(separatedBy: "\(displayRecord.title).").count - 1

            try expect(
                titleOccurrences == 1,
                "a subtitle identical to the title should not be spoken twice, got: \(label)"
            )
        }

        await runner.run("event node value explains the search-only dimming") {
            let visible = accessibilityDisplayRecord(severity: .warning)
            try expect(
                visible.eventNodeAccessibilityValue == nil,
                "an ordinary event should not carry a state value"
            )

            let dimmed = TimelineDisplayRecord(
                record: visible.record,
                presentation: visible.presentation,
                displayState: .hidden,
                hiddenBySearch: true
            )
            let value = try require(
                dimmed.eventNodeAccessibilityValue,
                "an event shown only because it matches the search should explain itself"
            )
            try expect(
                value.localizedCaseInsensitiveContains("search"),
                "the value should say the event survived because of the search, got: \(value)"
            )
        }
    }

    private static func runSeverityCueAccessibilityTests(_ runner: TestRunner) async {
        await runner.run("severity is distinguishable without color") {
            let warningBadge = try require(
                AlarmSeverity.warning.timelineBadgeSymbolName,
                "warning needs a non-color cue"
            )
            let criticalBadge = try require(
                AlarmSeverity.critical.timelineBadgeSymbolName,
                "critical needs a non-color cue"
            )

            try expect(
                warningBadge != criticalBadge,
                "warning and critical must not share a silhouette, or grayscale cannot tell them apart"
            )

            for severity in [AlarmSeverity.debug, .info, .notice] {
                try expect(
                    severity.timelineBadgeSymbolName == nil,
                    "\(severity.rawValue) is deliberately part of the unbadged quiet band"
                )
            }
        }

        await runner.run("severity tag avoids white text on near-white fills") {
            for severity in [AlarmSeverity.debug, .info] {
                try expect(
                    severity.timelineTagColor == .secondary,
                    "\(severity.rawValue) should fall back to the readable secondary tag styling"
                )
            }

            for severity in [AlarmSeverity.notice, .warning, .critical] {
                try expect(
                    severity.timelineTagColor == severity.timelineColor,
                    "\(severity.rawValue) should keep its own tag color"
                )
            }
        }

        await runner.run("recorder health is distinguishable without color") {
            let levels: [AgentHealthLevel] = [.healthy, .warning, .critical, .unknown]
            let symbols = levels.map(\.symbolName)

            try expect(
                Set(symbols).count == levels.count,
                "each recorder health level needs its own silhouette, got: \(symbols)"
            )
            try expect(symbols.allSatisfy { !$0.isEmpty }, "no health level may have an empty symbol")
        }
    }

    private static func runAccessibilityIdentifierTests(_ runner: TestRunner) async {
        await runner.run("accessibility identifiers are unique and well formed") {
            let identifiers = knownAccessibilityIdentifiers()

            try expect(
                Set(identifiers).count == identifiers.count,
                "identifiers must be unique or a UI test cannot target one control"
            )

            for identifier in identifiers {
                let components = identifier.components(separatedBy: ".")
                try expect(components.count >= 2, "\(identifier) should be surface-scoped")
                try expect(
                    components.allSatisfy { !$0.isEmpty },
                    "\(identifier) should not contain an empty component"
                )
                try expect(
                    !identifier.contains(" "),
                    "\(identifier) should not contain whitespace"
                )
            }
        }

        await runner.run("per-item accessibility identifiers stay distinct") {
            let nodes = (0..<5).map { A11yIdentifier.timelineEventNode(index: $0) }
            try expect(Set(nodes).count == nodes.count, "each timeline node needs its own identifier")

            let rows = (0..<5).map { A11yIdentifier.inspectorEventRow(index: $0) }
            try expect(Set(rows).count == rows.count, "each inspector row needs its own identifier")
            try expect(
                Set(nodes).isDisjoint(with: Set(rows)),
                "canvas nodes and inspector rows must not collide"
            )

            let filters = ["unlock", "custom.backup"].map { A11yIdentifier.toolbarCategoryFilter(id: $0) }
            try expect(Set(filters).count == filters.count, "each filter button needs its own identifier")
        }

        await runner.run("menu identifiers drop the selector colon") {
            try expect(
                A11yIdentifier.menuCommand(selectorName: "toggleInspector:") == "menu.command.toggleInspector",
                "menu identifiers should be derived from the selector without its argument colon"
            )
            try expect(
                A11yIdentifier.menuCommand(selectorName: "selectNextEvent:")
                    != A11yIdentifier.menuCommand(selectorName: "selectPreviousEvent:"),
                "distinct menu commands need distinct identifiers"
            )
        }
    }

    private static func runKeyboardSelectionTests(_ runner: TestRunner) async {
        await runner.run("VoiceOver traversal order is oldest first regardless of z-order") {
            let count = 4
            let priorities = (0..<count).map {
                TimelineAccessibilityOrder.sortPriority(index: $0, count: count)
            }

            try expect(
                priorities == priorities.sorted(by: >),
                "priorities should fall as position advances so the oldest event is read first"
            )
            try expect(
                Set(priorities).count == count,
                "no two events may share a traversal priority"
            )
            try expect(
                priorities.last == 1,
                "the newest event should still rank above unprioritized content"
            )
        }

        await runner.run("keyboard event stepping walks the timeline chronologically") {
            try await withIsolatedTimelineStore { store in
                let records = accessibilityStoreRecords()
                seedDerivedTimeline(store: store, records: records)

                store.selectAdjacentEvent(offset: 1)
                try expect(
                    store.selectedID == records[0].id,
                    "stepping forward with nothing selected should start at the oldest event"
                )

                store.selectAdjacentEvent(offset: 1)
                try expect(store.selectedID == records[1].id, "stepping forward should advance one event")

                store.selectAdjacentEvent(offset: -1)
                try expect(store.selectedID == records[0].id, "stepping back should retreat one event")
            }
        }

        await runner.run("keyboard event stepping clamps at both ends") {
            try await withIsolatedTimelineStore { store in
                let records = accessibilityStoreRecords()
                seedDerivedTimeline(store: store, records: records)

                store.selectAdjacentEvent(offset: -1)
                try expect(
                    store.selectedID == records[records.count - 1].id,
                    "stepping back with nothing selected should start at the newest event"
                )

                store.selectAdjacentEvent(offset: 1)
                try expect(
                    store.selectedID == records[records.count - 1].id,
                    "stepping past the newest event should stay put rather than wrap"
                )

                store.selectOldestEvent()
                store.selectAdjacentEvent(offset: -1)
                try expect(
                    store.selectedID == records[0].id,
                    "stepping before the oldest event should stay put rather than wrap"
                )
            }
        }

        await runner.run("keyboard event stepping is a no-op on an empty timeline") {
            try await withIsolatedTimelineStore { store in
                store.selectAdjacentEvent(offset: 1)
                store.selectAdjacentEvent(offset: -1)
                store.selectOldestEvent()
                store.selectNewestEvent()

                try expect(store.selectedID == nil, "an empty timeline should not select anything")
            }
        }

        await runner.run("keyboard jump commands reach both ends of the timeline") {
            try await withIsolatedTimelineStore { store in
                let records = accessibilityStoreRecords()
                seedDerivedTimeline(store: store, records: records)

                store.selectNewestEvent()
                try expect(
                    store.selectedID == records[records.count - 1].id,
                    "jumping to the newest event should select the last visible record"
                )

                store.selectOldestEvent()
                try expect(
                    store.selectedID == records[0].id,
                    "jumping to the oldest event should select the first visible record"
                )
            }
        }
    }
}

private func accessibilityDisplayRecord(severity: AlarmSeverity) -> TimelineDisplayRecord {
    let event = AlarmEvent(
        observedAt: Date(timeIntervalSince1970: 11_000),
        source: "session",
        name: "application.activated",
        severity: severity,
        metadata: [
            "applicationName": "Terminal",
            "bundleIdentifier": "com.apple.Terminal",
        ]
    )
    return timelineDisplayRecord(index: 0, event: event, displayState: .normal)
}

private func accessibilityStoreRecords() -> [TimelineRecord] {
    (0..<3).map { offset in
        timelineRecord(
            index: offset,
            event: AlarmEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000002\(offset)")!,
                observedAt: Date(timeIntervalSince1970: 20_000 + Double(offset)),
                source: "session",
                name: "screen.unlocked"
            )
        )
    }
}

@MainActor
private func seedDerivedTimeline(store: TimelineStore, records: [TimelineRecord]) {
    store.replaceRecords(records)
    store.applyDerivedTimelineData(
        TimelineDerivedState.compute(
            DerivedTimelineSnapshot(
                records: records,
                filters: store.timelineFilters,
                filterStates: store.filterStates,
                searchText: store.searchText,
                timeRange: store.timeRange,
                now: Date(timeIntervalSince1970: 20_010)
            )))
}

private func knownAccessibilityIdentifiers() -> [String] {
    [
        A11yIdentifier.timelineCanvas,
        A11yIdentifier.timelineEmptyState,
        A11yIdentifier.timelineLiveEdge,
        A11yIdentifier.toolbarRecorderHealth,
        A11yIdentifier.toolbarFilterSettings,
        A11yIdentifier.toolbarInspectorToggle,
        A11yIdentifier.toolbarSearchField,
        A11yIdentifier.toolbarZoomIn,
        A11yIdentifier.toolbarZoomOut,
        A11yIdentifier.toolbarZoomSlider,
        A11yIdentifier.toolbarLedgerStatus,
        A11yIdentifier.recorderBannerAction,
        A11yIdentifier.filterSettingsClose,
        A11yIdentifier.filterSettingsRestoreDefaults,
        A11yIdentifier.filterSettingsDone,
        A11yIdentifier.filterSettingsCreate,
        A11yIdentifier.ledgerIntegrityRefresh,
        A11yIdentifier.ledgerIntegrityClose,
        A11yIdentifier.notificationDiagnosticsRefresh,
        A11yIdentifier.notificationDiagnosticsClose,
        A11yIdentifier.telegramSettingsReload,
        A11yIdentifier.telegramSettingsClose,
        A11yIdentifier.timelineEventNode(index: 0),
        A11yIdentifier.inspectorEventRow(index: 0),
        A11yIdentifier.toolbarCategoryFilter(id: "unlock"),
        A11yIdentifier.toolbarTimeRange(id: "24h"),
        A11yIdentifier.filterSettingsStatePill(id: "unlock"),
        A11yIdentifier.menuCommand(selectorName: "toggleInspector:"),
    ]
}
