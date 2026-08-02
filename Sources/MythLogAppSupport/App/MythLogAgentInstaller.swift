import Foundation
import MythLogCore

enum MythLogRecorderInstallResult: Equatable, Sendable {
    case nativeRegistered
    case nativeRequiresApproval
    case legacyLaunchAgent

    var requiresBackgroundItemsApproval: Bool {
        self == .nativeRequiresApproval
    }
}

struct MythLogAgentInstaller: Sendable {
    let launchAgentLabel: String

    var paths: MythLogInstallationPaths {
        MythLogInstallationPaths(label: launchAgentLabel)
    }

    var installDirectory: URL {
        paths.installDirectory
    }

    var installedBinDirectory: URL {
        paths.binDirectory
    }

    var logDirectory: URL {
        paths.logDirectory
    }

    var configURL: URL {
        paths.configURL
    }

    var launchAgentURL: URL {
        paths.plistURL
    }

    var manager: LaunchAgentManager {
        LaunchAgentManager(paths: paths)
    }

    var serviceManagementRegistrar: MythLogServiceManagementAgentRegistrar {
        MythLogServiceManagementAgentRegistrar()
    }

    func installAndStartAgent() async throws -> MythLogRecorderInstallResult {
        MythLogDiagnostics.installer.info("Recorder install requested")

        // Sandboxed installs must resolve the App Group container before any I/O;
        // fail loudly and attributably here rather than writing helpers into a
        // private (split-brain) container. Unsandboxed installs skip this.
        if Self.isSandboxed {
            _ = try MythLogSharedContainer.containerURL()
        }

        let helpers = try await bundledHelpers()

        _ = await manager.stop()
        try await copyBundledHelpers(helpers)
        try await manager.prepareInstalledSupport(agentPath: helpers.agent.path)
        _ = try? await manager.uninstall(removePlist: true)

        switch try await serviceManagementRegistrar.registerIfPackaged() {
        case .registered:
            MythLogDiagnostics.installer.info("Recorder registered via SMAppService")
            return .nativeRegistered
        case .requiresApproval:
            MythLogDiagnostics.installer.notice("Recorder registration requires user approval in System Settings")
            return .nativeRequiresApproval
        case .unavailable(let reason):
            guard !Self.isSandboxed else {
                // The legacy path writes a LaunchAgent plist and helper into
                // real user Library locations, which a sandboxed process
                // cannot do; failing early gives an actionable error instead.
                MythLogDiagnostics.installer.error(
                    """
                    Legacy LaunchAgent install \
                    \(SandboxEnvironment.unavailableReason("writes into ~/Library outside the container"), privacy: .public); \
                    SMAppService was unavailable (\(reason, privacy: .public))
                    """)
                throw AppInstallerError.sandboxRequiresBundledRecorder(reason)
            }
            MythLogDiagnostics.installer.notice(
                """
                SMAppService unavailable (\(reason, privacy: .public)); \
                falling back to legacy LaunchAgent
                """)
            try await manager.install()
            MythLogDiagnostics.installer.info("Legacy LaunchAgent installed")
            return .legacyLaunchAgent
        }
    }

    func stopLaunchAgent() async {
        MythLogDiagnostics.installer.info("Recorder stop requested")
        await serviceManagementRegistrar.unregisterIfPackaged()
        _ = await manager.stop()
    }

    func restartLaunchAgent() async throws -> MythLogRecorderInstallResult {
        switch try await serviceManagementRegistrar.registerIfPackaged() {
        case .registered:
            return .nativeRegistered
        case .requiresApproval:
            return .nativeRequiresApproval
        case .unavailable:
            _ = try await manager.restart()
            return .legacyLaunchAgent
        }
    }

    func launchAgentStatus() async -> LaunchAgentServiceStatus {
        await manager.status()
    }

    func serviceManagementStatus() async -> ServiceManagementAgentStatus {
        await serviceManagementRegistrar.status()
    }

    func uninstallAgent() async throws {
        MythLogDiagnostics.installer.info("Recorder uninstall requested")
        await serviceManagementRegistrar.unregisterIfPackaged()
        _ = try await manager.uninstall()
        try await clearRuntimeStatus()
        MythLogDiagnostics.installer.info("Recorder uninstalled")
    }

    private func clearRuntimeStatus() async throws {
        let configURL = paths.configURL
        try await MythLogBackgroundTask.throwing(priority: .utility) {
            let config = (try? MythLogConfig.load(from: configURL)) ?? MythLogConfig()
            let statusURL = PathResolver.fileURL(config.storage.runtimeDirectory)
                .appendingPathComponent("status.json")
            try AgentStatusStore.remove(from: statusURL)
        }
    }

    private func bundledHelpers() async throws -> BundledHelpers {
        try await MythLogBackgroundTask.throwing(priority: .utility) {
            try BundledHelpers(
                agent: Self.bundledExecutable(named: "mythlog-agent"),
                control: Self.bundledExecutable(named: "mythlogctl"),
                icon: Self.bundledIcon()
            )
        }
    }

