import Foundation
import Testing

@testable import MythLog

/// The Wave 3 gate: **a config written by the shipping app round-trips
/// unchanged.**
///
/// The fixtures in `Tests/Fixtures/shipping-config` were written by
/// `MythLogConfig.write(to:)` in `Sources/MythLogCore` — the code on the App
/// Store — not by anything in this target.
@Suite("Config written by the shipping app")
struct ShippingConfigCompatibilityTests {

    private func fixture(_ name: String) throws -> URL {
        LedgerFixtures.testsDirectory
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("shipping-config", isDirectory: true)
            .appendingPathComponent(name)
    }

    @Test(
        "round-trips byte for byte",
        arguments: ["default-unsandboxed.json", "installed-sandboxed.json"]
    )
    func roundTripsByteForByte(name: String) throws {
        let url = try fixture(name)
        let original = try Data(contentsOf: url)

        let config = try EngineConfig.load(from: url)
        let reencoded = try config.encoded()

        #expect(
            reencoded == original,
            """
            Re-encoding changed the file.
            original:  \(String(decoding: original, as: UTF8.self).prefix(400))
            re-encoded:\(String(decoding: reencoded, as: UTF8.self).prefix(400))
            """
        )
    }

    @Test("sections this build does not model survive verbatim", arguments: [
        "default-unsandboxed.json", "installed-sandboxed.json",
    ])
    func unmodelledSectionsSurvive(name: String) throws {
        let config = try EngineConfig.load(from: try fixture(name))

        // These belong to waves that have not landed. They must come back
        // unchanged rather than being dropped.
        for section in ["session", "filesystem", "unifiedLog", "notifications", "telegram", "rules"] {
            #expect(config.unmodelled[section] != nil, "\(section) was dropped")
        }
        #expect(config.unmodelled.keys.allSatisfy { !EngineConfig.modelledKeys.contains($0) })
    }

    @Test("the modelled sections decode to the values the shipping app wrote")
    func modelledSectionsDecode() throws {
        let config = try EngineConfig.load(from: try fixture("installed-sandboxed.json"))

        #expect(config.schemaVersion == 1)
        #expect(config.identity.deviceID == "Fixture’s MacBook Pro")
        #expect(config.secrets.hmacKeyAccount == "ledger-hmac-key")
        #expect(config.secrets.allowDevelopmentFallbackKey == false)
        #expect(config.heartbeat.enabled)
        #expect(config.heartbeat.intervalSeconds == 60)
        #expect(config.storage?.maxLedgerFileBytes == 4_194_304)
        #expect(config.storage?.ledgerPath?.hasPrefix("/Users/example/Library/Group Containers/") == true)
    }

    @Test("a config written by a newer build keeps its unknown sections")
    func forwardCompatibility() throws {
        let temporary = try TemporaryDirectory()
        let url = temporary.appendingPathComponent("newer.json")
        let source = """
            {
              "schemaVersion" : 2,
              "identity" : { "deviceID" : "future", "displayName" : "future" },
              "somethingNew" : { "enabled" : true, "threshold" : 0.5, "names" : ["a", "b"] },
              "heartbeat" : { "checkpointEveryHeartbeats" : 5, "enabled" : true, "intervalSeconds" : 30 },
              "secrets" : { "allowDevelopmentFallbackKey" : false, "hmacKeyAccount" : "k" },
              "hashAnchor" : { "anchorEveryHeartbeats" : 5, "destination" : "iCloudDrive", "enabled" : true }
            }
            """
        try Data(source.utf8).write(to: url)

        let config = try EngineConfig.load(from: url)
        #expect(config.schemaVersion == 2)
        #expect(config.unmodelled["somethingNew"] != nil)

        // Save it back and load again: the unknown section is still there.
        let outputURL = temporary.appendingPathComponent("saved.json")
        try config.write(to: outputURL)
        #expect(try EngineConfig.load(from: outputURL) == config)
    }
}

