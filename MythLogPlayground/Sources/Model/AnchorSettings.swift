import Foundation

/// The anchor settings as the interface needs them.
///
/// # Why this is not just `HashAnchorConfig`
///
/// `HashAnchorConfig` is a *schema* — a shape on disk with a raw-value enum, a
/// back-compatibility rule about an absent `destination` field, and an optional
/// path. `DesignSystem/` may reference `Primitives/` and view models and nothing
/// else, so it cannot name any of that, and `Scripts/check-layering.sh` catches
/// the attempt.
///
/// The rule is worth keeping rather than working around. A settings screen bound
/// directly to a config schema drifts into presenting the file format — which is
/// exactly how this setting became a text field containing a directory, the
/// thing Phase C exists to undo.
struct AnchorSettings: Equatable, Sendable {
    var isEnabled: Bool
    var choice: AnchorChoice
    /// The configured path, for the `.directory` choice.
    var chosenDirectory: String?

    init(isEnabled: Bool = true, choice: AnchorChoice = .iCloudDrive, chosenDirectory: String? = nil) {
        self.isEnabled = isEnabled
        self.choice = choice
        self.chosenDirectory = chosenDirectory
    }

    init(config anchor: HashAnchorConfig) {
        self.init(
            isEnabled: anchor.enabled,
            choice: .choice(for: anchor.destination),
            chosenDirectory: anchor.directory
        )
    }
}

/// Says where a choice would actually write.
///
/// A protocol so the page can be shown against a machine that is signed out of
/// iCloud without being signed out of iCloud — the branch that matters is the
/// one that is hardest to reach by accident.
protocol AnchorLocationDescribing: Sendable {
    /// Never throws and never returns an empty string. "Aimed somewhere that is
    /// not currently there" and "not anchoring" are different states, and a
    /// blank line would collapse them.
    func describe(_ choice: AnchorChoice, chosenDirectory: String?) -> String
}

/// The real one, over ``AnchorLocations``.
struct AnchorLocationDescription: AnchorLocationDescribing {
    var locations: AnchorLocations

    init(locations: AnchorLocations = AnchorLocations()) {
        self.locations = locations
    }

    func describe(_ choice: AnchorChoice, chosenDirectory: String?) -> String {
        locations.describe(choice.locationKind, chosenDirectory: chosenDirectory)
    }
}

/// A fixed answer, for previews and tests.
struct StaticAnchorLocationDescription: AnchorLocationDescribing {
    var answers: [String: String]

    func describe(_ choice: AnchorChoice, chosenDirectory: String?) -> String {
        answers[choice.id] ?? "—"
    }
}

extension AnchorChoice {
    /// Builds the destination that would carry this choice out.
    ///
    /// Lives in `Model/` because it spans `Platform/` (where iCloud is) and
    /// `Ledger/` (what writing an anchor means), and `Model/` is the only layer
    /// permitted to see both.
    ///
    /// Resolution is deferred into the destination rather than done here: iCloud
    /// can stop being available between this call and the next write, and an
    /// anchor written to a stale path is worse than one not written at all.
    func makeDestination(
        chosenDirectory: String?,
        locations: AnchorLocations = AnchorLocations()
    ) -> any AnchorDestination {
        let kind = locationKind
        return ResolvingAnchorDestination(
            describedLocation: locations.describe(kind, chosenDirectory: chosenDirectory)
        ) {
            try locations.directory(for: kind, chosenDirectory: chosenDirectory)
        }
    }
}

extension AnchorSettings {
    /// The destination these settings describe, or a disabled one.
    ///
    /// `DisabledAnchorDestination` rather than `nil`, so "switched off" stays a
    /// state the rest of the app can carry rather than an absence it has to
    /// interpret.
    func makeDestination(locations: AnchorLocations = AnchorLocations()) -> any AnchorDestination {
        guard isEnabled else { return DisabledAnchorDestination() }
        return choice.makeDestination(chosenDirectory: chosenDirectory, locations: locations)
    }
}
