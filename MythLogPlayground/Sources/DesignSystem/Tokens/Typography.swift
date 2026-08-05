import SwiftUI

/// Type scale. Sizes are relative so Dynamic Type still moves them; the design
/// is dense, so most of the app lives between 11 and 14pt.
enum Typography {
    static let windowTitle = Font.system(size: 13, weight: .medium)

    static let appName = Font.system(size: 19, weight: .semibold)
    static let editionLabel = Font.system(size: 11, weight: .regular)

    static let sectionKicker = Font.system(size: 10, weight: .semibold).width(.expanded)
    static let inspectorTitle = Font.system(size: 20, weight: .semibold)

    static let chip = Font.system(size: 12, weight: .medium)
    static let chipCount = Font.system(size: 12, weight: .regular)

    static let rowTime = Font.system(size: 12, weight: .regular).monospacedDigit()
    static let rowLabel = Font.system(size: 13, weight: .medium)
    static let rowDetail = Font.system(size: 13, weight: .regular)
    static let rowRecord = Font.system(size: 11, weight: .regular).monospacedDigit()

    static let body = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 11, weight: .regular)
    static let hint = Font.system(size: 11, weight: .regular)

    static let axisLabel = Font.system(size: 10, weight: .regular).monospacedDigit()
    static let clusterCount = Font.system(size: 10, weight: .medium).monospacedDigit()

    static let payload = Font.system(size: 11.5, design: .monospaced)
    static let hash = Font.system(size: 11, design: .monospaced)
}