    private static func bundledExecutable(named name: String) throws -> URL {
        guard let resourceURL = Bundle.main.resourceURL else {
            throw AppInstallerError.missingBundleResource("Bundle resources are unavailable.")
        }

        let url = resourceURL.appendingPathComponent("bin/\(name)")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw AppInstallerError.missingBundleResource(
                "Missing bundled helper: \(url.path). Build a release bundle with scripts/package-release.sh.")
        }
        return url
    }

    private static func bundledIcon() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }

        let url = resourceURL.appendingPathComponent("MythLog.icns")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func copyBundledHelpers(_ helpers: BundledHelpers) async throws {
        let paths = paths
        try await MythLogBackgroundTask.throwing(priority: .utility) {
            try Self.copyBundledHelpers(
                agent: helpers.agent,
                control: helpers.control,
                paths: paths,
                icon: helpers.icon
            )
        }
    }

    static func copyBundledHelpers(
        agent: URL,
        control: URL,
        paths: MythLogInstallationPaths,
        icon: URL? = nil
    ) throws {
        try FileManager.default.createDirectory(at: paths.binDirectory, withIntermediateDirectories: true)
        try createAgentBundle(agent: agent, paths: paths, icon: icon)
        try replaceFile(from: control, to: paths.controlExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.controlExecutableURL.path)

        let legacyAgentURL = paths.binDirectory.appendingPathComponent("mythlog-agent")
        if FileManager.default.fileExists(atPath: legacyAgentURL.path) {
            try FileManager.default.removeItem(at: legacyAgentURL)
        }
    }

    private static func createAgentBundle(agent: URL, paths: MythLogInstallationPaths, icon: URL?) throws {
        let contentsURL = paths.agentBundleURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")

        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        try replaceFile(from: agent, to: paths.agentExecutableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.agentExecutableURL.path)
        try removeLegacyAgentExecutables(in: macOSURL, keeping: paths.agentExecutableURL)

        if let icon {
            try replaceFile(from: icon, to: resourcesURL.appendingPathComponent("MythLog.icns"))
        }

        try agentBundleInfoPlist(label: paths.label)
            .write(to: infoPlistURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: infoPlistURL.path)
        try signAndRegisterAgentBundleIfPossible(paths: paths)
    }

    private static func agentBundleInfoPlist(label: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleDevelopmentRegion</key>
          <string>en</string>
          <key>CFBundleDisplayName</key>
          <string>MythLog</string>
          <key>CFBundleExecutable</key>
          <string>MythLog</string>
          <key>CFBundleIconFile</key>
          <string>MythLog</string>
          <key>CFBundleIdentifier</key>
          <string>\(label)</string>
          <key>CFBundleName</key>
          <string>MythLog</string>
          <key>CFBundlePackageType</key>
          <string>APPL</string>
          <key>CFBundleShortVersionString</key>
          <string>1.0.0</string>
          <key>CFBundleVersion</key>
          <string>1</string>
          <key>LSBackgroundOnly</key>
          <true/>
          <key>LSMinimumSystemVersion</key>
          <string>14.0</string>
        </dict>
        </plist>
        """
    }

    private static func replaceFile(from source: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private static func removeLegacyAgentExecutables(in directory: URL, keeping activeExecutable: URL) throws {
        for legacyName in ["MythLogAgent", "mythlog-agent"] {
            let url = directory.appendingPathComponent(legacyName)
            if url.path != activeExecutable.path && FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Forwards to the shared `SandboxEnvironment.isSandboxed` so all sandbox
    /// detection has one implementation and one test seam.
    static var isSandboxed: Bool {
        SandboxEnvironment.isSandboxed
    }

    private static func signAndRegisterAgentBundleIfPossible(paths: MythLogInstallationPaths) throws {
        #if canImport(Darwin)
            guard try InstallerToolSupport.isMachOExecutable(paths.agentExecutableURL) else {
                return
            }

            try runInstallerTool(
                executable: "/usr/bin/codesign",
                arguments: ["--force", "--deep", "--sign", "-", paths.agentBundleURL.path]
            )
            try runInstallerTool(
                executable: "/usr/bin/codesign",
                arguments: ["--verify", "--deep", "--strict", paths.agentBundleURL.path]
            )

            guard !isSandboxed else {
                // lsregister cannot scan paths inside the app's sandbox container
                // (fails with -10819); the sandboxed recorder path is SMAppService.
                MythLogDiagnostics.installer.notice(
                    """
                    LaunchServices registration of the helper app \
                    \(SandboxEnvironment.unavailableReason("lsregister cannot scan the container"), privacy: .public); \
                    skipping
                    """)
                return
            }

            let lsregister = URL(
                fileURLWithPath:
                    "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            )
            if FileManager.default.isExecutableFile(atPath: lsregister.path) {
                try runInstallerTool(executable: lsregister.path, arguments: ["-f", paths.agentBundleURL.path])
            }
        #endif
    }

    private static func runInstallerTool(executable: String, arguments: [String]) throws {
        let result = try InstallerToolSupport.runTool(executable: executable, arguments: arguments)
        guard result.succeeded else {
            let detail = result.summary
            throw AppInstallerError.helperSigningFailed(detail)
        }
    }
}

private struct BundledHelpers: Sendable {
    var agent: URL
    var control: URL
    var icon: URL?
}

enum AppInstallerError: LocalizedError {
    case missingBundleResource(String)
    case helperSigningFailed(String)
    case sandboxRequiresBundledRecorder(String)

    var errorDescription: String? {
        switch self {
        case .missingBundleResource(let message):
            message
        case .helperSigningFailed(let message):
            "Could not sign the MythLog helper app: \(message)"
        case .sandboxRequiresBundledRecorder(let reason):
            """
            Legacy LaunchAgent install is \
            \(SandboxEnvironment.unavailableReason("it writes into ~/Library outside the container")). \
            This sandboxed build installs the recorder only through the bundled login item \
            (SMAppService), which was unavailable: \(reason) \
            Run the packaged MythLog.app (with Contents/Library/LoginItems), or \
            disable App Sandbox for development runs.
            """
        }
    }
}
