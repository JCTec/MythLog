import Foundation
import Testing

@testable import MythLog

/// The Wave 2 gate, in test form: one type answers "where does everything live",
/// and it never guesses.
///
/// These are the regression tests for the 1.0.0 bug. Every one of them would
/// have failed against the shipped behaviour.
@Suite("Storage locations")
struct StorageLocationTests {

    @Test("unsandboxed, everything lives under the user's Library")
    func unsandboxedUsesUserLibrary() throws {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let locations = try StorageLocations.resolve(environment: .unsandboxed, home: home)

        #expect(locations.origin == .userLibrary)
        #expect(locations.base.path == "/Users/example/Library/Application Support/MythLog")
        #expect(locations.ledgerURL.path == "/Users/example/Library/Application Support/MythLog/events.jsonl")
        #expect(locations.configURL.path == "/Users/example/Library/Application Support/MythLog/config.json")
    }

    @Test("sandboxed, everything lives in the shared App Group container")
    func sandboxedUsesAppGroupContainer() throws {
        let container = URL(fileURLWithPath: "/Users/example/Library/Group Containers/TEAM.shared", isDirectory: true)
        let locations = try StorageLocations.resolve(
            environment: .sandboxed(),
            container: .fixed(container),
            home: URL(fileURLWithPath: "/Users/example", isDirectory: true)
        )

        #expect(locations.origin == .appGroupContainer(group: SharedContainer.groupIdentifier))
        #expect(locations.base.path.hasPrefix(container.path))
        #expect(locations.ledgerURL.path.hasPrefix(container.path))
    }

    /// The bug itself. The viewer and the recorder resolved different files and
    /// nothing said so.
    @Test("sandboxed and unsandboxed resolve to different files, and the sandboxed one is not under home")
    func sandboxedNeverResolvesIntoAPrivateContainer() throws {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let container = URL(fileURLWithPath: "/private/GroupContainers/TEAM.shared", isDirectory: true)

        let viewer = try StorageLocations.resolve(environment: .unsandboxed, home: home)
        let recorder = try StorageLocations.resolve(
            environment: .sandboxed(), container: .fixed(container), home: home)

        #expect(viewer.ledgerURL != recorder.ledgerURL)
        #expect(!recorder.ledgerURL.path.hasPrefix(home.path))
    }

    @Test("an unresolvable container throws instead of substituting a path")
    func unresolvableContainerThrows() {
        #expect(throws: PlatformError.appGroupUnavailable(group: SharedContainer.groupIdentifier)) {
            _ = try StorageLocations.resolve(environment: .sandboxed(), container: .unavailable)
        }
    }

    @Test("the failure names the sandbox in the one greppable phrasing")
    func failureIsAttributed() {
        let message = PlatformError.appGroupUnavailable(group: "TEAM.shared").localizedDescription
        #expect(message.contains(SandboxEnvironment.unavailablePrefix))
        #expect(message.contains("TEAM.shared"))
    }

    @Test("no resolved path contains a tilde, in either environment")
    func noResolvedPathIsTildeRooted() throws {
        let container = URL(fileURLWithPath: "/private/GroupContainers/TEAM.shared", isDirectory: true)
        let both = [
            try StorageLocations.resolve(
                environment: .unsandboxed, home: URL(fileURLWithPath: "/Users/example", isDirectory: true)),
            try StorageLocations.resolve(environment: .sandboxed(), container: .fixed(container)),
        ]

        for locations in both {
            for url in [
                locations.base, locations.ledgerURL, locations.configURL,
                locations.runtimeDirectory, locations.spoolDirectory,
                locations.outboxDirectory, locations.logDirectory,
            ] {
                #expect(!url.path.contains("~"), "\(url.path)")
                #expect(url.path.hasPrefix("/"), "\(url.path)")
            }
        }
    }

    @Test("every location is derived from one base")
    func everythingHangsOffTheBase() {
        let locations = StorageLocations.rooted(at: URL(fileURLWithPath: "/tmp/anywhere", isDirectory: true))
        for url in [
            locations.ledgerURL, locations.configURL, locations.runtimeDirectory,
            locations.spoolDirectory, locations.outboxDirectory,
        ] {
            #expect(url.path.hasPrefix(locations.base.path))
        }
    }

    @Test("the origin is explained, not just recorded")
    func originIsExplained() throws {
        let unsandboxed = try StorageLocations.resolve(
            environment: .unsandboxed, home: URL(fileURLWithPath: "/Users/example", isDirectory: true))
        #expect(unsandboxed.explanation.contains("does not run under the App Sandbox"))

        let sandboxed = try StorageLocations.resolve(
            environment: .sandboxed(),
            container: .fixed(URL(fileURLWithPath: "/private/GroupContainers/x", isDirectory: true))
        )
        #expect(sandboxed.explanation.contains("App Group"))
    }
}

