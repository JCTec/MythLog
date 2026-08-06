import Foundation

/// Remembers which ledger was opened last, so it can be *offered* first.
///
/// # Remembering is not reopening
///
/// This deliberately does not auto-open. Consenting once to look at your own
/// history is not consent to have it on screen every time the app launches —
/// and the machine this runs on is the one being used for screenshots. The
/// remembered ledger appears at the top of the chooser, labelled, and one click
/// away. That is one extra click in exchange for never being ambushed by your
/// own history in front of an audience.
///
/// The stored value is a path, not a bookmark. That is enough while the app is
/// unsandboxed; see the caveat on ``LedgerDiscovery``.
struct OpenedLedgerMemory: Sendable {
    private static let key = "com.jctec.mythlog.playground.lastOpenedLedger"

    /// `UserDefaults` is not `Sendable`, so an instance is created and used
    /// inside each call rather than stored. These are two calls per launch on a
    /// property list the system already has in memory.
    func lastOpenedPath() -> String? {
        UserDefaults.standard.string(forKey: Self.key)
    }

    func remember(_ candidate: LedgerCandidate) {
        // The fixture is not worth remembering — it is the default anyway — and
        // an environment override is somebody else's decision, not a choice
        // this app should persist on their behalf.
        guard candidate.origin == .chosen || isInstalled(candidate.origin) else { return }
        UserDefaults.standard.set(candidate.ledgerURL.path, forKey: Self.key)
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    private func isInstalled(_ origin: LedgerCandidate.Origin) -> Bool {
        if case .installed = origin { return true }
        return false
    }
}
