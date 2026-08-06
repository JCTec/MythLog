import SwiftUI

@main
struct MythLogApp: App {
    /// The composition root. It builds nothing and decides nothing beyond which
    /// window to show — ``RootPage/Model`` owns finding and opening a ledger,
    /// because that is a decision with rules attached and rules belong somewhere
    /// testable.
    ///
    /// This used to read `MYTHLOG_LEDGER` and `MYTHLOG_HMAC_KEY_HEX` here and
    /// hand the result to `MainPage`. Those still work, and still open
    /// immediately — automation and the tamper tests in
    /// `HUMAN_CHECKLIST-ENGINE.md` need to launch straight into a named file —
    /// but they are no longer the only way in. See ``LedgerDiscovery``.
    var body: some Scene {
        Window("MythLog", id: "main") {
            RootPage(model: RootPage.Model(samples: MockTimelineSource.samples))
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1420, height: 900)
        .commands { TimelineCommands() }

        // ⌘, and the app menu, which is where a Mac user looks for a setting.
        // The anchor choice needs to be *found* to be reframed — a threat
        // explanation nobody reaches is the same as no explanation.
        Settings {
            AnchorSettingsPage()
                .preferredColorScheme(.dark)
                .frame(minWidth: 640, minHeight: 620)
        }
    }
}

/// The Timeline menu.
///
/// Here, in the composition root, because a menu is a property of the *app* and
/// because `Commands` is a scene modifier — but it decides nothing: every item
/// forwards to whatever ``MainPage`` published, and every item disables itself
/// when nothing did. See ``MainPage/Commands``.
///
/// Panning by keyboard is in the menu rather than only in `onKeyPress` so that
/// it works without the timeline having been clicked first, and so a user can
/// *find* it. Plain ← and → are deliberately not here: as menu key equivalents
/// they would take the arrow keys away from every text field in the app.
struct TimelineCommands: Commands {
    @FocusedValue(\.timelineCommands) private var timeline

    var body: some SwiftUI.Commands {
        CommandMenu("Timeline") {
            Button("Pan Earlier") { timeline?.panEarlier() }
                .keyboardShortcut(.leftArrow, modifiers: [.option, .shift])
                .disabled(!(timeline?.canPanEarlier ?? false))
            Button("Pan Later") { timeline?.panLater() }
                .keyboardShortcut(.rightArrow, modifiers: [.option, .shift])
                .disabled(!(timeline?.canPanLater ?? false))

            Divider()

            Button("Go to Beginning of History") { timeline?.jumpToStart() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!(timeline?.canPanEarlier ?? false))
            Button("Go to Now") { timeline?.jumpToNow() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!(timeline?.canPanLater ?? false))

            Divider()

            // The selection, not the window. Matches the shortcuts the shipping
            // app documents in `docs/ACCESSIBILITY.md`.
            Button("Select Previous Event") { timeline?.selectPrevious() }
                .keyboardShortcut(.leftArrow, modifiers: .option)
                .disabled(timeline == nil)
            Button("Select Next Event") { timeline?.selectNext() }
                .keyboardShortcut(.rightArrow, modifiers: .option)
                .disabled(timeline == nil)
        }
    }
}
