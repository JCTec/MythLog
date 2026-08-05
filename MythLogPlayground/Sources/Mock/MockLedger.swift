import Foundation

/// A believable day. Deliberately includes the two cases that break naive
/// layouts: a four-hour coverage gap, and a burst of 312 file events in ten
/// seconds from a single build.
enum MockLedger {
    static let day: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 4; c.hour = 0; c.minute = 0
        return Calendar.current.date(from: c) ?? .now
    }()

    static let now: Date = day.addingTimeInterval(14 * 3600 + 38 * 60)

    static let limit: ClosedRange<Date> = day...now

    static let gap = CoverageGap(
        start: day.addingTimeInterval(2 * 3600 + 4 * 60),
        end: day.addingTimeInterval(6 * 3600 + 28 * 60),
        stoppedRecord: 4101,
        restartedRecord: 4102
    )

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

        // Before the gap.
        add(24, .session, "Screen locked", "Idle 10 min", "loginwindow", "session.lock")
        add(38, .power, "System slept", "Idle sleep", "kernel", "power.sleep")
        add(96, .health, "Recorder heartbeat", "mythlog 0.1.0 · nominal", "mythlogd", "health.heartbeat")
        add(124, .health, "Recorder stopped", "Terminated", "mythlogd", "health.stop")

        // — coverage gap 02:04 – 06:28 —

        add(388, .health, "Recorder started", "mythlog 0.1.0", "mythlogd", "health.start")
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
        add(760, .health, "Recorder heartbeat", "mythlog 0.1.0 · nominal", "mythlogd", "health.heartbeat")
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

extension MockLedger {
    /// The mock as the interface consumes it. Kept behind the same
    /// ``TimelineSnapshot`` the real loader produces, so previews and design work
    /// stay deterministic without the page knowing a fixture exists.
    static var snapshot: TimelineSnapshot {
        TimelineSnapshot(
            events: events,
            gap: gap,
            history: limit,
            totalRecords: totalRecords,
            since: since,
            integrity: .verified
        )
    }
}
