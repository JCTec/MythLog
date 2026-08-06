import Observation
import SwiftUI
import UniformTypeIdentifiers

extension RootPage {
    /// Which ledger is open, and which ones could be.
    ///
    /// # The one decision this type makes
    ///
    /// Discovery offers; this opens. Everything about that split lives here so
    /// there is one place to check that the app cannot open a real ledger
    /// without being asked — see ``LedgerDiscovery`` for why that matters.
    ///
    /// The single exception is `MYTHLOG_LEDGER`, which opens immediately and
    /// deliberately: it exists for automation and for the tamper tests in
    /// `HUMAN_CHECKLIST-ENGINE.md`, both of which need to launch straight into a
    /// specific file. Setting an environment variable *is* the asking.
    @MainActor
    @Observable
    final class Model {
        /// A ledger that has been opened, with the thing that reads it.
        struct Opened {
            var loaded: LoadedLedger
            var source: any TimelineSource
            var request: TimelineLoadRequest
            /// Distinguishes one open ledger from another, so switching builds a
            /// fresh page rather than swapping a source under a running load.
            var id: String
        }

        private(set) var opened: Opened?
        private(set) var candidates: [LedgerCandidate] = []
        /// Supplied by the composition root. See ``SampleLedger`` for why this
        /// is injected rather than reached for.
        let samples: [SampleLedger]
        private(set) var problem: String?
        private(set) var lastOpenedPath: String?

        var isBrowsing = false

        private let discovery: LedgerDiscovery
        private let memory = OpenedLedgerMemory()
        private let environment: [String: String]

        init(
            samples: [SampleLedger] = [],
            discovery: LedgerDiscovery = LedgerDiscovery(),
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) {
            self.samples = samples
            self.discovery = discovery
            self.environment = environment
        }

        /// `events.jsonl` has no type of its own, and a ledger copied for a
        /// tamper test may have any name at all. Plain text plus "any file" is
        /// the honest filter — narrowing it would block the exact workflow the
        /// picker exists to support.
        static let ledgerContentTypes: [UTType] = [.plainText, .json, .data]

        // MARK: - Finding

        /// Looks for ledgers. Reads no records.
        func discover() {
            lastOpenedPath = memory.lastOpenedPath()

            var found = [LedgerCandidate]()

            // The override opens straight away — see the note on this type.
            if let override = LedgerDiscovery.environmentOverride(environment) {
                candidates = [override]
                open(override)
                return
            }

            if let installed = discovery.installedLedger() {
                found.append(installed)
            }

            // A remembered ledger somewhere else — a copy made for a tamper
            // test, an archive on an external drive — is offered too, provided
            // it is not the one already found.
            if let path = lastOpenedPath,
                !found.contains(where: { $0.ledgerURL.path == path }),
                let remembered = discovery.chosenLedger(at: URL(fileURLWithPath: path))
            {
                found.append(remembered)
            }

            candidates = found
        }

        // MARK: - Opening

        func open(_ candidate: LedgerCandidate) {
            do {
                opened = Opened(
                    loaded: candidate.loaded,
                    source: try candidate.makeSource(),
                    request: candidate.loadRequest,
                    id: candidate.id
                )
                problem = nil
                memory.remember(candidate)
                lastOpenedPath = memory.lastOpenedPath()
            } catch {
                // Stay on the welcome page and say what went wrong there. An
                // alert would dismiss to a screen with no explanation on it.
                problem = "That ledger could not be opened: "
                    + ((error as? LocalizedError)?.errorDescription ?? String(describing: error))
            }
        }

        /// A sample needs no opening ceremony — there is nothing to find, no key
        /// to look for, and nothing personal to be careful about.
        func open(_ sample: SampleLedger) {
            opened = Opened(
                loaded: sample.loaded, source: sample.source, request: sample.request, id: sample.id)
            problem = nil
        }

        /// Back to the chooser. The ledger stays on disk; only this view of it
        /// closes.
        func close() {
            opened = nil
            discover()
        }

        // MARK: - Browsing

        func browse() {
            isBrowsing = true
        }

        func finishBrowsing(_ result: Result<[URL], any Error>) {
            isBrowsing = false

            switch result {
            case .failure(let error):
                problem = "The file could not be opened: \(error.localizedDescription)"

            case .success(let urls):
                guard let url = urls.first else { return }
                guard let candidate = discovery.chosenLedger(at: url) else {
                    problem = "\(url.lastPathComponent) is not a readable file."
                    return
                }
                // Deliberately opened without checking whether it *looks* like a
                // ledger. A file that turns out not to be one produces
                // `.unreadable`, which the integrity banner explains properly —
                // and which says out loud that this is not an empty history.
                // Guessing here would only replace a good error with a worse one.
                open(candidate)
            }
        }
    }
}
