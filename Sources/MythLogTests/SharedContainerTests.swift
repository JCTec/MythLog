import Foundation
import MythLogCore

extension MythLogTests {
    static func runSharedContainerTests(_ runner: TestRunner) async {
        await runner.run("group identifier prefixes the team id") {
            try expect(
                MythLogSharedContainer.groupIdentifier
                    == "\(MythLogSharedContainer.teamIdentifier).\(MythLogSharedContainer.groupSuffix)",
                "group identifier should be <team>.<suffix>")
        }

        await runner.run("container override round-trips and clears") {
            let previous = MythLogSharedContainer.overrideContainerURL
            defer { MythLogSharedContainer.overrideContainerURL = previous }

            let fake = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            MythLogSharedContainer.overrideContainerURL = fake
            let resolved = try MythLogSharedContainer.containerURL()
            let storage = try MythLogSharedContainer.storageDirectory()
            try expect(resolved.path == fake.path, "override should be returned verbatim")
            try expect(
                storage.path == fake.appendingPathComponent("Application Support/MythLog").path,
                "storage directory should nest under the container")
        }

        await runner.run("unresolved container throws appGroupUnavailable") {
            let forcePrevious = MythLogSharedContainer.overrideForceUnavailable
            defer { MythLogSharedContainer.overrideForceUnavailable = forcePrevious }
            MythLogSharedContainer.overrideForceUnavailable = true

            do {
                _ = try MythLogSharedContainer.containerURL()
                throw TestFailure(description: "expected appGroupUnavailable to be thrown")
            } catch MythLogError.appGroupUnavailable(let group) {
                try expect(group == MythLogSharedContainer.groupIdentifier, "error should name the app group")
                let description = MythLogError.appGroupUnavailable(group).errorDescription ?? ""
                try expect(
                    description.hasPrefix(SandboxEnvironment.unavailablePrefix),
                    "error description should use the uniform sandbox phrasing")
            }
        }

        await runner.run("installation paths move into the container when sandboxed") {
            let sandboxPrevious = SandboxEnvironment.overrideIsSandboxed
            let containerPrevious = MythLogSharedContainer.overrideContainerURL
            defer {
                SandboxEnvironment.overrideIsSandboxed = sandboxPrevious
                MythLogSharedContainer.overrideContainerURL = containerPrevious
            }

            let container = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            let home = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            SandboxEnvironment.overrideIsSandboxed = true
            MythLogSharedContainer.overrideContainerURL = container

            let paths = MythLogInstallationPaths(label: "com.jctec.mythlog.agent", homeDirectory: home)
            let expectedInstall = container.appendingPathComponent("Application Support/MythLog")
            try expect(
                paths.installDirectory.path == expectedInstall.path,
                "sandboxed install dir should be under the container, got \(paths.installDirectory.path)")
            try expect(
                paths.configURL.path.hasPrefix(container.path),
                "sandboxed config should live in the container")
            try expect(
                !paths.configURL.path.hasPrefix(home.path),
                "sandboxed config must not resolve under the private home")
        }

        await runner.run("installation paths keep the home layout when unsandboxed") {
            let sandboxPrevious = SandboxEnvironment.overrideIsSandboxed
            defer { SandboxEnvironment.overrideIsSandboxed = sandboxPrevious }
            SandboxEnvironment.overrideIsSandboxed = false

            let home = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            let paths = MythLogInstallationPaths(label: "com.jctec.mythlog.agent", homeDirectory: home)
            try expect(
                paths.installDirectory.path
                    == home.appendingPathComponent("Library/Application Support/MythLog").path,
                "unsandboxed install dir should keep the ~/Library layout")
            try expect(
                paths.plistURL.path
                    == home.appendingPathComponent("Library/LaunchAgents/com.jctec.mythlog.agent.plist").path,
                "unsandboxed plist should keep the ~/Library/LaunchAgents layout")
        }

        await runner.run("installed default config pins absolute container storage when sandboxed") {
            let sandboxPrevious = SandboxEnvironment.overrideIsSandboxed
            let containerPrevious = MythLogSharedContainer.overrideContainerURL
            defer {
                SandboxEnvironment.overrideIsSandboxed = sandboxPrevious
                MythLogSharedContainer.overrideContainerURL = containerPrevious
            }

            let container = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true)
            SandboxEnvironment.overrideIsSandboxed = true
            MythLogSharedContainer.overrideContainerURL = container

            let paths = MythLogInstallationPaths(label: "com.jctec.mythlog.agent")
            let config = MythLogConfig.installedDefault(paths: paths)
            try expect(
                config.storage.ledgerPath.hasPrefix(container.path),
                "sandboxed ledger path should be absolute inside the container")
            try expect(
                !config.storage.ledgerPath.contains("~"),
                "sandboxed storage paths must be absolute, not tilde-relative")
            try expect(
                config.storage.outboxDirectory.hasPrefix(container.path)
                    && config.storage.runtimeDirectory.hasPrefix(container.path),
                "sandboxed outbox and runtime should be inside the container")
        }

        await runner.run("installed default config keeps tilde defaults when unsandboxed") {
            let sandboxPrevious = SandboxEnvironment.overrideIsSandboxed
            defer { SandboxEnvironment.overrideIsSandboxed = sandboxPrevious }
            SandboxEnvironment.overrideIsSandboxed = false

            let paths = MythLogInstallationPaths(label: "com.jctec.mythlog.agent")
            let config = MythLogConfig.installedDefault(paths: paths)
            try expect(
                config.storage == StorageConfig.default,
                "unsandboxed installed default should equal the tilde-based default")
        }
    }
}
