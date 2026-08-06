import Foundation
import Testing

@testable import MythLog

/// The refactor's contract: both shipped destinations behind one protocol, with
/// no behaviour change.
@Suite("Anchor destinations")
struct AnchorDestinationTests {

    private func anchor(records: Int, hash: String = "abc", at: Date = .now) -> LedgerHashAnchor {
        LedgerHashAnchor(
            createdAt: at,
            deviceID: "test",
            ledgerPath: "/tmp/events.jsonl",
            recordCount: records,
            lastHash: hash,
            isLedgerValid: true,
            reason: "test"
        )
    }

    @Test("a directory destination writes latest and appends to history")
    func directoryWritesBoth() async throws {
        let temporary = try TemporaryDirectory()
        let destination = DirectoryAnchorDestination(directory: temporary.url)

        try await destination.write(anchor(records: 10, hash: "aaa"))
        try await destination.write(anchor(records: 20, hash: "bbb"))

        #expect(try await destination.latest()?.recordCount == 20)

        // The history is append-only, which is what makes a rolled-back
        // "latest" detectable: overwriting the newest anchor still leaves a
        // history that ends somewhere else.
        let history = try await destination.history()
        #expect(history.map(\.recordCount) == [10, 20])
    }

    @Test("an empty destination has no latest and no history")
    func emptyDestination() async throws {
        let temporary = try TemporaryDirectory()
        let destination = DirectoryAnchorDestination(directory: temporary.appendingPathComponent("nothing"))

        #expect(try await destination.latest() == nil)
        #expect(try await destination.history().isEmpty)
    }

    @Test("a resolving destination writes wherever it currently resolves to")
    func resolvingDestinationDefersResolution() async throws {
        let temporary = try TemporaryDirectory()
        let first = temporary.appendingPathComponent("first")
        let second = temporary.appendingPathComponent("second")

        // A box the closure captures, standing in for iCloud moving under us.
        final class Target: @unchecked Sendable {
            // Guarded by the test's own sequential use — every read and write
            // happens on the test's single task, with the writes strictly
            // between the awaits. No concurrency exists here to race with.
            var url: URL
            init(url: URL) { self.url = url }
        }
        let target = Target(url: first)

        let destination = ResolvingAnchorDestination(describedLocation: "moving") { target.url }
        try await destination.write(anchor(records: 1))

        target.url = second
        try await destination.write(anchor(records: 2))

        // Resolution happens per operation, so the second anchor landed in the
        // second directory. A destination that resolved once at construction
        // would have written both to `first` — and would keep writing to a
        // stale path after a user signed out of iCloud.
        #expect(try await DirectoryAnchorDestination(directory: first).latest()?.recordCount == 1)
        #expect(try await DirectoryAnchorDestination(directory: second).latest()?.recordCount == 2)
    }

    @Test("a destination that cannot resolve throws rather than writing elsewhere")
    func unresolvableDestinationThrows() async throws {
        let destination = ResolvingAnchorDestination(describedLocation: "nowhere") {
            throw PlatformError.anchorDestinationUnavailable(detail: "signed out")
        }

        // An anchor written somewhere the user did not choose looks like the
        // protection is on. Failing is the correct outcome.
        await #expect(throws: PlatformError.self) {
            try await destination.write(
                LedgerHashAnchor(
                    deviceID: "t", ledgerPath: "/tmp/x", recordCount: 1,
                    lastHash: "a", isLedgerValid: true, reason: "t"))
        }
    }

    @Test("a disabled destination is a state, not an absence")
    func disabledDestination() async throws {
        let destination = DisabledAnchorDestination()
        // Writing is a no-op rather than an error: the user switched it off,
        // which is a choice and not a fault.
        try await destination.write(
            LedgerHashAnchor(
                deviceID: "t", ledgerPath: "/tmp/x", recordCount: 1,
                lastHash: "a", isLedgerValid: true, reason: "t"))
        #expect(try await destination.latest() == nil)
        #expect(destination.describedLocation == "not anchored")
    }
}

@Suite("Anchor locations")
struct AnchorLocationsTests {

    private let cloudDocs = URL(fileURLWithPath: "/Users/example/Library/Mobile Documents/com~apple~CloudDocs/MythLog")

    @Test("unsandboxed iCloud resolves to the visible CloudDocs folder")
    func unsandboxedICloud() throws {
        let locations = AnchorLocations(
            environment: .unsandboxed,
            ubiquity: FixedUbiquityContainerResolver(url: nil),
            iCloudDriveDirectory: cloudDocs
        )
        #expect(try locations.directory(for: .iCloudDrive, chosenDirectory: nil) == cloudDocs)
    }

    @Test("sandboxed iCloud resolves inside the ubiquity container")
    func sandboxedICloud() throws {
        let container = URL(fileURLWithPath: "/private/Ubiquity/iCloud.com.jctec.mythlog")
        let locations = AnchorLocations(
            environment: .sandboxed(),
            ubiquity: FixedUbiquityContainerResolver(url: container),
            iCloudDriveDirectory: cloudDocs
        )
        let resolved = try locations.directory(for: .iCloudDrive, chosenDirectory: nil)
        #expect(resolved.path == container.appendingPathComponent("Documents/MythLog").path)
    }

