import Foundation

/// The anchor destination, described as the question it actually is.
///
/// # Not "where do you want to keep a file"
///
/// An anchor on the same disk, under the same person's control, is worth
/// nothing: whoever truncated the ledger rewrites the anchor in the same motion.
/// The entire value comes from the anchor living somewhere the adversary cannot
/// reach — which means the right question is **"who are you keeping this away
/// from?"**, and only the user knows the answer.
///
/// A settings screen that asks for a path cannot be answered correctly by
/// someone who has not already had that thought. So this type carries the
/// thought: what each destination protects against, what it does not, and — the
/// one nobody expects — when choosing it could make things worse.
///
/// Copy lives here rather than in the view because it is *domain* knowledge, not
/// layout. It is also the part most likely to need review by someone who does
/// not read Swift, and it is easier to find in one file than scattered through a
/// hierarchy of `Text`.
struct AnchorChoice: Identifiable, Equatable, Sendable {
    var kind: AnchorDestinationKind
    var id: String { kind.rawValue }

    /// What to call it. Deliberately not the mechanism.
    var title: String
    /// The one-line answer to "who does this keep it away from?".
    var keepsItAwayFrom: String
    var protects: [String]
    var doesNotProtect: [String]

    /// The thing the current design never says.
    ///
    /// An anchor written to a synced folder appears on every device signed into
    /// that account — **including the adversary's**. For someone documenting a
    /// hostile household, the feature meant to protect them announces them
    /// instead: a folder called MythLog turning up on a shared iPad is not a
    /// neutral event.
    ///
    /// This is `docs/ANCHOR_DESTINATIONS.md` open question 1, and it belongs
    /// where the choice is made rather than in documentation nobody reads while
    /// frightened.
    var visibilityWarning: String?

    /// Whether this is a sensible default for someone who has not thought about
    /// it. Exactly one choice should be.
    var isDefault: Bool

    /// Whether this choice is meaningless without a folder being picked.
    var needsAFolder: Bool { kind == .directory }

    /// The schema value onto the platform's own vocabulary.
    ///
    /// This mapping is the reason `Model/` exists: `Config/` owns what is
    /// written down, `Platform/` owns where things are, and neither may name the
    /// other.
    var locationKind: AnchorLocations.Kind {
        switch kind {
        case .iCloudDrive: .iCloudDrive
        case .directory: .directory
        }
    }
}

extension AnchorChoice {
    /// The two destinations that exist today.
    ///
    /// Nothing new is added here — that is what makes this groundwork. The
    /// change is that both are now described in terms of the threat instead of
    /// the file path, and the second one stops being invisible.
    static let all: [AnchorChoice] = [.iCloudDrive, .chosenFolder]

    static let iCloudDrive = AnchorChoice(
        kind: .iCloudDrive,
        title: "iCloud Drive",
        keepsItAwayFrom: "Someone using this Mac who does not have your Apple Account password.",
        protects: [
            "Records deleted from the end of the ledger on this Mac.",
            "Someone with the Mac but not the account.",
            "This Mac being lost, wiped, or replaced.",
        ],
        doesNotProtect: [
            "Someone who also has your Apple Account — often the case with a partner or family member.",
            "Someone who can reach your unlocked iPhone or iPad.",
        ],
        visibilityWarning:
            "Anchors sync, so a MythLog folder appears on every device signed into this Apple Account — "
            + "including devices someone else uses. If the person you are documenting shares your account, "
            + "this tells them MythLog is running. Choose a folder they cannot see instead.",
        isDefault: true
    )

    static let chosenFolder = AnchorChoice(
        kind: .directory,
        title: "A folder you choose",
        keepsItAwayFrom: "Whoever cannot reach the folder — which is entirely up to where you put it.",
        protects: [
            "Everything iCloud protects against, if the folder is off this Mac.",
            "Someone with your Apple Account, if the folder is not synced to it.",
            "A USB key kept in a bag or at work: nothing reaches it while it is unplugged.",
        ],
        doesNotProtect: [
            "Anything, if the folder is on this Mac — the anchor is then as editable as the ledger.",
            "Someone who can see the sync account, if you point it at Dropbox or iCloud by hand.",
        ],
        visibilityWarning:
            "If you choose a synced folder, the same warning applies as for iCloud Drive: it will appear on "
            + "every device signed into that service. A USB key or an external drive appears nowhere.",
        isDefault: false
    )

    /// The case that already works and nobody knows about.
    ///
    /// A USB key kept in a bag scores well on the two properties that matter
    /// most — outside the adversary's control, and deletions are visible — using
    /// a mechanism that shipped a year ago. What was missing was ever saying so.
    /// It is called out separately because a bullet inside `protects` reads as
    /// an example, and this is a recommendation.
    static let usbKeySuggestion =
        "A USB key is the strongest option here and needs nothing new: point this at a folder on the key, "
        + "and unplug it. An anchor on a stick in your bag cannot be reached by anyone using this Mac, "
        + "cannot be quietly deleted, and shows up on nobody else's devices. Plug it in occasionally to "
        + "let MythLog write a fresh one."

    /// Why any of this exists, in the two sentences that make the rest make
    /// sense. The chain proves nothing was *edited*; only an outside copy proves
    /// nothing was *removed*.
    static let rationale =
        "The hash chain proves nobody edited a record. It cannot prove nobody deleted records from the end — "
        + "delete the last fifty and the rest still verifies perfectly, because the evidence of the deletion "
        + "was the part that got deleted. An anchor is a copy of \"there were N records at time T\", kept "
        + "somewhere else. It holds no event content at all, so it can go almost anywhere."

    static func choice(for kind: AnchorDestinationKind) -> AnchorChoice {
        all.first { $0.kind == kind } ?? .iCloudDrive
    }
}
