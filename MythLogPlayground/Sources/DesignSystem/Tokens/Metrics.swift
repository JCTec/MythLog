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

    // Event list.
    static let rowHeight: CGFloat = 32
    static let rowTimeWidth: CGFloat = 74
    static let rowRecordWidth: CGFloat = 54

    static let inspectorWidth: CGFloat = 340
}
