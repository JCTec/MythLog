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
/// # The configured cadence is a claim; the ledger is the evidence
///
/// The threshold arrives from `config.json`, and often that config is not there
/// to arrive from. `LedgerDiscovery` falls back to `HeartbeatConfig()` — 60 s,
/// so 180 s of silence — for any ledger opened by hand rather than auto-detected
/// beside its config, which is most of them.
///
/// A default is a guess, and a guess this tight fabricates gaps. Measured
/// against this repository's own shipping-ledger fixture, which has no
/// `config.json`: its heartbeats are 1096 s apart and its median record spacing
/// is 137 s, against a threshold of 180 s. Every ordinary quiet stretch in it is
/// within a rounding error of being reported as "the recorder was not running".
/// That is what produced clusters of short gaps with recorded events sitting
/// between them — and no amount of tidying the hatching would have made those
/// gaps true.
///
/// So the ledger gets a say. ``observedHeartbeatInterval(in:)`` measures the
/// cadence the records actually demonstrate, and the effective threshold is the
/// larger of the two. Raising it can only ever withdraw a claim that the ledger
/// could not support: if heartbeats really arrive every eighteen minutes, a
/// four-minute silence is not evidence of anything. The configured value is
/// never lowered — a user who says their recorder beats every 60 s is entitled
/// to have three missed beats taken seriously.
///
/// A ledger with no heartbeat records at all cannot be measured, and then the
/// configured threshold stands. That case deserves better than it gets here:
/// with heartbeats disabled there is no floor under legitimate silence at all,
/// so silence proves nothing and gap detection is not really possible. See the
/// note in `README.md`.
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

    /// Whether a record is a heartbeat.
    ///
    /// Matched on the last component of ``TimelineEvent/payloadKind``, which is
    /// `source.name` from the ledger: the shipping recorder writes
    /// `agent.agent.heartbeat` and the fixture writes `agent.heartbeat`. What
    /// they have in common is the only part worth matching on.
    static func isHeartbeat(_ event: TimelineEvent) -> Bool {
        event.payloadKind.split(separator: ".").last == "heartbeat"
    }

    /// The heartbeat cadence the ledger actually demonstrates, or `nil` when it
    /// does not demonstrate one.
    ///
    /// The **median** interval, not the mean: a heartbeat sequence interrupted
    /// by a genuine four-hour outage contains one enormous interval, and a mean
    /// would let that outage raise the threshold until it stopped being
    /// detectable. The median ignores it, which is the whole reason to use one.
    ///
    /// Three heartbeats — two intervals — is the minimum that can be called a
    /// cadence. Below that, `nil`.
    static func observedHeartbeatInterval(in events: [TimelineEvent]) -> TimeInterval? {
        let beats = events.filter(isHeartbeat).map(\.at).sorted()
        guard beats.count >= 3 else { return nil }

        let intervals = zip(beats, beats.dropFirst())
            .map { $1.timeIntervalSince($0) }
            .filter { $0 > 0 }
            .sorted()
        guard !intervals.isEmpty else { return nil }

        return intervals[intervals.count / 2]
    }

    /// - Parameters:
    ///   - events: in ascending time order. The loader guarantees this because
    ///     the ledger is append-only.
    ///   - threshold: how long a silence must be before it counts. Comes from
    ///     the config's heartbeat interval, not from a constant here — a user
    ///     who slowed their heartbeat down changed what "too quiet" means. It is
    ///     a floor, not the final word: see the type's doc comment for why the
    ///     ledger's own measured cadence can raise it.
    static func gaps(in events: [TimelineEvent], threshold: TimeInterval) -> [CoverageGap] {
        guard threshold > 0, events.count > 1 else { return [] }

        let effective = effectiveThreshold(configured: threshold, events: events)

        var gaps = [CoverageGap]()
        for (previous, next) in zip(events, events.dropFirst()) {
            let silence = next.at.timeIntervalSince(previous.at)
            guard silence > effective else { continue }

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

    /// The threshold actually applied: the configured one, or three of the
    /// ledger's own observed heartbeat intervals when those are longer.
    ///
    /// The multiplier is ``HeartbeatConfig/missedHeartbeatsForGap``, reused
    /// rather than repeated — "three missed heartbeats" must mean the same thing
    /// whether the interval came from a config file or from the records.
    static func effectiveThreshold(configured: TimeInterval, events: [TimelineEvent]) -> TimeInterval {
        guard let observed = observedHeartbeatInterval(in: events) else { return configured }
        return max(configured, HeartbeatConfig(intervalSeconds: observed).gapThreshold)
    }

    /// The gaps that overlap `window`, for the views that draw them. A gap that
    /// starts before the window and ends after it still counts — it covers the
    /// entire visible span, which is the most important case to draw.
    static func gaps(_ gaps: [CoverageGap], overlapping window: TimelineWindow) -> [CoverageGap] {
        gaps.filter { $0.end > window.start && $0.start < window.end }
    }
}