@Suite("Config schema")
struct ConfigSchemaTests {

    @Test("an absent storage section stays absent — it is not a set of defaults")
    func absentStorageIsAbsent() throws {
        let temporary = try TemporaryDirectory()
        let url = temporary.appendingPathComponent("minimal.json")
        try Data("{}".utf8).write(to: url)

        let config = try EngineConfig.load(from: url)
        #expect(config.storage == nil)

        // And it does not reappear on save. "Nobody configured a path" must stay
        // distinguishable from "the path is the default", which is the
        // distinction the 1.0.0 bug lost.
        let saved = String(decoding: try config.encoded(), as: UTF8.self)
        #expect(!saved.contains("\"storage\""))
    }

    @Test("no default anywhere in the schema is a tilde path")
    func noTildeDefaults() throws {
        let saved = String(decoding: try EngineConfig().encoded(), as: UTF8.self)
        #expect(!saved.contains("~"))
    }

    @Test("an absent anchor destination decodes as .directory, preserving old behaviour")
    func anchorDestinationBackCompatibility() throws {
        let older = Data("""
            {"hashAnchor":{"enabled":true,"directory":"/tmp/anchors","anchorEveryHeartbeats":5}}
            """.utf8)
        let config = try CanonicalJSON.decode(EngineConfig.self, from: older)
        #expect(config.hashAnchor.destination == .directory)

        // A freshly created one defaults to iCloud, because an anchor stored on
        // the Mac it describes is not evidence.
        #expect(EngineConfig().hashAnchor.destination == .iCloudDrive)
    }

    @Test("an unreadable config throws instead of yielding defaults")
    func unreadableThrows() throws {
        let temporary = try TemporaryDirectory()
        let missing = temporary.appendingPathComponent("nope.json")
        #expect(throws: ConfigError.self) { _ = try EngineConfig.load(from: missing) }

        let malformed = temporary.appendingPathComponent("bad.json")
        try Data("{ not json".utf8).write(to: malformed)
        #expect(throws: ConfigError.self) { _ = try EngineConfig.load(from: malformed) }
    }

    @Test("the gap threshold is three missed heartbeats")
    func gapThreshold() {
        #expect(HeartbeatConfig(intervalSeconds: 60).gapThreshold == 180)
        #expect(HeartbeatConfig(intervalSeconds: 30).gapThreshold == 90)
    }
}

@Suite("Config validation")
struct ConfigValidationTests {

    private func config(ledgerPath: String?) -> EngineConfig {
        EngineConfig(storage: StorageConfig(ledgerPath: ledgerPath))
    }

    @Test("a tilde storage path is an error under the sandbox")
    func tildeIsAnErrorWhenSandboxed() {
        let issues = ConfigValidator.issues(
            in: config(ledgerPath: "~/Library/Application Support/MythLog/events.jsonl"),
            environment: .sandboxed()
        )
        let issue = issues.first { $0.field == "storage.ledgerPath" }
        #expect(issue?.severity == .error)
        #expect(issue?.message.contains(SandboxEnvironment.unavailablePrefix) == true)
    }

    @Test("the same tilde path is only a warning unsandboxed, where it works")
    func tildeIsAWarningWhenUnsandboxed() {
        let issues = ConfigValidator.issues(
            in: config(ledgerPath: "~/Library/Application Support/MythLog/events.jsonl"),
            environment: .unsandboxed
        )
        #expect(issues.first { $0.field == "storage.ledgerPath" }?.severity == .warning)
    }

    @Test("an absolute container path is clean in both environments")
    func absoluteContainerPathIsClean() {
        let path = "/Users/example/Library/Group Containers/TEAM.shared/Application Support/MythLog/events.jsonl"
        for environment in [SandboxEnvironment.sandboxed(), .unsandboxed] {
            let issues = ConfigValidator.issues(in: config(ledgerPath: path), environment: environment)
            #expect(issues.allSatisfy { $0.field != "storage.ledgerPath" })
        }
    }

