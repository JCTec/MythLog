import SwiftUI

// Previews are a composition root, exactly like `MythLogApp`: they decide where
// the interface's data comes from. That is why they live here rather than beside
// the views — `DesignSystem/` may reference view models and nothing else, and a
// `#Preview` that names a fixture would breach that just as surely as a page
// doing it.
//
// The fixture is the right choice for design work: it contains a known coverage
// gap and a known 312-event burst, which is what makes layout decisions
// reproducible. No real ledger reliably contains either on the day you need it.

/// The default: a gap the ledger cannot explain, which is the case a worried
/// user is usually looking at.
#Preview("Main page — force-quit gap") {
    MainPage(
        source: MockTimelineSource(gapWasGraceful: false),
        request: .forFixture
    )
    .preferredColorScheme(.dark)
}

/// The same gap, with a stop record before it. The banner has to say something
/// different — and less alarming — for this one.
#Preview("Main page — graceful stop") {
    MainPage(
        source: MockTimelineSource(gapWasGraceful: true),
        request: .forFixture
    )
    .preferredColorScheme(.dark)
}

#Preview("Ledger status badges") {
    VStack(alignment: .leading, spacing: Metrics.space3) {
        RecorderStatusPill(isRunning: true, heartbeat: "4 s")
        RecorderStatusPill(isRunning: false, heartbeat: "")
        LedgerStatusBadge(state: .unverified)
        LedgerStatusBadge(state: .verified(recordCount: 5362))
        LedgerStatusBadge(state: .failed(lastTrustedOrdinal: 3200, issueCount: 12, recordCount: 5362))
        LedgerStatusBadge(state: .truncated(localRecords: 5362, anchoredRecords: 5410))
        LedgerStatusBadge(state: .anchorOffline(recordCount: 5362))
        LedgerStatusBadge(state: .unreadable(reason: "The ledger file could not be opened."))
    }
    .padding()
    .background(Palette.canvas)
}

extension TimelineLoadRequest {
    /// Matches the fixture's heartbeat interval, so gap detection over it
    /// behaves exactly as it does over a real ledger — three missed heartbeats.
    static var forFixture: TimelineLoadRequest {
        TimelineLoadRequest(
            gapThreshold: HeartbeatConfig(intervalSeconds: MockLedger.heartbeatInterval).gapThreshold)
    }
}
