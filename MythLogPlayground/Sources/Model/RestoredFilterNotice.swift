import Foundation

/// A filter that was active before the app was last closed and is active again
/// now.
///
/// # Why this is a type and not a boolean
///
/// Restoring a filter is the most dangerous thing in this feature. A quiet
/// timeline is what someone opens this app hoping for; a timeline that is quiet
/// because of a filter set last Tuesday is the one lie the app exists not to
/// tell, and it is convincing precisely because the user is looking at their own
/// history and it looks fine.
///
/// The notice is the mitigation, so it carries the sentences rather than leaving
/// each view to invent them: what is active, where it came from, when it was
/// saved, and — the part that matters most — that it was restored rather than
/// chosen. It stays until it is acknowledged or the filter is cleared.
struct RestoredFilterNotice: Equatable, Sendable {
    /// The saved filter this came from, or `nil` for one the user built by hand
    /// and never named. Both cases are announced; only one can be named.
    var savedAs: SavedFilter?
    var filter: EventFilter

    var headline: String {
        guard let savedAs else { return "A filter from your last session is still active" }
        return "A saved filter is active — \(savedAs.attribution)"
    }

    var body: String {
        "You are not looking at everything that was recorded. This was restored from the last time "
            + "you used MythLog — it is not something you chose just now."
    }

    /// What it is hiding, in the same words the filter bar uses.
    var expansion: String {
        filter.constraints.map(\.text).joined(separator: ", ")
    }
}
