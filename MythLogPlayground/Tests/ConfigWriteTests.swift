import Foundation
import Testing

@testable import MythLog

/// Writing a config the recorder depends on.
///
/// The rule that governs all of this is in `docs/CONFIG_OWNERSHIP.md`: the
/// viewer is the only writer at runtime, writes atomically, validates first, and
/// never drops a key it does not understand.
@Suite("Writing the config")
struct ConfigWriteTests {

    /// A config with sections this build does not model, exactly as the recorder
    /// writes them.
    private func writeInstalledConfig(
        at url: URL,
        extra: String = """
            ,
            "telegram" : { "enabled" : false, "approvedChatIDs" : [ 12345 ] },
            "filesystem" : { "watchedPaths" : [ { "label" : "ssh", "path" : "/etc/ssh", "required" : false } ] },
            "rules" : [ { "id" : "screen-unlocked", "severity" : "critical" } ],
            "somethingFromTheFuture" : { "nested" : { "deep" : [ 1, 2.5, true, null ] } }
            """
    ) throws {
        let json = """
            {
              "schemaVersion" : 1,
              "identity" : { "deviceID" : "Test Mac", "displayName" : "Test Mac" },
              "secrets" : { "allowDevelopmentFallbackKey" : false, "hmacKeyAccount" : "ledger-hmac-key" },
              "heartbeat" : { "checkpointEveryHeartbeats" : 5, "enabled" : true, "intervalSeconds" : 60 },
              "hashAnchor" : { "anchorEveryHeartbeats" : 5, "destination" : "iCloudDrive", "enabled" : true }\(extra)
            }
            """
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    // MARK: - The one that matters

    /// Wave 3 built a lossless round-trip for exactly this reason. A save that
    /// dropped `filesystem` would delete the user's watched paths as a side
    /// effect of changing where a hash goes.
    @Test("every unknown section survives a read-modify-write")
    func unknownSectionsSurvive() throws {
        let temporary = try TemporaryDirectory()
        let configURL = temporary.appendingPathComponent("config.json")
        try writeInstalledConfig(at: configURL)

        let outcome = ConfigWriter(configURL: configURL, environment: .unsandboxed)
            .apply(recorderIsRunning: false) { config in
                var updated = config
                updated.hashAnchor.destination = .directory
                updated.hashAnchor.directory = "/Volumes/KEY/MythLog"
                return updated
            }
        #expect(outcome.didWrite)

        let reloaded = try EngineConfig.load(from: configURL)

        // The change landed…
        #expect(reloaded.hashAnchor.destination == .directory)
        #expect(reloaded.hashAnchor.directory == "/Volumes/KEY/MythLog")

        // …and nothing else moved.
        #expect(reloaded.identity.deviceID == "Test Mac")
        #expect(reloaded.heartbeat.intervalSeconds == 60)
        for section in ["telegram", "filesystem", "rules", "somethingFromTheFuture"] {
            #expect(reloaded.unmodelled[section] != nil, "\(section) was dropped by the write")
        }

        // Including the parts of them nothing here can even name.
        #expect(
            reloaded.unmodelled["somethingFromTheFuture"]
                == .object(["nested": .object(["deep": .array([.int(1), .double(2.5), .bool(true), .null])])])
        )
    }

    @Test("a section this build does not model round-trips byte for byte through a save")
    func unknownSectionsAreByteIdentical() throws {
        let temporary = try TemporaryDirectory()
        let configURL = temporary.appendingPathComponent("config.json")
        try writeInstalledConfig(at: configURL)

        let before = try EngineConfig.load(from: configURL)

        // A save that changes nothing at all must still not damage the file.
        _ = ConfigWriter(configURL: configURL, environment: .unsandboxed)
            .apply(recorderIsRunning: false) { $0 }

        #expect(try EngineConfig.load(from: configURL).unmodelled == before.unmodelled)
    }

    // MARK: - Validation

    @Test("an invalid config is refused before anything is written")
    func invalidConfigIsRefused() throws {
        let temporary = try TemporaryDirectory()
        let configURL = temporary.appendingPathComponent("config.json")
        try writeInstalledConfig(at: configURL)
        let original = try Data(contentsOf: configURL)

        let outcome = ConfigWriter(configURL: configURL, environment: .unsandboxed)
            .apply(recorderIsRunning: false) { config in
                var updated = config
                // An invalid config can stop the recorder from starting, which
                // for this product means silently not recording.
                updated.secrets.allowDevelopmentFallbackKey = true
                return updated
            }

        guard case .refused(let reason) = outcome else {
            Issue.record("expected .refused, got \(outcome)")
            return
        }
        #expect(reason.contains("secrets.allowDevelopmentFallbackKey"))
        #expect(!outcome.didWrite)

        // Nothing on disk changed. Not "mostly nothing" — the same bytes.
        #expect(try Data(contentsOf: configURL) == original)
    }

