/// The rule that decides what order VoiceOver walks the timeline in.
///
/// Event nodes are drawn in severity-driven z-order — a critical event floats above its neighbours,
/// and the selected one floats above everything — which is the wrong order to hear a timeline in.
/// Every node therefore carries an explicit sort priority derived from its chronological position.
/// VoiceOver reads the highest priority first, so the oldest visible event gets the largest number.
///
/// This lives outside the view so the ordering contract can be tested directly. Verifying it through
/// the rendered view would need a UI test the project cannot currently run; see
/// `docs/ACCESSIBILITY.md`.
enum TimelineAccessibilityOrder {
    static func sortPriority(index: Int, count: Int) -> Double {
        Double(count - index)
    }
}
