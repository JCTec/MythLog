import Observation
import SwiftUI

extension AnchorSettingsPage {
    /// The anchor choice, and where each option would actually resolve to.
    ///
    /// Everything here speaks in ``AnchorSettings`` and ``AnchorChoice`` — view
    /// models — rather than in the config schema those are derived from. See
    /// ``AnchorSettings`` for why that boundary is worth keeping: a settings
    /// screen bound to a file format drifts into presenting the file format,
    /// which is how this setting became a path in the first place.
    @MainActor
    @Observable
    final class Model {
        var isEnabled: Bool
        private(set) var selected: AnchorChoice
        /// The path for "a folder you choose". Choosing one is a file-picker job
        /// that lands with the rest of configuration writing; showing where it
        /// currently points is useful now.
        var chosenDirectory: String?

        private let locations: any AnchorLocationDescribing

        init(
            settings: AnchorSettings = AnchorSettings(),
            locations: any AnchorLocationDescribing = AnchorLocationDescription()
        ) {
            self.isEnabled = settings.isEnabled
            self.selected = settings.choice
            self.chosenDirectory = settings.chosenDirectory
            self.locations = locations
        }

        func select(_ choice: AnchorChoice) {
            selected = choice
        }

        func isSelected(_ choice: AnchorChoice) -> Bool {
            selected.id == choice.id
        }

        /// Where this option would write, or why it currently cannot.
        ///
        /// Never blank, deliberately: "aimed at a place that is not there right
        /// now" and "not anchoring at all" are different states, and an empty
        /// footer would collapse them.
        func resolvedLocation(for choice: AnchorChoice) -> String {
            locations.describe(choice, chosenDirectory: chosenDirectory)
        }

        /// What these settings currently say, as a value the rest of the app can
        /// carry.
        var settings: AnchorSettings {
            AnchorSettings(isEnabled: isEnabled, choice: selected, chosenDirectory: chosenDirectory)
        }
    }
}
