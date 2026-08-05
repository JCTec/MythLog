import Foundation

/// Where trustworthy history ends.
///
/// # Why this is a first-class value
///
/// Verification produces a number — "records #1 to #3,200 verify" — and a number
/// is the one form nobody reads. The boundary has to be a *place*: a line across
/// the timeline, a rule in the list, a strip in the inspector. All three need the
/// same two facts, and computing them separately is how a timeline and a list end
/// up disagreeing about where trust ended.
///
/// # Trust is positional
///
/// This is the part that is easy to get wrong. Each record after a break still
/// hashes correctly *against its own predecessor* — an attacker who edits record
/// 3,201 and recomputes everything after it produces a chain that looks
/// internally perfect from 3,201 onwards. What they cannot do is make 3,201 link
/// back to 3,200 without the key.
///
/// So the verdict on a record is not a property of that record. It is a property
/// of its position relative to the first break. A per-record "looks fine" check
/// would mark almost every altered record as trustworthy.
struct TrustBoundary: Equatable, Sendable {
    /// The last record that verifies. `0` when nothing does.
    var lastTrustedOrdinal: Int

    /// The first record that cannot be trusted.
    var firstUntrustedOrdinal: Int

    /// When that record was recorded, so the boundary can be drawn on a time
    /// axis. `nil` when the first untrusted record is outside the loaded
    /// history — the boundary is real, it is just not on screen.
    var firstUntrustedAt: Date?

    /// Whether `ordinal` falls on the trustworthy side.
    func trusts(ordinal: Int) -> Bool { ordinal <= lastTrustedOrdinal }

    /// The whole history is suspect — there is no trustworthy span to point at.
    var nothingIsTrusted: Bool { lastTrustedOrdinal == 0 }

    /// Derives the boundary from a verification result and the loaded events.
    ///
    /// Returns `nil` when the concept does not apply, which is the common case
    /// and must stay distinct from "the boundary is at zero".
    ///
    /// `events` is expected in ascending time order, which is what
    /// ``LedgerTimelineSource`` guarantees. The first untrusted record by
    /// *ordinal* is found by ordinal rather than by position, because ledger
    /// order and time order are not the same thing.
    static func resolve(integrity: IntegrityState, events: [TimelineEvent]) -> TrustBoundary? {
        guard let lastTrusted = integrity.lastTrustedOrdinal else { return nil }

        let firstUntrusted =
            events
            .filter { $0.record > lastTrusted }
            .min { $0.record < $1.record }

        return TrustBoundary(
            lastTrustedOrdinal: lastTrusted,
            firstUntrustedOrdinal: firstUntrusted?.record ?? lastTrusted + 1,
            firstUntrustedAt: firstUntrusted?.at
        )
    }
}
