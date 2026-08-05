import SwiftUI

/// A category of recorded event. Adding a case must be all it takes to add a
/// category — no legend, colour list, or row layout may need hand-editing.
enum EventKind: String, CaseIterable, Identifiable, Sendable {
    case session
    case power
    case apps
    case files
    case drives
    case health

    var id: String { rawValue }

    var label: String {
        switch self {
        case .session: "Session"
        case .power: "Power"
        case .apps: "Apps"
        case .files: "Files"
        case .drives: "Drives"
        case .health: "Health"
        }
    }

    var hue: Color {
        switch self {
        case .session: Color(hex: 0x34C759)
        case .power: Color(hex: 0x3B82F6)
        case .apps: Color(hex: 0xA855F7)
        case .files: Color(hex: 0x6366F1)
        case .drives: Color(hex: 0xD1D5DB)
        case .health: Color(hex: 0x9CA3AF)
        }
    }

    var symbol: String {
        switch self {
        case .session: "lock.open"
        case .power: "moon"
        case .apps: "macwindow"
        case .files: "doc"
        case .drives: "externaldrive"
        case .health: "waveform.path.ecg"
        }
    }
}

/// A source this build cannot observe. Shown, never hidden, so its absence is
/// never mistaken for silence.
enum LockedSource: String, CaseIterable, Identifiable, Sendable {
    case failedUnlocks
    case permissionPrompts
    case remoteAccess
    case usbIdentity

    var id: String { rawValue }

    var label: String {
        switch self {
        case .failedUnlocks: "Failed unlocks"
        case .permissionPrompts: "Permission prompts"
        case .remoteAccess: "Remote access"
        case .usbIdentity: "USB identity"
        }
    }
}
