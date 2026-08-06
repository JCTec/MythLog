import Foundation

/// Finds ledgers without opening them.
///
/// # Auto-detect, do not auto-load
///
/// Everything here stats files and reads a small config. It never reads a
/// record, and it never hands anything to the interface unasked. That rule
/// exists because this app is run on other people's Macs for screenshots and
/// design work, and "launch the app, see somebody's real history" is a failure
/// even though every individual step of it is working correctly.
///
/// So discovery produces an *offer*. The user opens it.
///
/// # The sandbox caveat
///
/// This works because the playground is **unsandboxed** (`ENABLE_APP_SANDBOX: NO`
/// in `project.yml`). An unsandboxed process can read the App Group container
/// directory even without the App Groups entitlement, so `StorageLocations`
/// resolves a path this app can actually open.
///
/// A sandboxed build could not. It would be confined to its own container, and
/// reading the recorder's ledger would require either the matching App Groups
/// entitlement — which is how the shipping app does it — or a security-scoped
/// bookmark obtained from an `NSOpenPanel` the user drove, persisted with
/// `URL.bookmarkData(options: .withSecurityScope)` and re-entered with
/// `startAccessingSecurityScopedResource()`. The picker path in this phase
/// would need that treatment before it could ship in a sandboxed build; the
/// auto-detect path would need the entitlement.
struct LedgerDiscovery: Sendable {
    var environment: SandboxEnvironment
    var container: SharedContainer

    init(environment: SandboxEnvironment = .current(), container: SharedContainer = .system) {
        self.environment = environment
        self.container = container
    }

    /// The ledger an install would have written, if it is there.
    ///
    /// Returns `nil` when there is no ledger rather than an empty candidate: a
    /// path that resolves is not the same as a ledger that exists, and offering
    /// to open nothing is how the 1.0.0 bug felt from the outside.
    func installedLedger(fileManager: FileManager = FileManager()) -> LedgerCandidate? {
        guard let locations = try? StorageLocations.resolve(
            environment: environment, container: container)
        else {
            return nil
        }
        return candidate(at: locations.ledgerURL, origin: .installed(locations.origin), fileManager: fileManager)
    }

    /// A ledger the user chose in the file picker.
    func chosenLedger(at url: URL, fileManager: FileManager = FileManager()) -> LedgerCandidate? {
        candidate(at: url, origin: .chosen, fileManager: fileManager)
    }

    /// The `MYTHLOG_LEDGER` override. Automation, and the tamper tests in
    /// `HUMAN_CHECKLIST-ENGINE.md`, which need arbitrary paths and a key that
    /// may deliberately be wrong.
    static func environmentOverride(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = FileManager()
    ) -> LedgerCandidate? {
        guard let path = environment["MYTHLOG_LEDGER"] else { return nil }
        let url = URL(fileURLWithPath: path)

        // The key may be given explicitly — the tamper tests supply a
        // deliberately wrong one — and otherwise falls back to the secrets
        // directory beside the ledger.
        let explicitKey = environment["MYTHLOG_HMAC_KEY_HEX"]
            .flatMap { try? Data(hexEncoded: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        var candidate = LedgerDiscovery().candidate(at: url, origin: .environment, fileManager: fileManager)
        if candidate != nil, let explicitKey {
            candidate?.hmacKey = explicitKey
        }
        return candidate
    }

    // MARK: - Describing one

    private func candidate(
        at ledgerURL: URL,
        origin: LedgerCandidate.Origin,
        fileManager: FileManager
    ) -> LedgerCandidate? {
        guard fileManager.fileExists(atPath: ledgerURL.path) else { return nil }

        let directory = ledgerURL.deletingLastPathComponent()
        let locations = StorageLocations.rooted(at: directory)
        let config = try? EngineConfig.load(from: locations.configURL)

        let account = config?.secrets.hmacKeyAccount ?? SecretStore.ledgerHMACKeyAccount
        let key = SecretStore(locations: locations).ledgerHMACKey(account: account)

        let size = chainByteSize(for: ledgerURL, fileManager: fileManager)

        return LedgerCandidate(
            id: ledgerURL.path,
            origin: origin,
            ledgerURL: ledgerURL,
            hmacKey: key,
            heartbeatInterval: config?.heartbeat.intervalSeconds ?? HeartbeatConfig().intervalSeconds,
            title: directory.lastPathComponent == "MythLog"
                ? "MythLog ledger" : directory.lastPathComponent,
            detail: describe(ledgerURL: ledgerURL, hasKey: key != nil, config: config),
            byteSize: size
        )
    }

    /// A sentence that says what will happen if this is opened, including the
    /// bad news. A candidate with no key is offered, not hidden — it is still
    /// readable, and pretending it does not exist would be the less honest of
    /// the two options.
    private func describe(ledgerURL: URL, hasKey: Bool, config: EngineConfig?) -> String {
        var parts = [ledgerURL.deletingLastPathComponent().path]
        if !hasKey {
            parts.append("No key found beside it — readable, but nothing can be verified.")
        }
        if let device = config?.identity.displayName, !device.isEmpty {
            parts.append("Recorded by \(device).")
        }
        return parts.joined(separator: " · ")
    }

    /// Size of the whole chain: the active segment plus every rotated one.
    ///
    /// Best-effort and cheap — it stats files, it does not open them. A number
    /// here is the difference between "open the thing" and "open the thing and
    /// find out it is nine gigabytes".
    private func chainByteSize(for ledgerURL: URL, fileManager: FileManager) -> Int? {
        let segments = (try? LedgerSegmentNaming.rotatedSegmentURLs(
            for: ledgerURL, fileManager: fileManager)) ?? []

        let sizes = ([ledgerURL] + segments).compactMap { url -> Int? in
            (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)??.intValue
        }
        return sizes.isEmpty ? nil : sizes.reduce(0, +)
    }
}
