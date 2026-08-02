// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MythLog",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MythLogCore",
            targets: ["MythLogCore"]
        ),
        .library(
            name: "MythLogAppSupport",
            targets: ["MythLogAppSupport"]
        ),
        .executable(
            name: "mythlog-probe",
            targets: ["MythLogProbe"]
        ),
        .executable(
            name: "mythlog-agent",
            targets: ["MythLogAgent"]
        ),
        .executable(
            name: "mythlogctl",
            targets: ["MythLogCLI"]
        ),
        .executable(
            name: "MythLogApp",
            targets: ["MythLogApp"]
        ),
        .executable(
            name: "mythlog-tests",
            targets: ["MythLogTests"]
        ),
    ],
    targets: [
        .target(
            name: "MythLogCore"
        ),
        .executableTarget(
            name: "MythLogProbe",
            dependencies: ["MythLogCore"]
        ),
        .executableTarget(
            name: "MythLogAgent",
            dependencies: ["MythLogCore"]
        ),
        .target(
            name: "MythLogCLIKit",
            dependencies: ["MythLogCore"]
        ),
        .executableTarget(
            name: "MythLogCLI",
            dependencies: ["MythLogCore", "MythLogCLIKit"]
        ),
        .executableTarget(
            name: "MythLogApp",
            dependencies: ["MythLogAppSupport"]
        ),
        .executableTarget(
            name: "MythLogTests",
            dependencies: ["MythLogCore", "MythLogAppSupport", "MythLogCLIKit"]
        ),
        .target(
            name: "MythLogAppSupport",
            dependencies: ["MythLogCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
