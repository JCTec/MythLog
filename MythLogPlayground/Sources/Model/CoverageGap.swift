import Foundation

/// A span with no recording at all.
///
/// Never mistakable for a quiet period, and never hideable by a filter — an
/// absence of recording is not an event.
struct CoverageGap: Equatable, Sendable, Identifiable {
    /// What the ledger has to say about *why* nothing was recorded.
    ///
    /// The distinction is the whole point of the analysis. A graceful stop is
    /// reassuring and boring; an unexplained silence is the case a frightened
    /// user is actually looking at.
    enum Evidence: Equatable, Sendable {
        /// The recorder wrote a stop record before going quiet. Someone quit it
        /// on purpose, or the machine shut down cleanly.
        case recordedStop(ordinal: Int)
        /// Nothing was written at all. A force-quit, a crash, a power cut, or
        /// somebody stopping the recorder in a way that left no trace.
        case unexplained
    }

    /// The last moment the recorder is known to have been running.
    var start: Date
    /// The first moment it is known to have been running again.
    var end: Date

    /// The last record before the silence, and the first one after it. Both are
    /// cumulative ordinals, so the claim is checkable: the user can look them up.
    var lastRecordBefore: Int
    var firstRecordAfter: Int

    var evidence: Evidence

    var id: Int { firstRecordAfter }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    var wasGraceful: Bool {
        if case .recordedStop = evidence { return true }
        return false
    }

    var label: String {
        "no coverage \(start.clockText) – \(end.clockText)"
    }

    /// "4 h 24 min", "18 min".
    var durationLabel: String {
        let minutes = Int((duration / 60).rounded())
        if minutes >= 1440 {
            let days = minutes / 1440
            let hours = (minutes % 1440) / 60
            return hours == 0 ? "\(days) d" : "\(days) d \(hours) h"
        }
        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
        }
        return "\(minutes) min"
    }
}

/// Finds the spans where nothing was recorded.
///
/// # Gaps come from absence, not from stop/start pairs
///
/// The obvious implementation pairs each `agent.stopped` record with the next
/// `agent.started` and calls the space between them a gap. It is wrong in the
/// one case that matters.
///
/// A graceful stop writes a record. **A force-quit, a crash, a kernel panic, or
/// pulling the power writes nothing.** Those are precisely the events a user who
/// is worried about their Mac cares about, and a stop/start implementation is
/// blind to every one of them: with no stop record there is no pair, so there is
/// no gap, so the timeline shows an unremarkable quiet afternoon over the hours
/// somebody had the machine.
///
/// So the trigger is silence itself. The recorder writes a heartbeat every
/// `heartbeat.intervalSeconds`, which puts a floor under how long the ledger can
/// legitimately stay quiet: if the recorder is running, *something* is written,
/// even when nothing happens. A stretch longer than
/// ``HeartbeatConfig/gapThreshold`` therefore means the recorder was not
/// running, whatever it did or did not say about it.
///
/// A stop record, when there is one, becomes ``CoverageGap/Evidence`` — extra
/// detail attached to a gap that was already detected, never the thing that
/// detected it.
///
/// # Why this is synchronous
///
/// It is a single pass over an array already in memory. The `async` work is the
/// streaming that produced the array; adding a suspension point here would
/// suggest a wait that never happens.
enum CoverageAnalysis {

    /// Record names that mean "the recorder is stopping on purpose". Matched
    /// against ``TimelineEvent/payloadKind``, which is `source.name` from the
    /// ledger.
    static let gracefulStopKinds: Set<String> = [
        "agent.stopped", "agent.stopping", "health.stop", "session.willPowerOff",
    ]

    /// - Parameters:
    ///   - events: in ascending time order. The loader guarantees this because
    ///     the ledger is append-only.
    ///   - threshold: how long a silence must be before it counts. Comes from
    ///     the config's heartbeat interval, not from a constant here — a user
    ///     who slowed their heartbeat down changed what "too quiet" means.
    static func gaps(in events: [TimelineEvent], threshold: TimeInterval) -> [CoverageGap] {
        guard threshold > 0, events.count > 1 else { return [] }

        var gaps = [CoverageGap]()
        for (previous, next) in zip(events, events.dropFirst()) {
            let silence = next.at.timeIntervalSince(previous.at)
            guard silence > threshold else { continue }

            gaps.append(
                CoverageGap(
                    start: previous.at,
                    end: next.at,
                    lastRecordBefore: previous.record,
                    firstRecordAfter: next.record,
                    evidence: gracefulStopKinds.contains(previous.payloadKind)
                        ? .recordedStop(ordinal: previous.record)
                        : .unexplained
                ))
        }
        return gaps
    }

    /// The gaps that overlap `window`, for the views that draw them. A gap that
    /// starts before the window and ends after it still counts — it covers the
    /// entire visible span, which is the most important case to draw.
    static func gaps(_ gaps: [CoverageGap], overlapping window: TimelineWindow) -> [CoverageGap] {
        gaps.filter { $0.end > window.start && $0.start < window.end }
    }
}
