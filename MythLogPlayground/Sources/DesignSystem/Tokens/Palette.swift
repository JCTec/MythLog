import SwiftUI

/// Every colour in the app resolves here. Nothing else declares a literal.
///
/// Values are read off the reference design. Tune them in this one file and the
/// whole app follows — that is the only reason a token layer exists.
enum Palette {
    // Surfaces, darkest to lightest.
    static let canvas = Color(hex: 0x0B0F0E)
    static let surface = Color(hex: 0x111716)
    static let surfaceRaised = Color(hex: 0x161D1B)
    static let surfaceSunken = Color(hex: 0x0D1211)

    // Hairlines.
    static let border = Color.white.opacity(0.08)
    static let borderStrong = Color.white.opacity(0.14)
    static let divider = Color.white.opacity(0.06)

    // Text.
    static let textPrimary = Color(hex: 0xE7EDEA)
    static let textSecondary = Color(hex: 0x9BA8A3)
    static let textTertiary = Color(hex: 0x6C7A76)
    static let textQuiet = Color(hex: 0x4E5A57)

    // Accent — "verified", "running", the chain head.
    static let accent = Color(hex: 0x3FD07E)
    static let accentDim = Color(hex: 0x3FD07E).opacity(0.16)
    static let accentBorder = Color(hex: 0x3FD07E).opacity(0.38)

    // Alert states.
    static let warning = Color(hex: 0xE3B341)
    static let critical = Color(hex: 0xE5534B)

    // Selection.
    static let selection = Color(hex: 0x211E33)
    static let selectionBorder = Color(hex: 0x7C5CFF).opacity(0.55)

    /// Ambient glows behind the window. Green top-left, blue bottom-right.
    static let glowGreen = Color(hex: 0x1B3A2A)
    static let glowBlue = Color(hex: 0x16283E)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
