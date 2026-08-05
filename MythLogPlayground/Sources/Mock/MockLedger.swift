import Foundation

/// A believable day. Deliberately includes the two cases that break naive
/// layouts: a four-hour coverage gap, and a burst of 312 file events in ten
/// seconds from a single build.
///
/// # It carries heartbeats, and that is not decoration
///
/// A real recorder writes a heartbeat on a fixed interval, which puts a floor
/// under how long a healthy ledger can stay quiet. That floor is the entire
/// basis of gap detection: a silence longer than the interval allows means the
/// recorder was not running (see ``CoverageAnalysis``). A fixture without
/// heartbeats is not a small ledger, it is a *differently shaped* one — every
/// quiet half-hour in it would read as a coverage gap.
///
/// So this writes one every ``heartbeatInterval``, and stops writing them across
/// the gap. Callers build their ``TimelineLoadRequest`` from that interval.
enum MockLedger {
    static let day: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 4; c.hour = 0; c.minute = 0
        return Calendar.current.date(from: c) ?? .now
    }()

    static let now: Date = day.addingTimeInterval(14 * 3600 + 38 * 60)

    static let limit: ClosedRange<Date> = day...now

    /// The four-hour gap, and deliberately an **unexplained** one: the recorder
    /// wrote a `health.stop` record at 02:04, so this fixture also exercises the
    /// graceful case. See `MockTimelineSource` for the force-quit variant, which
    /// is the case that actually matters.
    static let gap = CoverageGap(
        start: day.addingTimeInterval(2 * 3600 + 4 * 60),
        end: day.addingTimeInterval(6 * 3600 + 28 * 60),
        lastRecordBefore: 4104,
        firstRecordAfter: 4105,
        evidence: .recordedStop(ordinal: 4104)
    )

    /// The fixture's heartbeat interval. Coarser than a real recorder's 60 s so
    /// a day fits in a readable number of rows; the analysis does not care what
    /// the number is, only that there is one.
    static let heartbeatInterval: TimeInterval = 15 * 60

    // The matching gap threshold is derived by the composition root, from
    // `heartbeatInterval` through `HeartbeatConfig`. Mock/ deliberately cannot
    // reach the Config layer — the fixture describes a ledger, it does not get
    // to decide how one is interpreted.

    static let events: [TimelineEvent] = build()

    private static func build() -> [TimelineEvent] {
        var out: [TimelineEvent] = []
        var record = 4000

        func add(_ minutes: Double, _ kind: EventKind, _ label: String, _ detail: String, _ source: String, _ payload: String) {
            record += 1
            out.append(
                TimelineEvent(
                    record: record,
                    at: day.addingTimeInterval(minutes * 60),
                    kind: kind, label: label, detail: detail,
                    source: source, payloadKind: payload
                )
            )
        }

        // A heartbeat every quarter hour, except across the gap — where the
        // recorder was not running, so nothing was written at all. That absence
        // is the only evidence the gap leaves, and it is what the analysis finds.
        let gapStartMinutes = 124.0
        let gapEndMinutes = 388.0
        for step in stride(from: 0.0, through: 878.0, by: heartbeatInterval / 60) {
            guard step < gapStartMinutes || step > gapEndMinutes else { continue }
            add(step, .health, "Recorder heartbeat", "mythlog 0.1.0 · nominal", "agent", "agent.heartbeat")
        }

        // Before the gap.
        add(24, .session, "Screen locked", "Idle 10 min", "loginwindow", "session.lock")
        add(38, .power, "System slept", "Idle sleep", "kernel", "power.sleep")
        add(124, .health, "Recorder stopped", "Terminated", "mythlogd", "health.stop")

        // — coverage gap 02:04 – 06:28 —

        add(388, .health, "Recorder started", "mythlog 0.1.0", "agent", "agent.started")
        add(402, .session, "Screen unlocked", "Touch ID", "loginwindow", "session.unlock")
        add(405, .apps, "App launched", "Mail 17.0", "com.apple.mail", "app.launched")
        add(422, .power, "Wake from sleep", "Lid opened", "kernel", "power.wake")
        add(434, .files, "File changed", "~/Documents/lease.pdf", "fseventsd", "file.modify")
        add(436, .apps, "App activated", "Xcode 16.2", "com.apple.dt.Xcode", "app.activated")

        // Morning build storm — 312 file events inside ten seconds.
        for i in 0..<312 {
            record += 1
            out.append(
                TimelineEvent(
                    record: record,
                    at: day.addingTimeInterval(9 * 3600 + 41 * 60 + Double(i) / 31.2),
                    kind: .files,
                    label: "File changed",
                    detail: "~/Projects/mythlog/.build/artifact-\(i).o",
                    source: "fseventsd",
                    payloadKind: "file.modify"
                )
            )
        }

        add(620, .drives, "Volume mounted", "\"Time Machine\" · 4 TB", "diskarbitrationd", "drive.mount")
        add(645, .session, "Screen locked", "Idle 10 min", "loginwindow", "session.lock")
        add(700, .apps, "App terminated", "Xcode 16.2", "com.apple.dt.Xcode", "app.terminated")
        add(716, .session, "Screen locked", "Idle 10 min", "loginwindow", "session.lock")
        add(740, .apps, "App terminated", "Safari 19.0", "com.apple.Safari", "app.terminated")
        add(743, .apps, "App launched", "Safari 19.0", "com.apple.Safari", "app.launched")
        add(792, .files, "File changed", "~/Documents/notes/journal.md", "fseventsd", "file.modify")
        add(818, .drives, "Volume unmounted", "\"Time Machine\" · 4 TB", "diskarbitrationd", "drive.unmount")

        // The last half hour — what the Events level shows.
        add(863, .apps, "App launched", "Preview", "com.apple.Preview", "app.launched")
        add(864, .files, "File changed", "~/Projects/mythlog/Sources/Ledger.swift", "fseventsd", "file.modify")
        add(866, .power, "Display connected", "LG UltraFine 5K", "kernel", "power.display")
        add(867, .files, "File changed", "~/Projects/mythlog/Package.resolved", "fseventsd", "file.modify")
        add(868, .drives, "Volume mounted", "\"Backup\" · 2 TB", "diskarbitrationd", "drive.mount")
        add(870, .session, "Screen unlocked", "Touch ID", "loginwindow", "session.unlock")
        add(873, .apps, "App launched", "Terminal 2.14", "com.apple.Terminal", "app.launched")
        add(877, .apps, "App activated", "Mail 17.0", "com.apple.mail", "app.activated")

        return out.sorted { $0.at < $1.at }
    }

    static var totalRecords: Int { 5362 }
    static var since: String { "since Jun 12" }
}

