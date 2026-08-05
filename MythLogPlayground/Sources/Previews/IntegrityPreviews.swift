import SwiftUI

// Every integrity state, over the fixture.
//
// The gate for Phase A is that all four states are reachable here, visually
// distinct, and legible in greyscale. To check the last one, turn on
// System Settings ▸ Accessibility ▸ Display ▸ Colour Filters ▸ Greyscale and
// read these again — every state must still be tellable apart by its symbol,
// its border weight, and whether it is hatched.

private func fixture(_ integrity: IntegrityState) -> MockTimelineSource {
    MockTimelineSource(gapWasGraceful: false, integrity: integrity)
}

// MARK: - The whole page, per state

#Preview("Page — verified") {
    MainPage(source: fixture(.verified(recordCount: MockLedger.totalRecords)), request: .forFixture)
        .preferredColorScheme(.dark)
}

/// The one that matters. A trust boundary should be visible in three places at
/// once: a rule in the list, a shaded span on the timeline, and a strip at the
/// top of the inspector when an untrusted record is selected.
#Preview("Page — verification failed") {
    MainPage(source: fixture(MockTimelineSource.brokenChain), request: .forFixture)
        .preferredColorScheme(.dark)
}

#Preview("Page — history truncated") {
    MainPage(
        source: fixture(.truncated(localRecords: MockLedger.totalRecords, anchoredRecords: MockLedger.totalRecords + 48)),
        request: .forFixture
    )
    .preferredColorScheme(.dark)
}

#Preview("Page — anchor offline") {
    MainPage(source: fixture(.anchorOffline(recordCount: MockLedger.totalRecords)), request: .forFixture)
        .preferredColorScheme(.dark)
}

#Preview("Page — ledger unreadable") {
    MainPage(
        source: fixture(.unreadable(reason: "The ledger file could not be opened: Operation not permitted.")),
        request: .forFixture
    )
    .preferredColorScheme(.dark)
}

// MARK: - The banner alone

/// Side by side, which is the only way to judge whether the severities actually
/// separate. `.verified` and `.unverified` are absent on purpose — they do not
/// get a banner, and a preview that showed one would be showing something the
/// app never does.
#Preview("Banners — every state that gets one") {
    ScrollView {
        VStack(spacing: Metrics.space4) {
            ForEach(
                [
                    IntegrityState.failed(lastTrustedOrdinal: 3200, issueCount: 12, recordCount: 5362),
                    .truncated(localRecords: 5362, anchoredRecords: 5410),
                    .anchorOffline(recordCount: 5362),
                    .unreadable(reason: "The ledger file could not be opened: Operation not permitted."),
                ]
            ) { state in
                IntegrityBanner(state: state, onPrimary: {}, onSecondary: {})
            }
        }
        .padding(Metrics.space5)
        .frame(width: 720)
    }
    .background(WindowBackground())
    .preferredColorScheme(.dark)
}

// MARK: - The pieces

#Preview("Header badges") {
    VStack(alignment: .leading, spacing: Metrics.space3) {
        RecorderStatusPill(isRunning: true, heartbeat: "4 s")
        RecorderStatusPill(isRunning: false, heartbeat: "")
        LedgerStatusBadge(state: .unverified)
        LedgerStatusBadge(state: .verified(recordCount: 5362))
        LedgerStatusBadge(state: .anchorOffline(recordCount: 5362))
        LedgerStatusBadge(state: .truncated(localRecords: 5362, anchoredRecords: 5410))
        LedgerStatusBadge(state: .failed(lastTrustedOrdinal: 3200, issueCount: 12, recordCount: 5362))
        LedgerStatusBadge(state: .unreadable(reason: "…"))
    }
    .padding(Metrics.space5)
    .background(Palette.canvas)
    .preferredColorScheme(.dark)
}

#Preview("Trust boundary and verdicts") {
    VStack(alignment: .leading, spacing: Metrics.space4) {
        TrustVerdictBadge(isTrusted: true, prominence: .inline, explanation: nil)
        TrustVerdictBadge(isTrusted: false, prominence: .inline, explanation: nil)

        TrustVerdictBadge(
            isTrusted: false,
            prominence: .banner,
            explanation: "The chain breaks at #3,201. This record sits after the break, so it cannot be "
                + "relied on — even though its own hash is consistent with the record before it."
        )

        TrustBoundaryMarker(
            boundary: TrustBoundary(
                lastTrustedOrdinal: 3200, firstUntrustedOrdinal: 3201, firstUntrustedAt: .now))

        TrustBoundaryMarker(
            boundary: TrustBoundary(
                lastTrustedOrdinal: 0, firstUntrustedOrdinal: 1, firstUntrustedAt: .now))
    }
    .padding(Metrics.space5)
    .frame(width: 620)
    .background(Palette.canvas)
    .preferredColorScheme(.dark)
}
