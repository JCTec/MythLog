import SwiftUI

// The anchor choice, reframed.
//
// The gate for Phase C is that this copy explains the threat rather than the
// file path. Read these as somebody who has never thought about where a hash
// goes: the question at the top should be answerable, and choosing wrongly
// should be visibly a decision rather than a default.

/// The normal case: iCloud selected, both options resolvable.
#Preview("Anchoring — iCloud selected") {
    AnchorSettingsPage(
        model: AnchorSettingsPage.Model(
            settings: AnchorSettings(isEnabled: true, choice: .iCloudDrive),
            store: .previewOnly,
            locations: StaticAnchorLocationDescription(answers: [
                AnchorChoice.iCloudDrive.id: "/Users/example/Library/Mobile Documents/com~apple~CloudDocs/MythLog",
                AnchorChoice.chosenFolder.id: "No anchor directory has been chosen.",
            ])
        )
    )
    .frame(width: 780, height: 900)
    .preferredColorScheme(.dark)
}

/// The case the feature was built for and nobody knew about: a USB key. The
/// footer shows a volume path, and the recommendation above it says why this is
/// the strongest option available.
#Preview("Anchoring — a USB key") {
    AnchorSettingsPage(
        model: AnchorSettingsPage.Model(
            settings: AnchorSettings(
                isEnabled: true, choice: .chosenFolder, chosenDirectory: "/Volumes/KEY/MythLog"),
            store: .previewOnly,
            locations: StaticAnchorLocationDescription(answers: [
                AnchorChoice.iCloudDrive.id: "/Users/example/Library/Mobile Documents/com~apple~CloudDocs/MythLog",
                AnchorChoice.chosenFolder.id: "/Volumes/KEY/MythLog",
            ])
        )
    )
    .frame(width: 780, height: 900)
    .preferredColorScheme(.dark)
}

/// Signed out of iCloud. The footer has to say *why* it cannot resolve rather
/// than going blank — "aimed at somewhere that is not there" and "not anchoring"
/// are different states.
#Preview("Anchoring — iCloud signed out") {
    AnchorSettingsPage(
        model: AnchorSettingsPage.Model(
            settings: AnchorSettings(isEnabled: true, choice: .iCloudDrive),
            store: .previewOnly,
            locations: AnchorLocationDescription(
                locations: AnchorLocations(
                    environment: .sandboxed(),
                    ubiquity: FixedUbiquityContainerResolver(url: nil)
                ))
        )
    )
    .frame(width: 780, height: 900)
    .preferredColorScheme(.dark)
}

/// Anchoring switched off. The toggle's own copy has to carry what is lost:
/// a shortened chain verifies perfectly, so without an anchor nothing catches it.
#Preview("Anchoring — switched off") {
    AnchorSettingsPage(
        model: AnchorSettingsPage.Model(
            settings: AnchorSettings(isEnabled: false, choice: .iCloudDrive),
            store: .previewOnly,
            locations: StaticAnchorLocationDescription(answers: [:])
        )
    )
    .frame(width: 780, height: 900)
    .preferredColorScheme(.dark)
}

/// The warning on its own, which is the thing that did not exist before.
#Preview("The visibility warning") {
    VStack(spacing: Metrics.space4) {
        ForEach(AnchorChoice.all) { choice in
            AnchorChoiceCard(
                choice: choice,
                isSelected: choice.kind == .iCloudDrive,
                resolvedLocation: "…",
                onSelect: {}
            )
        }
    }
    .padding(Metrics.space5)
    .frame(width: 760)
    .background(Palette.canvas)
    .preferredColorScheme(.dark)
}

extension AnchorSettingsStore {
    /// A store pointed at nowhere, so a preview can never write to the real
    /// install on the machine rendering it. Saving reports "nowhere to save",
    /// which is also a state worth seeing.
    static var previewOnly: AnchorSettingsStore {
        AnchorSettingsStore(locations: nil)
    }
}
