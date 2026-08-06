import Foundation
import Testing

@testable import MythLog

/// Finding a ledger without opening it, and never opening one unasked.
@Suite("Ledger discovery")
struct LedgerDiscoveryTests {

    /// A directory laid out the way an install is: a ledger, a config, and the
    /// key in `secrets/`.
    private func makeInstall(
        in temporary: TemporaryDirectory,
        withKey: Bool = true,
        heartbeatSeconds: TimeInterval = 60
    ) async throws -> URL {
        let base = temporary.appendingPathComponent("MythLog")
        let locations = StorageLocations.rooted(at: base)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let store = try LedgerStore(ledgerURL: locations.ledgerURL, hmacKey: Data("discovery-key".utf8))
        try await store.append(AlarmEvent(source: "agent", name: "agent.heartbeat"))

        try EngineConfig(
            identity: AgentIdentity(deviceID: "Test Mac", displayName: "Test Mac"),
            heartbeat: HeartbeatConfig(intervalSeconds: heartbeatSeconds)
        ).write(to: locations.configURL)

        if withKey {
            try FileManager.default.createDirectory(
                at: locations.secretsDirectory, withIntermediateDirectories: true)
            try Data("discovery-key".utf8).write(
                to: locations.secretsDirectory.appendingPathComponent(SecretStore.ledgerHMACKeyAccount))
        }

        return locations.ledgerURL
    }

    @Test("a ledger that is not there is not offered")
    func absentLedgerIsNotACandidate() throws {
        let temporary = try TemporaryDirectory()
        let discovery = LedgerDiscovery(
            environment: .sandboxed(), container: .fixed(temporary.url))

        // The path resolves. The file does not exist. Those are different
        // things, and conflating them is how "recorder not running" shipped.
        #expect(discovery.installedLedger() == nil)
    }

    @Test("a ledger where an install would put it is found, with its key and heartbeat")
    func installedLedgerIsFound() async throws {
        let temporary = try TemporaryDirectory()
        let base = temporary.appendingPathComponent("Application Support/MythLog")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        _ = try await makeInstall(in: temporary)

        // Lay it out where a sandboxed install resolves to.
        let locations = StorageLocations.rooted(at: base)
        try FileManager.default.copyItem(
            at: temporary.appendingPathComponent("MythLog/events.jsonl"), to: locations.ledgerURL)
        try FileManager.default.copyItem(
            at: temporary.appendingPathComponent("MythLog/config.json"), to: locations.configURL)
        try FileManager.default.copyItem(
            at: temporary.appendingPathComponent("MythLog/secrets"), to: locations.secretsDirectory)

        let discovery = LedgerDiscovery(environment: .sandboxed(), container: .fixed(temporary.url))
        let candidate = try #require(discovery.installedLedger())

        #expect(candidate.canVerify)
        #expect(candidate.hmacKey == Data("discovery-key".utf8))
        #expect(candidate.heartbeatInterval == 60)
        #expect(candidate.byteSize ?? 0 > 0)
        #expect(candidate.detail.contains("Test Mac"))
    }

    @Test("a ledger with no key beside it is offered, and says so")
    func missingKeyIsOfferedNotHidden() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try await makeInstall(in: temporary, withKey: false)

        let candidate = try #require(LedgerDiscovery().chosenLedger(at: ledgerURL))
        #expect(!candidate.canVerify)
        #expect(candidate.detail.contains("nothing can be verified"))
        // Unverifiable is not unopenable — and the request must not ask for a
        // verification that would then fail against a placeholder key.
        #expect(candidate.loadRequest.verify == false)
    }

    @Test("the heartbeat interval comes from the config beside the ledger")
    func heartbeatFollowsTheConfig() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try await makeInstall(in: temporary, heartbeatSeconds: 900)

        let candidate = try #require(LedgerDiscovery().chosenLedger(at: ledgerURL))
        #expect(candidate.heartbeatInterval == 900)
        // Which changes what counts as a gap — a slower heartbeat means a
        // longer silence is still healthy.
        #expect(candidate.loadRequest.gapThreshold == 2700)
    }

    @Test("the environment override is honoured, including a deliberately wrong key")
    func environmentOverrideWins() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try await makeInstall(in: temporary)

        let wrongKey = "00112233"
        let candidate = try #require(
            LedgerDiscovery.environmentOverride([
                "MYTHLOG_LEDGER": ledgerURL.path,
                "MYTHLOG_HMAC_KEY_HEX": wrongKey,
            ]))

        // The tamper tests in HUMAN_CHECKLIST-ENGINE.md need to supply a key
        // that does not match, so an explicit key must beat the one on disk.
        #expect(candidate.hmacKey == (try Data(hexEncoded: wrongKey)))
        #expect(candidate.origin == .environment)
    }

    @Test("an override with no key falls back to the one beside the ledger")
    func environmentOverrideFallsBackToTheStoredKey() async throws {
        let temporary = try TemporaryDirectory()
        let ledgerURL = try await makeInstall(in: temporary)

        let candidate = try #require(
            LedgerDiscovery.environmentOverride(["MYTHLOG_LEDGER": ledgerURL.path]))
        #expect(candidate.hmacKey == Data("discovery-key".utf8))
    }

    @Test("no override, no candidate")
    func noOverride() {
        #expect(LedgerDiscovery.environmentOverride([:]) == nil)
        #expect(LedgerDiscovery.environmentOverride(["MYTHLOG_LEDGER": "/nope/events.jsonl"]) == nil)
    }
}