    @Test("a relative storage path is always an error")
    func relativePathIsAnError() {
        let issues = ConfigValidator.issues(in: config(ledgerPath: "events.jsonl"), environment: .unsandboxed)
        #expect(issues.first { $0.field == "storage.ledgerPath" }?.severity == .error)
    }

    @Test("a development fallback key is an error")
    func fallbackKeyIsAnError() {
        let config = EngineConfig(secrets: SecretConfig(allowDevelopmentFallbackKey: true))
        let issues = ConfigValidator.issues(in: config, environment: .unsandboxed)
        #expect(issues.first { $0.field == "secrets.allowDevelopmentFallbackKey" }?.severity == .error)
        #expect(!ConfigValidator.isUsable(config, environment: .unsandboxed))
    }

    @Test("anchors written inside the container they protect are an error")
    func anchorInsideContainerIsAnError() {
        let containerURL = URL(fileURLWithPath: "/private/GroupContainers/TEAM.shared", isDirectory: true)
        let config = EngineConfig(
            hashAnchor: HashAnchorConfig(
                directory: "/private/GroupContainers/TEAM.shared/anchors", destination: .directory))

        let issues = ConfigValidator.issues(
            in: config, environment: .sandboxed(), container: .fixed(containerURL))
        #expect(issues.first { $0.field == "hashAnchor.directory" }?.severity == .error)
    }

    @Test("disabled heartbeats are a warning about gap detection specifically")
    func disabledHeartbeatWarnsAboutGaps() {
        let config = EngineConfig(heartbeat: HeartbeatConfig(enabled: false))
        let issue = ConfigValidator.issues(in: config, environment: .unsandboxed)
            .first { $0.field == "heartbeat.enabled" }
        #expect(issue?.severity == .warning)
        #expect(issue?.message.contains("force-quit") == true)
    }

    @Test("tildes in sections this build does not model are still reported when sandboxed")
    func unmodelledTildesAreReported() throws {
        let config = try EngineConfig.load(
            from: LedgerFixtures.testsDirectory
                .appendingPathComponent("Fixtures/shipping-config/default-unsandboxed.json"))

        let issues = ConfigValidator.issues(in: config, environment: .sandboxed())
        // `filesystem.watchedPaths` carries ~/.ssh/authorized_keys.
        #expect(issues.contains { $0.field.hasPrefix("filesystem.") })
        #expect(issues.allSatisfy { !$0.field.hasPrefix("filesystem.") || $0.severity == .warning })
    }

    @Test("the shipping app's own sandboxed default is usable; its unsandboxed one is not, under the sandbox")
    func shippingDefaultsAreJudgedCorrectly() throws {
        let base = LedgerFixtures.testsDirectory.appendingPathComponent("Fixtures/shipping-config")
        let sandboxed = try EngineConfig.load(from: base.appendingPathComponent("installed-sandboxed.json"))
        let unsandboxed = try EngineConfig.load(from: base.appendingPathComponent("default-unsandboxed.json"))

        #expect(ConfigValidator.isUsable(sandboxed, environment: .sandboxed()))
        // This is the config that shipped the bug: correct on a developer's Mac,
        // silently wrong once sandboxed.
        #expect(!ConfigValidator.isUsable(unsandboxed, environment: .sandboxed()))
        #expect(ConfigValidator.isUsable(unsandboxed, environment: .unsandboxed))
    }

    @Test("validation never modifies the config it inspects")
    func validationIsPure() {
        let original = EngineConfig(storage: StorageConfig(ledgerPath: "~/broken"))
        var copy = original
        _ = ConfigValidator.issues(in: copy, environment: .sandboxed())
        #expect(copy == original)
        copy.schemaVersion = 9
        #expect(copy != original)
    }
}
