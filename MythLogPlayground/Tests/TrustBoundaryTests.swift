import Foundation
import Testing

@testable import MythLog

/// Trust is positional, and getting that wrong is the difference between
/// "twelve records were altered" and "your history is fine".
@Suite("Trust boundary")
struct TrustBoundaryTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func events(_ ordinals: [Int]) -> [TimelineEvent] {
        ordinals.map { ordinal in
            TimelineEvent(
                record: ordinal,
                at: base.addingTimeInterval(Double(ordinal) * 60),
                kind: .session,
                label: "Event \(ordinal)",
                detail: "",
                source: "test",
                payloadKind: "test.event"
            )
        }
    }

    @Test("a failed verification puts the boundary at the first record after the break")
    func failedResolvesToTheBreak() throws {
        let boundary = try #require(
            TrustBoundary.resolve(
                integrity: .failed(lastTrustedOrdinal: 5, issueCount: 3, recordCount: 10),
                events: events(Array(1...10))
            ))

        #expect(boundary.lastTrustedOrdinal == 5)
        #expect(boundary.firstUntrustedOrdinal == 6)
        #expect(boundary.firstUntrustedAt == base.addingTimeInterval(360))
        #expect(!boundary.nothingIsTrusted)
    }

    @Test("every record after the break is untrusted, including ones that hash correctly")
    func trustIsPositional() throws {
        let boundary = try #require(
            TrustBoundary.resolve(
                integrity: .failed(lastTrustedOrdinal: 5, issueCount: 1, recordCount: 10),
                events: events(Array(1...10))
            ))

        // Only *one* record was reported as an issue. Everything after it is
        // still untrusted, because an attacker who edits #6 can recompute every
        // hash from #7 onwards — those records look internally perfect and are
        // exactly the ones a per-record check would clear.
        for ordinal in 1...5 { #expect(boundary.trusts(ordinal: ordinal)) }
        for ordinal in 6...10 { #expect(!boundary.trusts(ordinal: ordinal)) }
    }

    @Test("a state where nothing verifies is distinct from a state with no boundary")
    func nothingTrustedIsNotTheSameAsNoBoundary() throws {
        let nothing = try #require(
            TrustBoundary.resolve(
                integrity: .failed(lastTrustedOrdinal: 0, issueCount: 10, recordCount: 10),
                events: events(Array(1...10))
            ))
        #expect(nothing.nothingIsTrusted)
        #expect(!nothing.trusts(ordinal: 1))

        // `.verified` has no boundary at all, which must not collapse into
        // "the boundary is at zero".
        #expect(TrustBoundary.resolve(integrity: .verified(recordCount: 10), events: events(Array(1...10))) == nil)
    }

    @Test("truncation has no boundary — everything still present verifies")
    func truncationHasNoBoundary() {
        // Records were removed from the *end*. What remains is intact, so
        // marking any of it untrusted would be a false accusation.
        #expect(
            TrustBoundary.resolve(
                integrity: .truncated(localRecords: 8, anchoredRecords: 10),
                events: events(Array(1...8))
            ) == nil)
    }

    @Test("an unreadable ledger trusts nothing")
    func unreadableTrustsNothing() throws {
        let boundary = try #require(
            TrustBoundary.resolve(integrity: .unreadable(reason: "…"), events: events(Array(1...10))))
        #expect(boundary.nothingIsTrusted)
        #expect(!boundary.trusts(ordinal: 1))
    }

    @Test("a boundary outside the loaded history is still a boundary")
    func boundaryOffScreenStillResolves() throws {
        // The break is at #6, but only records 1–5 were retained. The boundary
        // is real; it simply has no date to be drawn at.
        let boundary = try #require(
            TrustBoundary.resolve(
                integrity: .failed(lastTrustedOrdinal: 5, issueCount: 3, recordCount: 10),
                events: events(Array(1...5))
            ))
        #expect(boundary.firstUntrustedOrdinal == 6)
        #expect(boundary.firstUntrustedAt == nil)
    }

    @Test("the boundary is found by ordinal, not by position in a time-sorted array")
    func boundaryFollowsOrdinalsNotOrder() throws {
        // Ledger order is append order and the timeline is sorted by time, so
        // the first untrusted *ordinal* need not be the first untrusted
        // *position*. Ordinals 8 and 9 are stamped before 6 and 7 here.
        var out = events([1, 2, 3, 4, 5])
        out.append(contentsOf: [
            TimelineEvent(record: 8, at: base.addingTimeInterval(10), kind: .health,
                          label: "", detail: "", source: "t", payloadKind: "t.e"),
            TimelineEvent(record: 6, at: base.addingTimeInterval(9_000), kind: .health,
                          label: "", detail: "", source: "t", payloadKind: "t.e"),
        ])
        out.sort { $0.at < $1.at }

        let boundary = try #require(
            TrustBoundary.resolve(
                integrity: .failed(lastTrustedOrdinal: 5, issueCount: 2, recordCount: 8),
                events: out
            ))
        #expect(boundary.firstUntrustedOrdinal == 6)
    }
}