    @Test("a config that cannot be read is never overwritten with defaults")
    func unreadableConfigIsNotReplaced() throws {
        let temporary = try TemporaryDirectory()
        let configURL = temporary.appendingPathComponent("config.json")
        try Data("{ this is not json".utf8).write(to: configURL)
        let original = try Data(contentsOf: configURL)

        let outcome = ConfigWriter(configURL: configURL, environment: .unsandboxed)
            .apply(recorderIsRunning: false) { $0 }

        // Replacing a file we cannot parse with one built from defaults is data
        // loss dressed as a repair.
        #expect(!outcome.didWrite)
        #expect(try Data(contentsOf: configURL) == original)
    }

    // MARK: - How it is written

    @Test("the written file is owner-only")
    func permissionsAreTightened() throws {
        let temporary = try TemporaryDirectory()
        let configURL = temporary.appendingPathComponent("config.json")
        try writeInstalledConfig(at: configURL)
        // Deliberately loosened first: an atomic write replaces the file, so the
        // new one does not inherit the old one's mode and the writer has to set
        // it every time.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: configURL.path)

        _ = ConfigWriter(configURL: configURL, environment: .unsandboxed)
            .apply(recorderIsRunning: false) { config in
                var updated = config
                updated.hashAnchor.enabled = false
                return updated
            }

        let mode = try FileManager.default.attributesOfItem(atPath: configURL.path)[.posixPermissions]
        #expect((mode as? NSNumber)?.int16Value == 0o600)
    }

    @Test("a change that changes nothing does not rewrite the file")
    func noOpDoesNotTouchTheFile() throws {
        let temporary = try TemporaryDirectory()
        let configURL = temporary.appendingPathComponent("config.json")
        try writeInstalledConfig(at: configURL)

        let before = try FileManager.default.attributesOfItem(atPath: configURL.path)[.modificationDate] as? Date
        let outcome = ConfigWriter(configURL: configURL, environment: .unsandboxed)
            .apply(recorderIsRunning: false) { $0 }
        let after = try FileManager.default.attributesOfItem(atPath: configURL.path)[.modificationDate] as? Date

        // Reported as a success — there is nothing left to do — without churning
        // a modification date that other things watch for staleness.
        #expect(outcome.didWrite)
        #expect(before == after)
    }

    // MARK: - Ownership

    @Test("a running recorder changes the outcome, not the write")
    func runningRecorderIsReportedNotObeyed() throws {
        let temporary = try TemporaryDirectory()
        let configURL = temporary.appendingPathComponent("config.json")
        try writeInstalledConfig(at: configURL)

        let outcome = ConfigWriter(configURL: configURL, environment: .unsandboxed)
            .apply(recorderIsRunning: true) { config in
                var updated = config
                updated.hashAnchor.enabled = false
                return updated
            }

        // The recorder never writes this file, so there is no race to lose —
        // the write happens. What changes is what the user is told.
        guard case .writtenPendingRecorderRestart = outcome else {
            Issue.record("expected .writtenPendingRecorderRestart, got \(outcome)")
            return
        }
        #expect(try EngineConfig.load(from: configURL).hashAnchor.enabled == false)
    }
}

