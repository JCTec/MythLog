import Foundation
import MythLogCore

extension TimelineStore {
    func scheduleDerivedTimelineUpdate() {
        let snapshot = DerivedTimelineSnapshot(
            records: records,
            filters: timelineFilters,
            filterStates: filterStates,
            searchText: searchText,
            timeRange: timeRange,
            now: Date()
        )

        derivedTimelineTask?.cancel()
        derivedTimelineTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(45))
            guard !Task.isCancelled else {
                return
            }

            let signpostState = MythLogDiagnostics.signposter.beginInterval("timelineDerivation")
            let result = await MythLogBackgroundTask.value(priority: .userInitiated) {
                TimelineDerivedState.computeIfNotCancelled(snapshot)
            }
            MythLogDiagnostics.signposter.endInterval("timelineDerivation", signpostState)

            guard let result, !Task.isCancelled else {
                MythLogDiagnostics.timeline.debug("Derivation cancelled or superseded; result discarded")
                return
            }

            self?.applyDerivedTimelineData(result)
        }
    }
}
