import SwiftUI

@main
struct MythLogApp: App {
    /// The composition root: the one place that decides where the interface's
    /// data comes from. Wave 4 replaces this with a real ledger loader; until
    /// then it is the fixture, chosen here rather than reached for from inside
    /// the page.
    private let snapshot = MockLedger.snapshot

    var body: some Scene {
        Window("MythLog — \(snapshot.history.upperBound.longDateText)", id: "main") {
            MainPage(snapshot: snapshot)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1420, height: 900)
    }
}
