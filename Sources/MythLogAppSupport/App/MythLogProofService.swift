import Foundation
import MythLogCore

enum MythLogProofServiceError: LocalizedError, Sendable {
    case missingSecret(account: String)

    var errorDescription: String? {
        switch self {
        case .missingSecret(let account):
            """
            MythLog cannot verify or export the ledger because the installed ledger HMAC key is missing.

            Install or start the recorder from Recorder > Install Recorder at Login... so MythLog can create the local secret account: \(account)
            """
        }
    }
}

struct MythLogProofService: Sendable {
    var launchAgentLabel: String

    func inspectLedger() async throws -> LedgerIntegritySnapshot {
        let launchAgentLabel = launchAgentLabel
        return try await MythLogBackgroundTask.throwing(priority: .userInitiated) {
            let context = try Self.proofContext(launchAgentLabel: launchAgentLabel)
            let exporter = try LedgerProofExporter(ledgerURL: context.ledgerURL, hmacKey: context.hmacKey)
            return try exporter.inspectLedger()
        }
    }

    func exportProofBundle(to destinationURL: URL) async throws -> LedgerProofBundle {
        let launchAgentLabel = launchAgentLabel
        return try await MythLogBackgroundTask.throwing(priority: .userInitiated) {
            let context = try Self.proofContext(launchAgentLabel: launchAgentLabel)
            let exporter = try LedgerProofExporter(ledgerURL: context.ledgerURL, hmacKey: context.hmacKey)
            return try exporter.exportProofBundle(to: destinationURL)
        }
    }

    private static func proofContext(launchAgentLabel: String) throws -> ProofContext {
        let paths = MythLogInstallationPaths(label: launchAgentLabel)
        // installedDefault, not MythLogConfig(): the bare default's tilde paths
        // resolve outside the App Group container under the sandbox, so proof
        // export would read a different (empty) ledger than the recorder writes.
        let config =
            if FileManager.default.fileExists(atPath: paths.configURL.path) {
                try MythLogConfig.load(from: paths.configURL)
            } else {
                MythLogConfig.installedDefault(paths: paths)
            }
        let secretStore = FileSecretStore.installedStore(for: config)
        guard let hmacKey = try secretStore.readSecret(account: config.secrets.hmacKeyAccount) else {
            throw MythLogProofServiceError.missingSecret(account: config.secrets.hmacKeyAccount)
        }
        return ProofContext(
            ledgerURL: PathResolver.fileURL(config.storage.ledgerPath),
            hmacKey: hmacKey
        )
    }
}

private struct ProofContext: Sendable {
    var ledgerURL: URL
    var hmacKey: Data
}