@Suite("Sandbox detection")
struct SandboxEnvironmentTests {

    @Test("the container variable's presence is the signal")
    func detectsFromEnvironment() {
        #expect(SandboxEnvironment.current(environment: [:]).isSandboxed == false)

        let sandboxed = SandboxEnvironment.current(
            environment: [SandboxEnvironment.containerVariable: "com.jctec.mythlog"])
        #expect(sandboxed.isSandboxed)
        #expect(sandboxed.containerIdentifier == "com.jctec.mythlog")
    }

    @Test("every unavailability message shares one greppable prefix")
    func phrasingIsUniform() {
        let reason = SandboxEnvironment.unavailableReason("the thing could not be done")
        #expect(reason.hasPrefix(SandboxEnvironment.unavailablePrefix))
        #expect(reason == "unavailable under App Sandbox: the thing could not be done.")
    }

    @Test("detection is a value, so two environments can coexist in one process")
    func environmentsAreIndependentValues() {
        // The point of not using a global: these are simultaneously true.
        let a = SandboxEnvironment.unsandboxed
        let b = SandboxEnvironment.sandboxed(containerIdentifier: "x")
        #expect(a.isSandboxed == false)
        #expect(b.isSandboxed == true)
        #expect(a != b)
    }
}

@Suite("Container membership")
struct SharedContainerTests {

    @Test("a path inside the container is recognised; one beside it is not")
    func containmentIsPrefixSafe() {
        let container = SharedContainer.fixed(
            URL(fileURLWithPath: "/private/GroupContainers/TEAM.shared", isDirectory: true))

        #expect(container.contains("/private/GroupContainers/TEAM.shared"))
        #expect(container.contains("/private/GroupContainers/TEAM.shared/Application Support/MythLog"))
        // The case a naive `hasPrefix` gets wrong.
        #expect(!container.contains("/private/GroupContainers/TEAM.shared-other/x"))
        #expect(!container.contains("/Users/example/Documents"))
    }

    @Test("an unresolvable container treats every path as outside")
    func unresolvableContainerExcludesEverything() {
        #expect(!SharedContainer.unavailable.contains("/anything"))
    }
}

@Suite("Process entitlements")
struct ProcessEntitlementsTests {

    @Test("a declared entitlement is read back")
    func readsDeclaredValues() {
        let entitlements = ProcessEntitlements.declaring([ProcessEntitlements.networkClientKey: true])
        #expect(entitlements.hasNetworkClient)
        #expect(entitlements.bool(ProcessEntitlements.networkClientKey) == true)
    }

    @Test("an absent entitlement reads as absent, not as granted")
    func absenceIsNotPermission() {
        #expect(ProcessEntitlements.none.hasNetworkClient == false)
        #expect(ProcessEntitlements.none.bool("anything") == nil)
    }
}

@Suite("Diagnostics subsystem")
struct DiagnosticsTests {

    /// If these two are ever the same string, the recorder ingests its own debug
    /// output into the ledger as user events.
    @Test("diagnostics never share the subsystem the recorder ingests")
    func subsystemsAreDistinct() {
        #expect(Diagnostics.subsystem != Diagnostics.ingestedSubsystem)
        #expect(Diagnostics.subsystem == "com.jctec.mythlog.diagnostics")
    }
}
