import SwiftUI

// The four gap shapes that decide whether the overlay is right, each built from
// a ledger rather than from hand-written rectangles.
//
// Previews are a composition root, so this may reach across layers freely — and
// it uses that to derive the gaps with `CoverageAnalysis`, exactly as the loader
// does. A preview that positioned its own hatching would be a drawing of the
// intended result rather than a rendering of the real one, which is how the
// misalignment survived being looked at.

/// A ledger with silences in it, at a known heartbeat cadence.
private enum GapShapes {

    /// Fixed, so every preview renders the same picture on every machine.
    static let start = Date(timeIntervalSince1970: 1_770_000_000)

    /// A real recorder's cadence, which makes the 180 s threshold the honest one
    /// here — and keeps the measured floor in ``CoverageAnalysis`` from raising
    /// it, since the records demonstrate the same 60 s the config claims.
    static let heartbeat: TimeInterval = 60
    static var threshold: TimeInterval { HeartbeatConfig(intervalSeconds: heartbeat).gapThreshold }

    /// Heartbeats every minute across `minutes`, minus the silences, with a few
    /// coloured events so the cluster bars have something to stack.
    ///
    /// - Parameter silences: half-open minute ranges during which the recorder
    ///   wrote nothing at all — a force quit, a crash, or a power cut.
    static func events(minutes: Double, silences: [Range<Double>]) -> [TimelineEvent] {
        var out = [TimelineEvent]()
        var record = 1_000

        for minute in stride(from: 0.0, through: minutes, by: heartbeat / 60) {
            guard !silences.contains(where: { $0.contains(minute) }) else { continue }
            record += 1
            out.append(
                TimelineEvent(
                    record: record, at: start.addingTimeInterval(minute * 60), kind: .health,
                    label: "Recorder heartbeat", detail: "nominal",
                    source: "agent", payloadKind: "agent.heartbeat"
                ))
        }

        let colour: [(Double, EventKind, String)] = [
            (12, .session, "Screen unlocked"), (37, .apps, "App launched"),
            (63, .files, "File changed"), (96, .power, "Wake from sleep"),
            (141, .apps, "App terminated"), (188, .drives, "Volume mounted"),
        ]
        for (minute, kind, label) in colour where minute <= minutes {
            guard !silences.contains(where: { $0.contains(minute) }) else { continue }
            record += 1
            out.append(
                TimelineEvent(
                    record: record, at: start.addingTimeInterval(minute * 60), kind: kind,
                    label: label, detail: "preview", source: "preview", payloadKind: "preview.event"
                ))
        }

        return out.sorted { $0.at == $1.at ? $0.record < $1.record : $0.at < $1.at }
    }
}

/// The canvas over one of those ledgers, at a level chosen by the preview rather
/// than by the span — the whole point is to see the same silence drawn three
/// different ways.
private struct GapShapePreview: View {
    var title: String
    var note: String
    var minutes: Double
    var silences: [Range<Double>]
    var level: ZoomLevel = .clusters
    /// Minutes into the ledger where the window starts, for the edge case.
    var windowStartMinute: Double = 0
    var windowMinutes: Double = 240

    var body: some View {
        let events = GapShapes.events(minutes: minutes, silences: silences)
        let gaps = CoverageAnalysis.gaps(in: events, threshold: GapShapes.threshold)
        let history = GapShapes.start...GapShapes.start.addingTimeInterval(minutes * 60)
        let window = TimelineWindow(
            history: history,
            centredOn: GapShapes.start.addingTimeInterval((windowStartMinute + windowMinutes / 2) * 60),
            span: windowMinutes * 60
        )

        return VStack(alignment: .leading, spacing: Metrics.space2) {
            Text(title)
                .font(Typography.sectionKicker)
                .foregroundStyle(Palette.textTertiary)
            Text(note)
                .font(Typography.caption)
                .foregroundStyle(Palette.textQuiet)

            TimelineCanvas(
                events: events.filter { window.contains($0.at) },
                window: window,
                gaps: CoverageAnalysis.gaps(gaps, overlapping: window),
                trustBoundary: nil,
                level: level,
                selected: nil,
                onSelect: { _ in },
                onZoomTo: { _ in }
            )
        }
        .padding(Metrics.space5)
        .frame(width: 900)
        .background(Palette.canvas)
    }
}

/// The easy case, and the one the fixture always had: an absence wide enough to
/// name itself.
#Preview("Gap — one long silence") {
    GapShapePreview(
        title: "One long gap · Clusters · 4 h",
        note: "70 minutes of silence. Whole buckets, so the hatching runs edge to edge on the grid.",
        minutes: 300,
        silences: [95..<165]
    )
    .preferredColorScheme(.dark)
}

/// The case that produced five blocks with seams between them. Coalescing turns
/// near-adjacent silences into one absence; the live records between them still
/// interrupt it wherever a bar is actually drawn.
#Preview("Gap — several short silences together") {
    GapShapePreview(
        title: "Several short gaps · Clusters · 4 h",
        note: "Four silences of 5–8 minutes, 2–4 minutes apart. Merged where the grid cannot draw the division.",
        minutes: 300,
        silences: [100..<108, 111..<116, 119..<125, 128..<133]
    )
    .preferredColorScheme(.dark)
}

/// A gap that begins before the window does. It covers the visible span from the
/// left edge, which is the case worth getting right — the user is looking at the
/// part of an absence that is on screen.
#Preview("Gap — at the window edge") {
    GapShapePreview(
        title: "Gap at the window edge · Clusters · 4 h",
        note: "The silence starts 40 minutes before the window opens and ends inside it.",
        minutes: 400,
        silences: [80..<170],
        windowStartMinute: 120
    )
    .preferredColorScheme(.dark)
}

/// Narrower than one bucket, so there is no whole bucket to hatch. It becomes a
/// tick: still visible, no longer claiming a span the grid cannot draw.
#Preview("Gap — narrower than one bucket") {
    GapShapePreview(
        title: "Sub-bucket gap · Clusters · 4 h",
        note: "Four minutes of silence on a ten-minute grid. A tick, never nothing.",
        minutes: 300,
        silences: [124..<128]
    )
    .preferredColorScheme(.dark)
}

/// The same four minutes at the Events level, where there is a real timestamp to
/// draw on and no grid to snap to.
#Preview("Gap — the same four minutes, continuous") {
    GapShapePreview(
        title: "Sub-bucket gap · Events · 30 min",
        note: "No grid here, so the gap keeps its real edges and the bracketing records sit on them.",
        minutes: 300,
        silences: [124..<128],
        level: .events,
        windowStartMinute: 112,
        windowMinutes: 30
    )
    .preferredColorScheme(.dark)
}


/// Density draws the same quantised marks on a coarser grid — the level changes
/// what the timeline is made of, never whether an absence is drawn.
#Preview("Gap — density") {
    GapShapePreview(
        title: "One long gap · Density · 15 h",
        note: "Half-hour buckets. The same 70 minutes, still whole buckets, still aligned.",
        minutes: 900,
        silences: [400..<470],
        level: .density,
        windowMinutes: 900
    )
    .preferredColorScheme(.dark)
}
