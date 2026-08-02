import Foundation
import MythLogCore

extension TimelineStore {
    func start() {
        reload()
        startWatchingLedgerPath()
    }

    func reload() {
        let ledgerURL = ledgerURL
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            let result = await MythLogBackgroundTask.value(priority: .userInitiated) {
                Result {
                    try TimelineLedgerLoader.load(from: ledgerURL)
                }
            }

            guard !Task.isCancelled else {
                return
            }

            switch result {
            case .success(let snapshot):
                MythLogDiagnostics.timeline.debug(
                    "Ledger reload succeeded (\(snapshot.recordSet.records.count, privacy: .public) record(s))")
                self?.replaceRecords(snapshot.recordSet)
                self?.ledgerContinuity = snapshot.continuity
                self?.loadError = nil
            case .failure(let error):
                MythLogDiagnostics.timeline.error(
                    "Ledger reload failed: \(String(describing: error), privacy: .public)")
                self?.loadError = String(describing: error)
            }
        }
    }
}
