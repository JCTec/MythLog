import Observation
import SwiftUI

extension AnchorSettingsPage {
    /// The anchor choice, where each option would resolve to, and what happened
    /// the last time it was saved.
    ///
    /// Everything here speaks in ``AnchorSettings``, ``AnchorChoice`` and
    /// ``SettingsSaveResult`` — view models — rather than in the config schema
    /// those are derived from. See ``AnchorSettings`` for why that boundary is
    /// worth keeping: a settings screen bound to a file format drifts into
    /// presenting the file format, which is how this setting became a path in
    /// the first place.
    @MainActor
    @Observable
    final class Model {
        var isEnabled: Bool { didSet { markDirty(from: oldValue, to: isEnabled) } }
        private(set) var selected: AnchorChoice
        private(set) var chosenDirectory: String?

        /// What the last save did. `nil` before anything has been saved this
        /// session — which is a third state, distinct from "saved" and
        /// "refused", and must not render as either.
        private(set) var lastResult: SettingsSaveResult?

        /// Whether the on-screen settings differ from what was loaded. Drives
        /// whether saving is offered at all: a Save button that is always live
        /// invites people to press it and learn nothing.
        private(set) var hasUnsavedChanges = false

        private let store: AnchorSettingsStore
        private var loaded: AnchorSettings

        init(
            settings: AnchorSettings? = nil,
            store: AnchorSettingsStore = AnchorSettingsStore(),
            locations: (any AnchorLocationDescribing)? = nil
        ) {
            self.store = store
            // Explicit settings win (previews and tests); otherwise read what is
            // actually installed. Falling back to defaults is deliberate and
            // safe here — nothing is written until the user presses Save, so a
            // wrong guess costs a redraw rather than a config.
            let initial = settings ?? store.load() ?? AnchorSettings()
            self.loaded = initial
            self.isEnabled = initial.isEnabled
            self.selected = initial.choice
            self.chosenDirectory = initial.chosenDirectory
            self.describer = locations ?? AnchorLocationDescription()
        }

        private let describer: any AnchorLocationDescribing

        // MARK: - Choosing

        func select(_ choice: AnchorChoice) {
            guard choice.id != selected.id else { return }
            selected = choice
            recomputeDirty()
        }

        func isSelected(_ choice: AnchorChoice) -> Bool {
            selected.id == choice.id
        }

        /// Opens the folder panel, with the visibility warning inside it.
        ///
        /// Choosing a folder also selects "a folder you choose" — picking a
        /// destination and then having to remember to tick it is a way to leave
        /// somebody's anchors going to iCloud while they believe they are on a
        /// USB key.
        func chooseFolder() {
            let chooser = FolderChooser(
                message: Self.pickerWarning,
                prompt: "Keep anchors here",
                startingAt: chosenDirectory.map { URL(fileURLWithPath: $0) }
            )
            guard let url = chooser.choose() else { return }

            chosenDirectory = url.path
            selected = .chosenFolder
            recomputeDirty()
        }

        /// Said inside the panel, at the moment of choosing, because that is
        /// when it applies — not on a page read a minute ago.
        static let pickerWarning =
            "Anchors kept here are only out of reach if this folder is. A folder that syncs — iCloud "
            + "Drive, Dropbox, anything similar — appears on every device signed into that account, "
            + "including devices someone else uses. A USB key or an external drive appears nowhere."

        // MARK: - Saving

        var canSave: Bool { store.canSave && hasUnsavedChanges }

        /// Where a save would go, shown before anyone presses anything.
        var targetDescription: String { store.targetDescription }

        /// True when there is no install to save into — a normal state on a Mac
        /// used only to look at exported ledgers, and one the page explains
        /// rather than hiding the button over.
        var hasNowhereToSave: Bool { !store.canSave }

        func save() {
            let result = store.save(settings)
            lastResult = result
            if result.isSaved {
                loaded = settings
                recomputeDirty()
            }
        }

        /// Throws away unsaved edits and shows what is actually on disk.
        func revert() {
            isEnabledWithoutDirtying(loaded.isEnabled)
            selected = loaded.choice
            chosenDirectory = loaded.chosenDirectory
            lastResult = nil
            recomputeDirty()
        }

        // MARK: - Presentation

        func resolvedLocation(for choice: AnchorChoice) -> String {
            describer.describe(choice, chosenDirectory: chosenDirectory)
        }

        /// What these settings currently say, as a value the rest of the app can
        /// carry.
        var settings: AnchorSettings {
            AnchorSettings(isEnabled: isEnabled, choice: selected, chosenDirectory: chosenDirectory)
        }

        // MARK: - Dirty tracking

        private func markDirty(from oldValue: Bool, to newValue: Bool) {
            guard oldValue != newValue else { return }
            recomputeDirty()
        }

        private func isEnabledWithoutDirtying(_ value: Bool) {
            // `didSet` does not fire during `revert`'s own recompute, so this
            // just keeps the intent readable at the call site.
            isEnabled = value
        }

        private func recomputeDirty() {
            hasUnsavedChanges = settings != loaded
            // A pending result describes the previous state of the file. Once
            // the user edits again it is no longer true, and a stale "Saved at
            // 14:32" beside changed settings is the exact ambiguity this page
            // is supposed to remove.
            if hasUnsavedChanges { lastResult = nil }
        }
    }
}