@Suite("Integrity presentation")
struct IntegrityStatePresentationTests {

    private let all: [IntegrityState] = [
        .unverified,
        .verified(recordCount: 5362),
        .failed(lastTrustedOrdinal: 3200, issueCount: 12, recordCount: 5362),
        .truncated(localRecords: 5362, anchoredRecords: 5410),
        .anchorOffline(recordCount: 5362),
        .unreadable(reason: "The ledger file could not be opened."),
    ]

    @Test("only the states with something to say get a banner")
    func bannerStates() {
        #expect(!IntegrityState.unverified.needsBanner)
        #expect(!IntegrityState.verified(recordCount: 1).needsBanner)
        for state in all where state.needsBanner {
            // A banner with no words is worse than no banner.
            #expect(!state.bannerTitle.isEmpty, "\(state) has a banner with no title")
            #expect(!state.bannerBody.isEmpty, "\(state) has a banner with no body")
            #expect(!state.bannerAction.isEmpty)
        }
    }

    /// Colour cannot be the only carrier. Two states that share a severity must
    /// still be tellable apart in greyscale, which means a distinct symbol.
    @Test("every state has its own symbol")
    func symbolsAreDistinct() {
        let symbols = all.map(\.symbol)
        #expect(Set(symbols).count == all.count, "two states share a glyph: \(symbols)")
    }

    @Test("truncation is an alarm, not a caution")
    func truncationIsAnAlarm() {
        // Records were removed from the end and the chain cannot see it. That is
        // the attack the anchor exists to catch, so the one time it fires it
        // must not read as a nuisance.
        #expect(IntegrityState.truncated(localRecords: 1, anchoredRecords: 2).severity == .alarm)
        #expect(IntegrityState.anchorOffline(recordCount: 1).severity == .caution)
        #expect(IntegrityState.verified(recordCount: 1).severity == .calm)
    }

    @Test("evidence is offered where evidence is at stake")
    func secondaryActions() {
        #expect(IntegrityState.failed(lastTrustedOrdinal: 1, issueCount: 1, recordCount: 2)
            .bannerSecondaryAction == "Export proof bundle")
        #expect(IntegrityState.truncated(localRecords: 1, anchoredRecords: 2)
            .bannerSecondaryAction == "Export proof bundle")
        #expect(IntegrityState.verified(recordCount: 1).bannerSecondaryAction == nil)
    }

    @Test("a failing ledger never describes itself as empty or calm")
    func failureIsNeverCalm() {
        let failed = IntegrityState.failed(lastTrustedOrdinal: 3200, issueCount: 12, recordCount: 5362)
        #expect(!failed.isHealthy)
        #expect(failed.severity == .alarm)
        #expect(failed.bannerBody.contains("cannot be trusted"))

        let unreadable = IntegrityState.unreadable(reason: "gone")
        #expect(unreadable.bannerBody.contains("not an empty history"))
    }
}
