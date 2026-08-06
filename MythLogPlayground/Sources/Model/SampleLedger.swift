import Foundation

/// A ready-made history offered alongside the real ones.
///
/// # Why the design system cannot name a fixture
///
/// `LedgerCandidate` describes something found on disk. A sample has no file, no
/// key, and no path — and, more importantly, `Mock/` is *below* `Model/` in the
/// layering, so nothing here may reach into it. `Scripts/check-layering.sh`
/// catches the attempt.
///
/// That rule is not bureaucracy. The whole point of the source seam is that the
/// interface cannot tell a fixture from a real ledger, and it stops being true
/// the moment a view can say `MockLedger`. So the composition root builds the
/// samples and hands them down as already-constructed sources; everything below
/// sees a title, a sentence, and something that loads.
struct SampleLedger: Identifiable, Sendable {
    var id: String
    var title: String
    var detail: String
    var source: any TimelineSource
    /// The heartbeat interval this sample was "recorded" with.
    ///
    /// Carried as a plain interval rather than a built ``TimelineLoadRequest``
    /// so that `Mock/` — which may reference `Primitives/` and `Model/` and
    /// nothing else — can describe a sample without reaching into `Config/`.
    /// Turning it into a gap threshold is this layer's job.
    var heartbeatInterval: TimeInterval

    /// Gap detection over a sample behaves exactly as it does over a real
    /// ledger: three missed heartbeats.
    var request: TimelineLoadRequest {
        TimelineLoadRequest(
            gapThreshold: HeartbeatConfig(intervalSeconds: heartbeatInterval).gapThreshold)
    }

    var loaded: LoadedLedger {
        LoadedLedger(badge: "Sample", title: title, path: nil, isRealHistory: false)
    }
}

/// What is open, as the header describes it.
///
/// Deliberately the same shape whether it came from a real ledger or a sample:
/// the header's job is to say *which*, and a type that could only describe one
/// of them would make the other the unlabelled default.
struct LoadedLedger: Equatable, Sendable {
    var badge: String
    var title: String
    /// `nil` for a sample, which has no file.
    var path: String?
    /// The one bit a reader of a screenshot cannot otherwise recover.
    var isRealHistory: Bool
}
