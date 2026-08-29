import Foundation

/// How a coverage gap is *drawn*, which is not the same as what it *is*.
///
/// A ``CoverageGap`` is a claim about the ledger: nothing was recorded between
/// these two records, and here are their ordinals so you can check. This decides
/// what that claim looks like on a timeline whose resolution is coarser than the
/// claim — and it does so without touching the claim itself. The values are
/// carried through untouched, because the banner cites their real record numbers
/// and a merged pair has two pairs of real ordinals, not one invented one.
///
/// # A bucket is wholly in a gap or wholly out of one
///
/// At Density and Clusters the timeline is made of buckets, and half a bar
/// cannot mean anything. So a bucket is hatched only when it lies entirely
/// inside a gap — and, separately and non-negotiably, only when no bars are
/// drawn in it. **A bucket with a non-zero count is never inside a gap**, since
/// a coverage gap means nothing was recorded and a bucket with events is a
/// bucket where something was.
///
/// That rule alone repairs the contradiction the endpoints create. A gap runs
/// from the last record before the silence to the first record after it, so its
/// two edge buckets always contain a record; neither is wholly inside the gap,
/// so neither is hatched.
///
/// # At Events level there is no grid to snap to
///
/// So there is no quantising and no coalescing: a real timestamp is the honest
/// position, and the two records bracketing the gap are drawn on its edges where
/// they belong.
enum CoverageGapLayout {

    /// One drawn thing: a hatched region, or a tick where a region would be a
    /// lie about resolution.
    struct Mark: Identifiable, Equatable, Sendable {

        /// # Why a short gap changes shape instead of vanishing
        ///
        /// At a wide zoom a four-minute gap is two or three pixels of hatching:
        /// noise, not information, and easy to read as a rendering artefact. The
        /// tempting fix is a minimum width, which lies about duration, or a
        /// minimum *size* below which a gap is dropped — which hides exactly the
        /// brief interruption somebody is hunting for. A gap may never be
        /// dropped for being small.
        ///
        /// So it changes representation rather than visibility. A hatched region
        /// is a claim about a *span*: "no coverage from here to here". Below one
        /// bucket the grid cannot support a span claim — the span is finer than
        /// anything else drawn on the axis — but the data still supports a
        /// *point* claim: "coverage was interrupted here". The tick makes
        /// exactly that claim, at a fixed width, at the gap's real position.
        ///
        /// The list banner is unaffected either way: it always says the
        /// duration in words, which is the reading that does not depend on how
        /// many pixels the window happens to be wide.
        enum Form: Equatable, Sendable {
            /// Hatching over a span that is genuinely without coverage.
            case region
            /// A mark at a point: an interruption too brief for this grid to
            /// describe as a span.
            case tick
        }

        var id: Int
        var form: Form

        /// The left and right edges, as fractions of the window in `0...1`. A
        /// tick has `start == end` and is drawn at a fixed width around it.
        var start: Double
        var end: Double

        /// The whole buckets this region covers, or `nil` at the Events level
        /// where there is no grid. Carried so the invariant can be asserted by
        /// index rather than by comparing floating-point edges.
        var buckets: ClosedRange<Int>?

        /// The gaps this mark stands for, exactly as the analysis produced them.
        /// Never fewer than one, and more than one only after coalescing.
        var gaps: [CoverageGap]

        /// What this says out loud, in the accessibility label and — for a wide
        /// enough region — on the canvas.
        ///
        /// It quotes the gaps' real times, never the quantised edges. The
        /// hatching snaps to the grid because the grid is what the eye can read;
        /// the sentence does not, because a sentence has no resolution limit and
        /// rounding one would be a lie with no upside.
        var label: String {
            guard let first = gaps.first, let last = gaps.last else { return "no coverage" }
            if gaps.count == 1 { return first.label }
            // Day-aware for the same reason a single gap is: a coalesced region
            // is by construction the *widest* thing on the timeline, so it is
            // the mark most likely to span midnight.
            return "no coverage \(RangeLabel.text(from: first.start, to: last.end)), "
                + "\(gaps.count.formatted()) interruptions"
        }

        var isRegion: Bool { form == .region }
    }

    // MARK: - Bucketed levels

