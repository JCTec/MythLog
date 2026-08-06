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
