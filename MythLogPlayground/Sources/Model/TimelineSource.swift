import Foundation

/// Where the interface's data comes from.
///
/// # The switch the design work needs
///
/// Two conformers: ``LedgerTimelineSource``, which reads a real ledger, and
/// ``MockTimelineSource``, which returns a fixture with a known four-hour gap
/// and a known 312-event burst. Previews and design decisions need determinism —
/// a layout judged against whatever happened on this Mac last Tuesday is not a
/// layout that was judged.
///
/// `MythLogApp` picks. Nothing below it knows which it got, which is what keeps
/// the design system honest: it cannot special-case the fixture.
///
/// `Sendable` because loading happens off the main actor and the source is
/// captured by the loading task.
protocol TimelineSource: Sendable {
    /// A short name for the source, for diagnostics and the human checklist.
    var describedOrigin: String { get }

    /// Loads the history.
    ///
    /// Implementations must call `Task.checkCancellation()` inside their loops:
    /// a load can be superseded by the user pointing at a different ledger, and
    /// a superseded load of a two-year history must die rather than finish.
    func load(_ request: TimelineLoadRequest) async throws -> TimelineSnapshot
}

/// What to load, and how much of it to keep.
///
/// # Why there is a cap at all
///
/// Streaming keeps the *read* bounded — one line at a time, whatever the size of
/// the ledger. It does not bound what the interface then holds: a two-year
/// ledger mapped into `TimelineEvent`s is still a two-year ledger in memory.
///
/// So the loader keeps the newest `retainedEventLimit` events and counts the
/// rest. Memory is bounded by the cap rather than by the history, and the
/// snapshot says how many records it did not keep so the interface can say so
/// too. Silently showing the newest 250,000 events as though they were
/// everything would be the same class of lie as an undrawn coverage gap.
struct TimelineLoadRequest: Equatable, Sendable {
    /// How many mapped events to hold. Roughly 200 bytes each, so the default is
    /// on the order of 50 MB — comfortable, and far more history than any zoom
    /// level renders at once.
    var retainedEventLimit: Int

    /// How long the ledger may be silent before that silence is a coverage gap.
    /// Comes from the config's heartbeat interval; see ``CoverageAnalysis``.
    var gapThreshold: TimeInterval

    /// Whether to verify the chain as part of loading. Verification reads every
    /// record a second time and computes an HMAC per record, so it is worth
    /// being able to skip while iterating on the interface.
    var verify: Bool

    init(
        retainedEventLimit: Int = 250_000,
        gapThreshold: TimeInterval = HeartbeatConfig().gapThreshold,
        verify: Bool = true
    ) {
        self.retainedEventLimit = retainedEventLimit
        self.gapThreshold = gapThreshold
        self.verify = verify
    }
}

/// How far a load has got, for a UI that must not simply freeze.
enum TimelineLoadProgress: Equatable, Sendable {
    case reading(recordsSoFar: Int)
    case verifying
    case analysing
    case finished(TimelineSnapshot)

    var describedStage: String {
        switch self {
        case .reading(let count): "Reading the ledger — \(count.formatted()) records"
        case .verifying: "Verifying the hash chain"
        case .analysing: "Looking for coverage gaps"
        case .finished: "Done"
        }
    }
}