/// The fixture, behind the same ``TimelineSource`` a real ledger comes through.
///
/// # Why this stays
///
/// Design decisions need determinism. A layout judged against whatever happened
/// on this Mac last Tuesday has not been judged — and the two cases that break
/// naive timeline layouts, a long coverage gap and a dense burst, are exactly
/// the two a real ledger will not reliably contain on the day you need them.
///
/// It goes through `TimelineSource` rather than a back door so the interface
/// cannot tell the difference, which is the only way the fixture stays honest
/// about what the real thing will do.
struct MockTimelineSource: TimelineSource {
    /// Whether the fixture's gap looks like a clean shutdown or a force-quit.
    ///
    /// The force-quit variant is the one worth looking at: it writes no stop
    /// record at all, so a gap can only be found by noticing the silence. See
    /// ``CoverageAnalysis``.
    var gapWasGraceful: Bool

    init(gapWasGraceful: Bool = false) {
        self.gapWasGraceful = gapWasGraceful
    }

    var describedOrigin: String {
        "fixture (\(gapWasGraceful ? "graceful stop" : "force-quit"))"
    }

    func load(_ request: TimelineLoadRequest) async throws -> TimelineSnapshot {
        var events = MockLedger.events
        if !gapWasGraceful {
            // Remove the "Recorder stopped" record so the gap has no explanation
            // in the ledger — a force-quit, which is what a worried user is
            // usually looking at.
            events.removeAll { $0.payloadKind == "health.stop" }
        }

        // Derived by the same analysis the real loader uses, rather than
        // hard-coded, so the fixture cannot drift away from the algorithm.
        let gaps = CoverageAnalysis.gaps(in: events, threshold: request.gapThreshold)

        return TimelineSnapshot(
            events: events,
            gaps: gaps,
            history: MockLedger.limit,
            totalRecords: MockLedger.totalRecords,
            omittedOlderRecords: MockLedger.totalRecords - events.count,
            firstRetainedAt: events.first?.at,
            integrity: .verified(recordCount: MockLedger.totalRecords),
            origin: describedOrigin
        )
    }
}
