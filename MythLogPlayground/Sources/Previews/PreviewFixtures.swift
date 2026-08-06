import Foundation

/// Shared setup for the previews.
///
/// Previews are a composition root, so this may reach across layers freely —
/// which is exactly why the derivation lives here rather than in `Mock/`.
extension TimelineLoadRequest {
    /// Matches the fixture's heartbeat interval, so gap detection over it
    /// behaves as it does over a real ledger: three missed heartbeats.
    static var fixtureRequest: TimelineLoadRequest {
        TimelineLoadRequest(
            gapThreshold: HeartbeatConfig(intervalSeconds: MockLedger.heartbeatInterval).gapThreshold)
    }
}
