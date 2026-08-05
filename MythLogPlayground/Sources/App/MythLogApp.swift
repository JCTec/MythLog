import SwiftUI

@main
struct MythLogApp: App {
    /// The composition root, and the only place that decides where the
    /// interface's data comes from.
    ///
    /// # The switch
    ///
    /// `MYTHLOG_LEDGER` names a ledger to read; `MYTHLOG_HMAC_KEY_HEX` supplies
    /// the key to verify it with. With both set the app reads a real ledger,
    /// and with neither it falls back to the fixture, so design work and
    /// previews stay deterministic. Nothing below this line knows which it got.
    ///
    /// Environment variables rather than a preference, because the point is to
    /// be able to point the app at somebody's actual ledger from a terminal
    /// without a settings screen existing yet — see `HUMAN_CHECKLIST-ENGINE.md`.
    private let source: any TimelineSource
    private let request: TimelineLoadRequest

    init() {
        let environment = ProcessInfo.processInfo.environment

        if let path = environment["MYTHLOG_LEDGER"],
            let keyHex = environment["MYTHLOG_HMAC_KEY_HEX"],
            let key = try? Data(hexEncoded: keyHex.trimmingCharacters(in: .whitespacesAndNewlines)),
            let store = try? LedgerStore(ledgerURL: URL(fileURLWithPath: path), hmacKey: key)
        {
            source = LedgerTimelineSource(store: store, describedOrigin: path)
            // The gap threshold has to match the recorder that wrote the ledger,
            // so it comes from that install's config when there is one.
            let interval = Self.heartbeatInterval(besideLedgerAt: URL(fileURLWithPath: path))
            request = TimelineLoadRequest(
                gapThreshold: HeartbeatConfig(intervalSeconds: interval).gapThreshold)
        } else {
            source = MockTimelineSource()
            request = TimelineLoadRequest(
                gapThreshold: HeartbeatConfig(intervalSeconds: MockLedger.heartbeatInterval).gapThreshold)
        }
    }

    /// Reads the heartbeat interval from the config beside the ledger.
    ///
    /// Falls back to the schema default rather than guessing: a wrong interval
    /// makes gap detection wrong in one direction or the other, and it is worth
    /// being explicit about where the number came from.
    private static func heartbeatInterval(besideLedgerAt ledgerURL: URL) -> TimeInterval {
        let configURL = ledgerURL.deletingLastPathComponent().appendingPathComponent("config.json")
        guard let config = try? EngineConfig.load(from: configURL) else {
            return HeartbeatConfig().intervalSeconds
        }
        return config.heartbeat.intervalSeconds
    }

    var body: some Scene {
        Window("MythLog", id: "main") {
            MainPage(source: source, request: request)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1420, height: 900)
    }
}