@Suite("Recorder presence")
struct RecorderPresenceTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func writeStatus(
        at url: URL, state: String, generatedAt: Date
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let json = """
            { "state" : "\(state)", "generatedAt" : "\(generatedAt.formatted(.iso8601))", "processID" : 123 }
            """
        try Data(json.utf8).write(to: url)
    }

    @Test("a fresh running status means a recorder is running")
    func freshRunningStatus() throws {
        let temporary = try TemporaryDirectory()
        let statusURL = temporary.appendingPathComponent("runtime/status.json")
        try writeStatus(at: statusURL, state: "running", generatedAt: now.addingTimeInterval(-30))

        let presence = RecorderPresence(statusURL: statusURL, heartbeatInterval: 60)
        #expect(presence.isRecorderRunning(now: now))
    }

    /// The case that decides whether the interface promises a restart that is
    /// never coming: a force-quit recorder leaves its last status file behind
    /// for ever.
    @Test("a stale status file means the recorder is gone, not running")
    func staleStatusMeansGone() throws {
        let temporary = try TemporaryDirectory()
        let statusURL = temporary.appendingPathComponent("runtime/status.json")
        try writeStatus(at: statusURL, state: "running", generatedAt: now.addingTimeInterval(-600))

        let presence = RecorderPresence(statusURL: statusURL, heartbeatInterval: 60)
        #expect(!presence.isRecorderRunning(now: now))
        // Three missed refreshes at a 60 s heartbeat.
        #expect(presence.stalenessThreshold == 180)
    }

    @Test("staleness follows the configured heartbeat, not a constant")
    func stalenessFollowsHeartbeat() throws {
        let temporary = try TemporaryDirectory()
        let statusURL = temporary.appendingPathComponent("runtime/status.json")
        try writeStatus(at: statusURL, state: "running", generatedAt: now.addingTimeInterval(-600))

        // A recorder configured to write every five minutes is not stale after
        // ten, and judging it against a constant would say otherwise.
        #expect(RecorderPresence(statusURL: statusURL, heartbeatInterval: 300).isRecorderRunning(now: now))
    }

    @Test("a stopped recorder is not running however fresh the file is")
    func stoppedIsNotRunning() throws {
        let temporary = try TemporaryDirectory()
        let statusURL = temporary.appendingPathComponent("runtime/status.json")
        try writeStatus(at: statusURL, state: "stopped", generatedAt: now)

        #expect(!RecorderPresence(statusURL: statusURL, heartbeatInterval: 60).isRecorderRunning(now: now))
    }

    @Test("no status file at all means nothing is running")
    func noStatusFile() throws {
        let temporary = try TemporaryDirectory()
        let presence = RecorderPresence(
            statusURL: temporary.appendingPathComponent("runtime/status.json"), heartbeatInterval: 60)
        #expect(!presence.isRecorderRunning(now: now))
        #expect(presence.status() == nil)
    }
}

@Suite("Anchor settings persistence")
struct AnchorSettingsStoreTests {

    private func makeInstall(in temporary: TemporaryDirectory) throws -> StorageLocations {
        let locations = StorageLocations.rooted(at: temporary.appendingPathComponent("MythLog"))
        try EngineConfig(
            identity: AgentIdentity(deviceID: "Test", displayName: "Test"),
            hashAnchor: HashAnchorConfig(enabled: true, destination: .iCloudDrive)
        ).write(to: locations.configURL)
        return locations
    }

    /// The definition of done: choosing a destination persists across a
    /// relaunch. A second store shares nothing in memory with the first.
    @Test("a saved choice is there when the app is opened again")
    func choicePersists() throws {
        let temporary = try TemporaryDirectory()
        let locations = try makeInstall(in: temporary)

        let store = AnchorSettingsStore(locations: locations)
        let result = store.save(
            AnchorSettings(isEnabled: true, choice: .chosenFolder, chosenDirectory: "/Volumes/KEY/MythLog"))
        #expect(result.isSaved)

        let reopened = AnchorSettingsStore(locations: locations).load()
        #expect(reopened?.choice.kind == .directory)
        #expect(reopened?.chosenDirectory == "/Volumes/KEY/MythLog")
        #expect(reopened?.isEnabled == true)
    }

    @Test("switching back to iCloud keeps the folder that was chosen")
    func choosingICloudDoesNotForgetTheFolder() throws {
        let temporary = try TemporaryDirectory()
        let locations = try makeInstall(in: temporary)
        let store = AnchorSettingsStore(locations: locations)

        _ = store.save(
            AnchorSettings(isEnabled: true, choice: .chosenFolder, chosenDirectory: "/Volumes/KEY/MythLog"))
        _ = store.save(
            AnchorSettings(isEnabled: true, choice: .iCloudDrive, chosenDirectory: "/Volumes/KEY/MythLog"))

        // Clearing a perfectly good path because the user is currently looking
        // at the other option would be a change they did not ask for.
        let reloaded = store.load()
        #expect(reloaded?.choice.kind == .iCloudDrive)
        #expect(reloaded?.chosenDirectory == "/Volumes/KEY/MythLog")
    }

    @Test("saving preserves fields the interface does not expose")
    func unexposedFieldsSurvive() throws {
        let temporary = try TemporaryDirectory()
        let locations = StorageLocations.rooted(at: temporary.appendingPathComponent("MythLog"))
        try EngineConfig(hashAnchor: HashAnchorConfig(anchorEveryHeartbeats: 17)).write(to: locations.configURL)

        _ = AnchorSettingsStore(locations: locations).save(AnchorSettings(isEnabled: false))

        // `anchorEveryHeartbeats` has no control on the page and must not be
        // reset to a default because something else on the page changed.
        #expect(try EngineConfig.load(from: locations.configURL).hashAnchor.anchorEveryHeartbeats == 17)
    }

