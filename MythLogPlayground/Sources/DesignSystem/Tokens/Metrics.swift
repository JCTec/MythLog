import SwiftUI

/// Spacing, radii, and the fixed dimensions the dense layout depends on.
enum Metrics {
    // 4pt base scale.
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
    static let space6: CGFloat = 24
    static let space8: CGFloat = 32

    static let radiusPanel: CGFloat = 10
    static let radiusControl: CGFloat = 7
    static let radiusPill: CGFloat = 999

    static let hairline: CGFloat = 1

    // Chrome.
    static let windowPadding: CGFloat = 16
    static let headerHeight: CGFloat = 44
    static let chipHeight: CGFloat = 26
    static let controlHeight: CGFloat = 24

    // Timeline.
    static let timelineHeight: CGFloat = 150
    static let timelineAxisInset: CGFloat = 26
    static let nodeDiameter: CGFloat = 26
    static let clusterBarWidth: CGFloat = 22
    static let clusterBarGap: CGFloat = 6

    /// Below this, a coverage gap is drawn as a tick rather than as a hatched
    /// region — hatching this narrow reads as an artefact, not as an absence.
    /// It is never dropped; see ``CoverageGapLayout/Mark/Form``.
    static let timelineGapMinimumWidth: CGFloat = 6
    /// The tick a short gap becomes. Wide enough to survive a Retina hairline
    /// and to be a target the eye lands on.
    static let timelineGapTickWidth: CGFloat = 3

    /// The position-in-history bar under the axis.
    static let historyBarHeight: CGFloat = 5
    /// A ten-minute window over two years is a thousandth of a point wide. It is
    /// drawn at least this wide, because "where you are" cannot be nowhere.
    static let historyBarMinimumThumb: CGFloat = 8

    // Event list.
    static let rowHeight: CGFloat = 32
    static let rowTimeWidth: CGFloat = 74
    static let rowRecordWidth: CGFloat = 54

    static let inspectorWidth: CGFloat = 340

    // Filtering.

    /// The popover behind a chip's disclosure. Wide enough for a full path
    /// prefix — `~/Projects/mythlog/.build/` is what the whole subject facet
    /// exists for, and eliding it would defeat the purpose.
    static let facetPanelWidth: CGFloat = 380
    /// Tall enough for a dozen values; beyond that the list scrolls and says how
    /// many it did not show.
    static let facetPanelMaxHeight: CGFloat = 460
    static let facetRowHeight: CGFloat = 26

    /// The rule down the left edge of the filtered-state band. Colour is never
    /// the only carrier, and this is the part that survives greyscale.
    static let stateBandRule: CGFloat = 3
}
