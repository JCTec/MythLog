import SwiftUI

@main
struct MythLogApp: App {
    var body: some Scene {
        Window("MythLog — \(MockLedger.day.longDateText)", id: "main") {
            MainPage()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1420, height: 900)
    }
}