    @Test("with no install there is nowhere to save, and it says so")
    func noInstallIsExplained() {
        let store = AnchorSettingsStore(locations: nil)
        #expect(!store.canSave)
        #expect(store.load() == nil)

        let result = store.save(AnchorSettings())
        #expect(!result.isSaved)
        #expect(result.kind == .refused)
        #expect(result.message.contains("no MythLog install"))
    }

    @Test("an install whose config file is missing cannot be saved into")
    func missingConfigCannotBeSaved() throws {
        let temporary = try TemporaryDirectory()
        let store = AnchorSettingsStore(
            locations: StorageLocations.rooted(at: temporary.appendingPathComponent("Empty")))
        #expect(!store.canSave)
        #expect(!store.save(AnchorSettings()).isSaved)
    }
}

@Suite("Anchor settings page saving")
struct AnchorSettingsPageSavingTests {

    private func makeInstall(in temporary: TemporaryDirectory) throws -> StorageLocations {
        let locations = StorageLocations.rooted(at: temporary.appendingPathComponent("MythLog"))
        try EngineConfig(hashAnchor: HashAnchorConfig(enabled: true, destination: .iCloudDrive))
            .write(to: locations.configURL)
        return locations
    }

    @MainActor
    @Test("nothing is offered to save until something changes")
    func savingIsOfferedOnlyWhenDirty() throws {
        let temporary = try TemporaryDirectory()
        let model = AnchorSettingsPage.Model(
            store: AnchorSettingsStore(locations: try makeInstall(in: temporary)),
            locations: StaticAnchorLocationDescription(answers: [:])
        )

        #expect(!model.hasUnsavedChanges)
        #expect(!model.canSave)

        model.select(.chosenFolder)
        #expect(model.hasUnsavedChanges)
        #expect(model.canSave)
    }

    @MainActor
    @Test("saving reports what happened, and clears once saved")
    func savingReportsAndClears() throws {
        let temporary = try TemporaryDirectory()
        let model = AnchorSettingsPage.Model(
            store: AnchorSettingsStore(locations: try makeInstall(in: temporary)),
            locations: StaticAnchorLocationDescription(answers: [:])
        )

        model.select(.chosenFolder)
        model.save()

        #expect(model.lastResult?.isSaved == true)
        #expect(model.lastResult?.at != nil)
        #expect(!model.hasUnsavedChanges)
    }

    @MainActor
    @Test("a stale result never sits beside changed settings")
    func staleResultIsCleared() throws {
        let temporary = try TemporaryDirectory()
        let model = AnchorSettingsPage.Model(
            store: AnchorSettingsStore(locations: try makeInstall(in: temporary)),
            locations: StaticAnchorLocationDescription(answers: [:])
        )

        model.select(.chosenFolder)
        model.save()
        #expect(model.lastResult != nil)

        // "Saved at 14:32" printed next to settings that have since changed is
        // exactly the ambiguity this page exists to remove.
        model.select(.iCloudDrive)
        #expect(model.lastResult == nil)
    }

    @MainActor
    @Test("reverting restores what is on disk")
    func revertRestores() throws {
        let temporary = try TemporaryDirectory()
        let model = AnchorSettingsPage.Model(
            store: AnchorSettingsStore(locations: try makeInstall(in: temporary)),
            locations: StaticAnchorLocationDescription(answers: [:])
        )

        model.select(.chosenFolder)
        model.isEnabled = false
        #expect(model.hasUnsavedChanges)

        model.revert()
        #expect(!model.hasUnsavedChanges)
        #expect(model.isSelected(.iCloudDrive))
        #expect(model.isEnabled)
    }

    @MainActor
    @Test("the page loads what is installed rather than a default")
    func loadsFromDisk() throws {
        let temporary = try TemporaryDirectory()
        let locations = StorageLocations.rooted(at: temporary.appendingPathComponent("MythLog"))
        try EngineConfig(
            hashAnchor: HashAnchorConfig(
                enabled: false, directory: "/Volumes/KEY/MythLog", destination: .directory)
        ).write(to: locations.configURL)

        let model = AnchorSettingsPage.Model(
            store: AnchorSettingsStore(locations: locations),
            locations: StaticAnchorLocationDescription(answers: [:])
        )

        #expect(!model.isEnabled)
        #expect(model.isSelected(.chosenFolder))
        #expect(model.chosenDirectory == "/Volumes/KEY/MythLog")
    }
}
