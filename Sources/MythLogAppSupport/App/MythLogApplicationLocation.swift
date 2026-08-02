import Foundation

struct MythLogApplicationLocation: Equatable, Sendable {
    var bundleURL: URL

    static func current(bundle: Bundle = .main) -> MythLogApplicationLocation {
        MythLogApplicationLocation(bundleURL: bundle.bundleURL)
    }

    var recorderInstallIssue: MythLogRecorderInstallLocationIssue? {
        if isDevelopmentBuild || isInApplicationsFolder {
            return nil
        }

        if isDiskImagePath {
            return .diskImage(path: displayPath)
        }

        if isAppTranslocationPath {
            return .appTranslocation(path: displayPath)
        }

        return .outsideApplications(path: displayPath)
    }

    private var displayPath: String {
        bundleURL.standardizedFileURL.path
    }

    private var pathComponents: [String] {
        URL(fileURLWithPath: displayPath).pathComponents
    }

    private var isDevelopmentBuild: Bool {
        let path = displayPath
        return pathComponents.contains(".build") || path.contains("/DerivedData/")
    }

    private var isInApplicationsFolder: Bool {
        let components = pathComponents

        if components.count >= 3, components[0] == "/", components[1] == "Applications" {
            return true
        }

        if components.count >= 5,
            components[0] == "/",
            components[1] == "Users",
            components[3] == "Applications"
        {
            return true
        }

        return false
    }

    private var isDiskImagePath: Bool {
        let components = pathComponents
        return components.count >= 2 && components[0] == "/" && components[1] == "Volumes"
    }

    private var isAppTranslocationPath: Bool {
        displayPath.contains("/AppTranslocation/")
    }
}

enum MythLogRecorderInstallLocationIssue: Equatable, Sendable {
    case diskImage(path: String)
    case appTranslocation(path: String)
    case outsideApplications(path: String)

    var title: String {
        "Move MythLog to Applications"
    }

    var message: String {
        """
        Recorder setup must run from a stable installed app location.

        Quit this copy of MythLog, drag MythLog.app to Applications, then open it from Applications and install the recorder again.

        Current location:
        \(path)
        """
    }

    private var path: String {
        switch self {
        case .diskImage(let path), .appTranslocation(let path), .outsideApplications(let path):
            path
        }
    }
}
