import SwiftUI

// Previews are a composition root, exactly like `MythLogApp`: they decide where
// the interface's data comes from. That is why they live here rather than beside
// the view — `DesignSystem/` may reference view models and nothing else, and a
// `#Preview` that names a fixture would breach that just as surely as the page
// doing it.
//
// The fixture is the right choice for design work: it contains a known
// four-hour coverage gap and a known 312-event burst, which is what makes
// layout decisions reproducible. No real ledger reliably contains either.

#Preview("Main page — fixture") {
    MainPage(snapshot: MockLedger.snapshot)
        .preferredColorScheme(.dark)
}