    /// Marks quantised to `grid`, for Density and Clusters.
    ///
    /// - Parameter buckets: the buckets as drawn, from
    ///   ``BucketGrid/buckets(over:)``. Their counts are what the invariant is
    ///   enforced against: hatching must not appear where a bar does, and a bar
    ///   is drawn from the *visible* events, so that is the population to check.
    static func marks(for gaps: [CoverageGap], on grid: BucketGrid, buckets: [BucketGrid.Bucket]) -> [Mark] {
        var marks = [Mark]()
        var id = 0

        for group in coalesced(gaps, closerThan: grid.step) {
            guard let extent = extent(of: group) else { continue }
            // Callers hand over gaps already scoped to the window, but a mark
            // for a gap that is not in it would be drawn pinned to an edge —
            // an absence claimed for a span the user is not looking at.
            guard extent.end > grid.window.start, extent.start < grid.window.end else { continue }

            let runs = hatchableRuns(within: extent, on: grid, buckets: buckets)

            guard !runs.isEmpty else {
                // Nothing whole to hatch — a gap shorter than a bucket, or one
                // straddling a boundary. It is still there, so it is still
                // drawn. See `Mark.Form`.
                let centre = extent.start.addingTimeInterval(extent.end.timeIntervalSince(extent.start) / 2)
                let at = min(max(grid.window.fraction(of: centre), 0), 1)
                marks.append(Mark(id: id, form: .tick, start: at, end: at, buckets: nil, gaps: group))
                id += 1
                continue
            }

            for run in runs {
                marks.append(
                    Mark(
                        id: id,
                        form: .region,
                        start: grid.slot(run.lowerBound).lowerBound,
                        end: grid.slot(run.upperBound).upperBound,
                        buckets: run,
                        gaps: group
                    ))
                id += 1
            }
        }
        return marks
    }

    /// The maximal runs of consecutive buckets that lie entirely inside
    /// `extent` and carry no events.
    ///
    /// Two conditions, and the second one wins. A bucket with a non-zero count
    /// interrupts a run even when the gap arithmetic says it is inside — which
    /// can happen after coalescing, since the live stretch between two merged
    /// gaps is real however short it is. A seam with a bar in it is the truth;
    /// hatching over the bar would not be.
    private static func hatchableRuns(
        within extent: (start: Date, end: Date),
        on grid: BucketGrid,
        buckets: [BucketGrid.Bucket]
    ) -> [ClosedRange<Int>] {
        var runs = [ClosedRange<Int>]()
        var run: (first: Int, last: Int)?

        for index in 0..<grid.count {
            let isHatchable =
                grid.start(of: index) >= extent.start
                && grid.end(of: index) <= extent.end
                && (index < buckets.count ? buckets[index].count == 0 : true)

            if isHatchable {
                run = run.map { ($0.first, index) } ?? (index, index)
            } else if let finished = run {
                runs.append(finished.first...finished.last)
                run = nil
            }
        }
        if let finished = run { runs.append(finished.first...finished.last) }
        return runs
    }

    // MARK: - Events level

    /// Continuous marks, for the Events level.
    ///
    /// - Parameter minimumWidth: as a fraction of the window. Below it a region
    ///   becomes a tick, for the reason on ``Mark/Form``. Nothing is dropped.
    static func marks(
        for gaps: [CoverageGap],
        in window: TimelineWindow,
        minimumWidth: Double
    ) -> [Mark] {
        gaps.enumerated().compactMap { index, gap in
            let left = window.fraction(of: gap.start)
            let right = window.fraction(of: gap.end)
            guard right > 0, left < 1 else { return nil }

            let start = min(max(left, 0), 1)
            let end = min(max(right, 0), 1)
            guard end - start >= minimumWidth else {
                let at = (start + end) / 2
                return Mark(id: index, form: .tick, start: at, end: at, buckets: nil, gaps: [gap])
            }
            return Mark(id: index, form: .region, start: start, end: end, buckets: nil, gaps: [gap])
        }
    }

    // MARK: - Coalescing

    /// Groups gaps separated by less than one bucket.
    ///
    /// # Why merge at all
    ///
    /// Several near-adjacent gaps each drew their own rectangle, so one absence
    /// arrived as five blocks with seams between them and inconsistent widths —
    /// which reads as noise rather than as an absence. A division narrower than
    /// one bucket is also a claim the grid cannot make: there is no way to draw
    /// "the recorder came back for ninety seconds" on a ten-minute grid without
    /// implying a bucket's worth of coverage that did not exist.
    ///
    /// # And why it is only a grouping
    ///
    /// The gaps come back whole, in a group. Nothing is rewritten: merging is a
    /// presentation decision and ``CoverageGap`` is evidence, cited by ordinal
    /// in the banner. A merged region that also swallowed the record numbers
    /// would be an uncheckable claim, which is the one thing this app must not
    /// produce.
    ///
    /// The live stretch between two merged gaps is still respected when the
    /// region is quantised — see ``hatchableRuns(within:on:buckets:)`` — so
    /// merging can never hatch over a bar.
    static func coalesced(_ gaps: [CoverageGap], closerThan separation: TimeInterval) -> [[CoverageGap]] {
        let ordered = gaps.sorted { $0.start < $1.start }
        var groups = [[CoverageGap]]()

        for gap in ordered {
            guard let previous = groups.last?.last else {
                groups.append([gap])
                continue
            }
            if gap.start.timeIntervalSince(previous.end) < separation {
                groups[groups.count - 1].append(gap)
            } else {
                groups.append([gap])
            }
        }
        return groups
    }

    private static func extent(of group: [CoverageGap]) -> (start: Date, end: Date)? {
        guard let start = group.map(\.start).min(), let end = group.map(\.end).max() else { return nil }
        return (start, end)
    }
}