@Suite("Secret store")
struct SecretStoreTests {

    @Test("reads a secret written beside the ledger")
    func readsSecret() throws {
        let temporary = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: temporary.url, withIntermediateDirectories: true)
        try Data("hunter2".utf8).write(to: temporary.appendingPathComponent("ledger-hmac-key"))

        #expect(SecretStore(directory: temporary.url).ledgerHMACKey() == Data("hunter2".utf8))
    }

    @Test("an absent secret is nil, not an error")
    func absentSecretIsNil() throws {
        let temporary = try TemporaryDirectory()
        // A ledger copied without its secrets directory is readable and
        // unverifiable, and the interface has to be able to say exactly that.
        #expect(SecretStore(directory: temporary.url).ledgerHMACKey() == nil)
    }

    @Test("an empty key file reads as no key rather than an empty key")
    func emptyKeyIsNoKey() throws {
        let temporary = try TemporaryDirectory()
        try Data().write(to: temporary.appendingPathComponent("ledger-hmac-key"))
        // An empty key would be refused by LedgerStore anyway; catching it here
        // means the chooser says "no key" instead of the open failing.
        #expect(SecretStore(directory: temporary.url).ledgerHMACKey() == nil)
    }

    @Test("an account name cannot escape the secrets directory")
    func accountNamesArePathSafe() {
        // The account comes from a config file the user can edit, so it is
        // untrusted input on a path.
        #expect(SecretStore.fileName(forAccount: "../../etc/passwd") != nil)
        #expect(SecretStore.fileName(forAccount: "../../etc/passwd")?.contains("/") == false)
        #expect(SecretStore.fileName(forAccount: "..") == nil)
        #expect(SecretStore.fileName(forAccount: ".") == nil)
        #expect(SecretStore.fileName(forAccount: "") == nil)
        #expect(SecretStore.fileName(forAccount: "ledger-hmac-key") == "ledger-hmac-key")
    }
}

@Suite("Choosing a ledger")
struct RootPageModelTests {

    @MainActor
    @Test("discovery offers but does not open")
    func discoveryDoesNotOpen() {
        let model = RootPage.Model(
            samples: [],
            discovery: LedgerDiscovery(environment: .unsandboxed, container: .unavailable),
            environment: [:]
        )
        model.discover()

        // The whole point: launching the app must never put somebody's real
        // history on screen by itself.
        #expect(model.opened == nil)
    }

    @MainActor
    @Test("a sample opens without ceremony")
    func samplesOpenDirectly() {
        let model = RootPage.Model(
            samples: MockTimelineSource.samples,
            discovery: LedgerDiscovery(environment: .unsandboxed, container: .unavailable),
            environment: [:]
        )
        model.discover()
        #expect(model.opened == nil)

        let sample = try! #require(model.samples.first)
        model.open(sample)

        #expect(model.opened?.id == sample.id)
        // And the header can always say it is not real history.
        #expect(model.opened?.loaded.isRealHistory == false)
    }

    @MainActor
    @Test("the environment override opens immediately — setting it is the asking")
    func environmentOverrideOpensImmediately() throws {
        let temporary = try TemporaryDirectory()
        let base = temporary.appendingPathComponent("MythLog")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let ledgerURL = StorageLocations.rooted(at: base).ledgerURL
        try Data("{}\n".utf8).write(to: ledgerURL)

        let model = RootPage.Model(
            samples: [],
            discovery: LedgerDiscovery(environment: .unsandboxed, container: .unavailable),
            environment: ["MYTHLOG_LEDGER": ledgerURL.path]
        )
        model.discover()

        #expect(model.opened != nil)
        #expect(model.opened?.loaded.isRealHistory == true)
        #expect(model.opened?.loaded.badge == "MYTHLOG_LEDGER")
    }

    @MainActor
    @Test("closing returns to the chooser without touching the ledger")
    func closeReturnsToChooser() {
        let model = RootPage.Model(
            samples: MockTimelineSource.samples,
            discovery: LedgerDiscovery(environment: .unsandboxed, container: .unavailable),
            environment: [:]
        )
        model.discover()
        model.open(model.samples[0])
        #expect(model.opened != nil)

        model.close()
        #expect(model.opened == nil)
        #expect(!model.samples.isEmpty)
    }
}
