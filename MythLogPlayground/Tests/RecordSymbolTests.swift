import AppKit
import Foundation
import Testing

@testable import MythLog

/// The glyph beside a record's headline, which is not the glyph for its
/// category.
///
/// Six categories is the right granularity for a filter chip and the wrong
/// granularity for an icon: "Screen locked" and "Screen unlocked" are opposite
/// facts that shared one padlock, so the icon carried no information in exactly
/// the place a reader was most likely to lean on it.
@Suite("Per-record symbols")
struct RecordSymbolTests {

    private func event(_ payloadKind: String, kind: EventKind = .session) -> TimelineEvent {
        TimelineEvent(
            record: 1,
            at: Date(timeIntervalSince1970: 1_770_000_000),
            kind: kind,
            label: "Event",
            detail: "detail",
            source: "test",
            payloadKind: payloadKind
        )
    }

    /// The case that motivated the whole thing.
    @Test("locking and unlocking do not share a glyph")
    func lockAndUnlock() {
        let locked = event("session.lock")
        let unlocked = event("session.unlock")

        #expect(locked.symbol != unlocked.symbol)
        #expect(locked.symbol == "lock.fill")
        #expect(unlocked.symbol == "lock.open.fill")
    }

    /// The shipping recorder writes `agent.agent.heartbeat` and the fixture
    /// writes `agent.heartbeat`. What they have in common is the only part worth
    /// matching on, and the same rule is used by ``CoverageAnalysis/isHeartbeat(_:)``
    /// — the two must not disagree about what a record is.
    @Test("the two spellings of a heartbeat agree")
    func heartbeatSpellings() {
        let shipping = event("agent.agent.heartbeat", kind: .health)
        let fixture = event("agent.heartbeat", kind: .health)

        #expect(shipping.symbol == fixture.symbol)
        #expect(CoverageAnalysis.isHeartbeat(shipping) == CoverageAnalysis.isHeartbeat(fixture))
    }

    /// The honest default. An invented glyph per payload kind would be a legend
    /// nobody can learn, and later waves add kinds that do not exist yet.
    @Test("an unknown payload kind falls back to its category")
    func unknownFallsBack() {
        for kind in EventKind.allCases {
            #expect(event("something.nobody.modelled", kind: kind).symbol == kind.symbol)
            // A payload kind with no dots at all is still a payload kind.
            #expect(event("bare", kind: kind).symbol == kind.symbol)
            #expect(event("", kind: kind).symbol == kind.symbol)
        }
    }

    /// Session is a person, not a padlock. A padlock beside a record title asks
    /// a question the reader has to resolve — is this an unlock event, or is
    /// this telling me something is insecure? — and padlocks are reserved for
    /// the two records that genuinely are about locking.
    @Test("the session category is not a padlock")
    func sessionIsNotAPadlock() {
        #expect(EventKind.session.symbol == "person.crop.circle")
        for kind in EventKind.allCases {
            #expect(!kind.symbol.hasPrefix("lock"))
        }
    }

    /// Every symbol named anywhere in the design resolves against the SDK this
    /// build is compiled with. A missing SF Symbol is not a compile error — it
    /// is a blank space at runtime, which is the failure mode most likely to
    /// survive review.
    @Test("every symbol the design names actually exists")
    func symbolsResolve() {
        let directional = [
            "session.lock", "session.unlock", "power.sleep", "power.wake",
            "power.display", "drives.mount", "drives.unmount", "apps.launched",
            "apps.terminated", "health.stop", "agent.started",
        ]
        var names = Set(EventKind.allCases.map(\.symbol))
        for kind in directional { names.insert(event(kind).symbol) }

        for name in names {
            // `Image(systemName:)` accepts anything and draws nothing;
            // `NSImage` is the only thing here that actually looks it up.
            #expect(
                NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                "\(name) is not a symbol in this SDK — it renders as a blank")
        }
    }
}

/// A gap said in one line, for the second and every subsequent card.
///
/// A real ledger has many gaps. The line is what a reader scanning six cards
/// actually reads, so every fact that makes the claim checkable has to survive
/// the compression — the prose is what gets dropped, never the evidence.
@Suite("What a gap says in one line")
struct CoverageGapSummaryTests {

    private let base = Date(timeIntervalSince1970: 1_770_000_000)

    private func gap(
        minutes: Double, evidence: CoverageGap.Evidence, before: Int = 4_628, after: Int = 4_629
    ) -> CoverageGap {
        CoverageGap(
            start: base,
            end: base.addingTimeInterval(minutes * 60),
            lastRecordBefore: before,
            firstRecordAfter: after,
            evidence: evidence
        )
    }

    @Test("the line carries the duration, both ordinals, and the range")
    func facts() {
        let g = gap(minutes: 264, evidence: .unexplained, before: 4_628, after: 4_713)
        let line = g.summaryLine

        #expect(line.contains(g.durationLabel))
        #expect(line.contains("4 h 24 min"))
        #expect(line.contains(g.rangeLabel))
        #expect(line.contains("4,628"))
        #expect(line.contains("4,713"))
        #expect(line.contains(g.boundsLabel))
    }

    /// The unexplained case is the one a frightened user is looking at, and a
    /// card scanned rather than read must not leave the impression that every
    /// gap is accounted for.
    @Test("an unexplained gap says so, in those words")
    func unexplained() {
        #expect(gap(minutes: 90, evidence: .unexplained).summaryLine.contains("no stop record"))
    }

    @Test("a graceful stop says the ledger explained itself")
    func graceful() {
        let g = gap(minutes: 90, evidence: .recordedStop(ordinal: 4_628))
        #expect(g.summaryLine.contains("stop record written"))
        #expect(!g.summaryLine.contains("no stop record"))
        #expect(g.wasGraceful)
    }

    /// Ordinals are how a claim about the ledger is checked, so they are written
    /// the way every other count in the app is written.
    @Test("ordinals carry thousands separators")
    func separators() {
        #expect(gap(minutes: 5, evidence: .unexplained, before: 34_395, after: 34_396)
            .boundsLabel == "#34,395→#34,396")
    }

    /// A gap crossing midnight is the commonest long gap there is — a machine
    /// left off overnight — and it is also the one whose duration matters most.
    @Test("a gap across midnight names both days in its line")
    func acrossMidnight() {
        let calendar = Calendar.current
        let start = calendar.date(
            from: DateComponents(year: 2026, month: 6, day: 10, hour: 13, minute: 31))!
        let g = CoverageGap(
            start: start,
            end: start.addingTimeInterval(22 * 3600 + 25 * 60),
            lastRecordBefore: 1,
            firstRecordAfter: 2,
            evidence: .unexplained
        )

        #expect(g.durationLabel == "22 h 25 min")
        #expect(g.summaryLine.contains(start.formatted(.dateTime.weekday(.abbreviated))))
        #expect(g.summaryLine.contains("→"))
    }
}
