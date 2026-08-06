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

/// A viewer looking for somebody else's install cannot assume they share a
/// sandbox. This app is unsandboxed; the recorder people actually have is not.
@Suite("Finding an install that is not ours")
struct InstalledCandidateTests {

    private let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)

    @Test("the App Group container is checked first, the Library layout second")
    func containerComesFirst() {
        let containerURL = URL(fileURLWithPath: "/Users/example/Library/Group Containers/TEAM.shared")
        let candidates = StorageLocations.installedCandidates(
            container: .fixed(containerURL), home: home)

        #expect(candidates.count == 2)
        // A sandboxed recorder is the shipping configuration, so its location is
        // the one worth checking first.
        #expect(candidates[0].origin == .appGroupContainer(group: SharedContainer.groupIdentifier))
        #expect(candidates[0].base.path.hasPrefix(containerURL.path))
        #expect(candidates[1].origin == .userLibrary)
        #expect(candidates[1].base.path == "/Users/example/Library/Application Support/MythLog")
    }

    @Test("an unresolvable container still leaves the Library layout to check")
    func containerUnavailableStillOffersLibrary() {
        let candidates = StorageLocations.installedCandidates(container: .unavailable, home: home)
        #expect(candidates.count == 1)
        #expect(candidates[0].origin == .userLibrary)
    }

    /// The regression this exists for: the install is in the App Group
    /// container, the viewer is unsandboxed, and `resolve` alone would look only
    /// at `~/Library` and report an absence that is not there.
    @Test("an install in the container is found by an unsandboxed viewer")
    func containerInstallIsFoundFromUnsandboxed() throws {
        let temporary = try TemporaryDirectory()
        let containerURL = temporary.appendingPathComponent("GroupContainer")
        let installed = containerURL
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("MythLog", isDirectory: true)
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: installed.appendingPathComponent("config.json"))

        // Resolving our own convention finds nothing…
        let ourOwn = try StorageLocations.resolve(environment: .unsandboxed, home: temporary.url)
        #expect(!FileManager.default.fileExists(atPath: ourOwn.configURL.path))

        // …but looking at every plausible location finds the real install.
        let found = StorageLocations.firstInstalled(
            containing: \.configURL, container: .fixed(containerURL), home: temporary.url)
        #expect(found?.base.path == installed.path)
        #expect(found?.origin == .appGroupContainer(group: SharedContainer.groupIdentifier))
    }

    @Test("nothing installed anywhere is nil, not a guess")
    func nothingInstalled() throws {
        let temporary = try TemporaryDirectory()
        #expect(
            StorageLocations.firstInstalled(
                containing: \.configURL, container: .unavailable, home: temporary.url) == nil)
    }

    @Test("the marker decides which install counts")
    func markerSelectsTheInstall() throws {
        let temporary = try TemporaryDirectory()
        // A container with a ledger but no config, and a Library with a config
        // but no ledger. Which one is "installed" depends on what you are
        // looking for, which is why the caller says.
        let containerURL = temporary.appendingPathComponent("GroupContainer")
        let containerBase = containerURL
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("MythLog", isDirectory: true)
        try FileManager.default.createDirectory(at: containerBase, withIntermediateDirectories: true)
        try Data("{}\n".utf8).write(to: containerBase.appendingPathComponent("events.jsonl"))

        let libraryBase = temporary.url
            .appendingPathComponent("Library/Application Support/MythLog", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryBase, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: libraryBase.appendingPathComponent("config.json"))

        #expect(
            StorageLocations.firstInstalled(
                containing: \.ledgerURL, container: .fixed(containerURL), home: temporary.url)?
                .base.path == containerBase.path)
        #expect(
            StorageLocations.firstInstalled(
                containing: \.configURL, container: .fixed(containerURL), home: temporary.url)?
                .base.path == libraryBase.path)
    }
}