    @Test("signed out of iCloud throws — it never falls back to a local folder")
    func signedOutThrows() {
        let locations = AnchorLocations(
            environment: .sandboxed(),
            ubiquity: FixedUbiquityContainerResolver(url: nil),
            iCloudDriveDirectory: cloudDocs
        )
        #expect(throws: PlatformError.self) {
            _ = try locations.directory(for: .iCloudDrive, chosenDirectory: nil)
        }
        // And it says so rather than going blank: "aimed at somewhere that is
        // not there" and "not anchoring" are different states.
        let description = locations.describe(.iCloudDrive, chosenDirectory: nil)
        #expect(description.contains("signed out"))
        #expect(!description.isEmpty)
    }

    @Test("a chosen directory is used verbatim, and an unset one is refused")
    func chosenDirectory() throws {
        let locations = AnchorLocations(
            environment: .unsandboxed,
            ubiquity: FixedUbiquityContainerResolver(url: nil),
            iCloudDriveDirectory: cloudDocs
        )
        #expect(
            try locations.directory(for: .directory, chosenDirectory: "/Volumes/KEY/MythLog").path
                == "/Volumes/KEY/MythLog")

        #expect(throws: PlatformError.self) {
            _ = try locations.directory(for: .directory, chosenDirectory: nil)
        }
    }
}

@Suite("Anchor settings")
struct AnchorSettingsTests {

    @Test("the config's destination maps onto a choice with threat copy")
    func settingsFromConfig() {
        let settings = AnchorSettings(
            config: HashAnchorConfig(directory: "/Volumes/KEY", destination: .directory))

        #expect(settings.choice.kind == .directory)
        #expect(settings.chosenDirectory == "/Volumes/KEY")
        #expect(settings.isEnabled)
    }

    /// The whole point of Phase C: the copy answers "who does this keep it away
    /// from?", not "which folder?".
    @Test("every choice states who it keeps the anchor away from, and who it does not")
    func copyIsAboutThreatNotPath() {
        for choice in AnchorChoice.all {
            #expect(!choice.keepsItAwayFrom.isEmpty)
            #expect(!choice.protects.isEmpty)
            #expect(!choice.doesNotProtect.isEmpty, "\(choice.title) claims no weaknesses")
            // A path in the headline would be the old framing sneaking back.
            #expect(!choice.keepsItAwayFrom.contains("/"))
        }
    }

    /// `docs/ANCHOR_DESTINATIONS.md` open question 1. For someone in a hostile
    /// household the feature meant to protect them can announce them.
    @Test("both choices warn that a synced folder is visible to the adversary too")
    func visibilityWarningExists() {
        for choice in AnchorChoice.all {
            let warning = choice.visibilityWarning
            #expect(warning != nil, "\(choice.title) has no visibility warning")
            #expect(warning?.isEmpty == false)
        }
        #expect(AnchorChoice.iCloudDrive.visibilityWarning?.contains("every device") == true)
    }

    @Test("the USB case is stated as a recommendation, not buried in a bullet")
    func usbCaseIsDiscoverable() {
        // It already worked and nobody knew. Making it findable is the cheapest
        // real-world gain in the whole document.
        #expect(AnchorChoice.usbKeySuggestion.contains("USB key"))
        #expect(AnchorChoice.usbKeySuggestion.contains("needs nothing new"))
    }

    @Test("exactly one choice is the default")
    func oneDefault() {
        #expect(AnchorChoice.all.filter(\.isDefault).count == 1)
    }

    @Test("disabled settings produce a disabled destination, not a broken one")
    func disabledSettings() {
        let destination = AnchorSettings(isEnabled: false).makeDestination()
        #expect(destination is DisabledAnchorDestination)
    }

    @Test("enabled settings produce a destination that defers resolution")
    func enabledSettingsResolveLazily() {
        let locations = AnchorLocations(
            environment: .sandboxed(),
            ubiquity: FixedUbiquityContainerResolver(url: nil),
            iCloudDriveDirectory: URL(fileURLWithPath: "/tmp")
        )
        // Signed out of iCloud, yet building the destination still succeeds —
        // resolution is the write's job, so the settings screen can describe a
        // destination that is not currently reachable.
        let destination = AnchorSettings(isEnabled: true, choice: .iCloudDrive)
            .makeDestination(locations: locations)
        #expect(destination is ResolvingAnchorDestination)
        #expect(destination.describedLocation.contains("signed out"))
    }
}

@Suite("Anchor settings page")
struct AnchorSettingsPageModelTests {

    @MainActor
    @Test("selecting a choice changes it, and the settings value follows")
    func selection() {
        let model = AnchorSettingsPage.Model(
            settings: AnchorSettings(isEnabled: true, choice: .iCloudDrive),
            locations: StaticAnchorLocationDescription(answers: [:])
        )
        #expect(model.isSelected(.iCloudDrive))

        model.select(.chosenFolder)
        #expect(model.isSelected(.chosenFolder))
        #expect(model.settings.choice.kind == .directory)
    }

    @MainActor
    @Test("the resolved location is never blank")
    func resolvedLocationIsNeverBlank() {
        let model = AnchorSettingsPage.Model(
            settings: AnchorSettings(),
            locations: StaticAnchorLocationDescription(answers: [:])
        )
        for choice in AnchorChoice.all {
            #expect(!model.resolvedLocation(for: choice).isEmpty)
        }
    }
}
