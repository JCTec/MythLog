import Foundation

/// The fixture, offered through ``SampleLedger`` so the chooser can list it
/// without any part of the design system knowing a fixture exists.
///
/// `Mock/` may reference `Model/`, which is what makes this the right side of
/// the boundary. The reverse — `Model/` reaching for `MockLedger` — is what
/// `Scripts/check-layering.sh` rejects, and rightly: the interface must not be
/// able to special-case sample data, or the claim that it cannot tell a fixture
/// from a real ledger stops being true.
extension MockTimelineSource {
    /// Both gap variants, in the order a person should meet them.
    ///
    /// The force-quit one comes first because it is the case that matters: a
    /// crash or a pulled plug writes no stop record at all, and a design judged
    /// only against the tidy version has not been judged.
    static var samples: [SampleLedger] {
        [
            SampleLedger(
                id: "sample-forcequit",
                title: "Sample day",
                detail: "A believable day with a four-hour gap the recorder never explained — a force quit, "
                    + "a crash, or a pulled plug — and a 312-event burst. No real history; safe for screenshots.",
                source: MockTimelineSource(gapWasGraceful: false),
                heartbeatInterval: MockLedger.heartbeatInterval
            ),
            SampleLedger(
                id: "sample-graceful",
                title: "Sample day — stopped cleanly",
                detail: "The same day, with a stop record before the gap. The banner says something quite "
                    + "different about this one, which is the point of having both.",
                source: MockTimelineSource(gapWasGraceful: true),
                heartbeatInterval: MockLedger.heartbeatInterval
            ),
        ]
    }
}
