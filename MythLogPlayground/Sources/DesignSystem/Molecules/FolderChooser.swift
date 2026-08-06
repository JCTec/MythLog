import AppKit
import SwiftUI

/// Picks a directory, and says the dangerous thing at the moment of picking.
///
/// # Why `NSOpenPanel` rather than `.fileImporter`
///
/// SwiftUI's `.fileImporter` presents the same panel and cannot set its
/// `message`. That message is the point of this type: the visibility warning
/// belongs *in the panel*, next to the folder list, at the instant somebody is
/// about to click on their iCloud Drive folder — not on a settings page they
/// read a minute ago and have stopped looking at.
///
/// `canCreateDirectories` matters for the same reason. The recommended answer is
/// a USB key, and a USB key usually has no MythLog folder on it yet; a picker
/// that cannot make one turns the best option into the most annoying one.
struct FolderChooser {
    /// Shown inside the panel, above the file list.
    var message: String
    var prompt: String
    /// Where to start. The current choice, when there is one.
    var startingAt: URL?

    /// Runs the panel and returns what was chosen, or `nil` if it was cancelled.
    ///
    /// `@MainActor` because `NSOpenPanel` is AppKit and must be driven from the
    /// main thread. Modal, deliberately: choosing where evidence is kept is not
    /// a background activity, and a sheet the user can wander away from leaves
    /// the settings page in a state that has to be explained.
    @MainActor
    func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = message
        panel.prompt = prompt
        panel.directoryURL = startingAt

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
