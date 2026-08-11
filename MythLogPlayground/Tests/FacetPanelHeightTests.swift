import AppKit
import Foundation
import SwiftUI
import Testing

@testable import MythLog

/// The sequence the app actually performs: the popover opens while the facet
/// derivation is still running, so the panel is presented with no values, and
/// they arrive a moment later.
///
/// This is not a contrivance to make a test fail. It is the only sequence that
/// happens — ``MainPage/Model/openDetail(for:)`` sets `categoryDetail` to `[]`
/// and fills it from a task, so a populated panel is never the one that gets
/// presented.
private struct DeferredValuesHost: View {
    var values: [FacetValues]
    /// How long the derivation "takes".
    var delay: Duration = .milliseconds(250)

    @State private var isPresented = false
    @State private var arrived: [FacetValues] = []

    var body: some View {
        Color.clear
            .frame(width: 60, height: 24)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                FilterFacetPanel(
                    kind: .session,
                    facetValues: arrived,
                    filter: EventFilter(),
                    onSet: { _, _, _ in },
                    onClear: { _ in }
                )
            }
            .onAppear {
                isPresented = true
                Task {
                    try? await Task.sleep(for: delay)
                    arrived = values
                }
            }
    }
}

/// How tall ``FilterFacetPanel`` ends up when a popover presents it.
///
/// # Why this measures a popover and not a view
///
/// The panel shipped collapsed to a sliver, and every obvious way of checking it
/// said it was fine. Hand it a populated `facetValues` and it sizes correctly
/// with no help at all — so previews were right, screenshots were right, and
/// `fittingSize` was right. The defect lives entirely in the *order* things
/// happen: an `NSPopover` fixes its content size when it is presented, the panel
/// is always presented before its values exist, and a SwiftUI view whose ideal
/// height grows afterwards does not move it.
///
/// So the thing under test is the presented popover's window, after the values
/// land. At the broken revision these assertions return 100 pt for every
/// category on the machine this was written on; with the fix, 177, 357 and 546.
@Suite("How tall the facet panel ends up")
@MainActor
struct FacetPanelHeightTests {

    /// A category with `count` values under one facet.
    private func facetValues(_ count: Int, omitted: Int = 0) -> [FacetValues] {
        [
            FacetValues(
                facet: .type,
                kind: .session,
                values: (0..<count).map {
                    FacetValue(value: "session.event\($0)", count: count - $0)
                },
                omitted: omitted
            )
        ]
    }

    private func panel(_ values: [FacetValues]) -> FilterFacetPanel {
        FilterFacetPanel(
            kind: .session,
            facetValues: values,
            filter: EventFilter(),
            onSet: { _, _, _ in },
            onClear: { _ in }
        )
    }

    private var visiblePopovers: [NSWindow] {
        NSApp.windows.filter { "\(type(of: $0))".contains("Popover") && $0.isVisible }
    }

    /// Presents `values` the way the app does — after the popover is already
    /// open — and answers with the popover's height before and after they land.
    ///
    /// The host window sits far off any screen, so the popover it opens is never
    /// in front of whoever is at this Mac. Its own size is what is measured, and
    /// that does not depend on where it is.
    private func popoverHeights(
        forValuesArrivingLate values: [FacetValues]
    ) async throws -> (whileEmpty: CGFloat, afterArrival: CGFloat) {
        let existing = Set(visiblePopovers.map(ObjectIdentifier.init))

        let hosting = NSHostingView(rootView: DeferredValuesHost(values: values))
        hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -6000, y: -6000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        /// Only the popover this call opened — a previous case's may still be
        /// closing, and a stale window would make growth look like a pass.
        func mine() -> NSWindow? {
            visiblePopovers.first { !existing.contains(ObjectIdentifier($0)) }
        }

        // Presented, derivation still running.
        try await Task.sleep(for: .milliseconds(150))
        let whileEmpty = mine()?.frame.height ?? 0

        // Values landed, and the popover has had time to follow them.
        try await Task.sleep(for: .milliseconds(700))
        let afterArrival = mine()?.frame.height ?? 0

        return (whileEmpty, afterArrival)
    }

    /// The defect itself. Both categories used to sit at the height of the
    /// "Reading this window…" line for as long as the popover was open.
    @Test("the popover follows the values that arrive after it opened")
    func popoverGrowsWhenTheValuesArrive() async throws {
        let small = try await popoverHeights(forValuesArrivingLate: facetValues(2))
        let large = try await popoverHeights(forValuesArrivingLate: facetValues(60, omitted: 12))

        #expect(small.whileEmpty > 0, "no popover was presented at all")

        #expect(
            small.afterArrival > small.whileEmpty,
            "two values arrived and the popover stayed \(small.whileEmpty) pt — it never resized")
        #expect(
            large.afterArrival > large.whileEmpty,
            "sixty values arrived and the popover stayed \(large.whileEmpty) pt — it never resized")

        // The failure that started this: every category the same collapsed size.
        #expect(
            large.afterArrival > small.afterArrival,
            "sixty values (\(large.afterArrival) pt) is not taller than two (\(small.afterArrival) pt)")

        #expect(
            small.afterArrival > 2 * Metrics.facetRowHeight,
            "\(small.afterArrival) pt is not enough for two rows")
        #expect(
            large.afterArrival >= Metrics.facetPanelMaxHeight,
            "\(large.afterArrival) pt is under the cap — sixty values cannot have fitted")
    }

    /// The end state the panel is supposed to offer, measured as a size rather
    /// than through a presentation: as tall as its content, up to the cap.
    ///
    /// This one passes at the broken revision too — it is here to say what the
    /// panel is *for*, not to catch the bug above.
    @Test("the height it asks for tracks its content and stops at the cap")
    func idealHeightTracksContent() async throws {
        let short = try await idealHeight(of: panel(facetValues(2)))
        let medium = try await idealHeight(of: panel(facetValues(8)))
        let long = try await idealHeight(of: panel(facetValues(60)))

        #expect(short < medium, "2 values (\(short) pt) is not shorter than 8 (\(medium) pt)")
        #expect(medium < long, "8 values (\(medium) pt) is not shorter than 60 (\(long) pt)")
        #expect(short < Metrics.facetPanelMaxHeight)
        // Six more rows grew the panel by about six rows. Loose at both ends:
        // section chrome and text wrapping are in there too.
        #expect(medium - short >= 4 * Metrics.facetRowHeight)

        // The cap, plus the header, the gap under it, and the panel's padding.
        let chrome = 2 * Metrics.space4 + Metrics.space3 + 60
        #expect(
            long <= Metrics.facetPanelMaxHeight + chrome,
            "\(long) pt is past the cap plus its chrome — the ceiling is not holding")
    }

    /// The branch the fix must not have touched. An unfinished derivation is a
    /// different state from a category with nothing in it, and it has no scroll
    /// region at all.
    @Test("the unfinished-derivation panel is unaffected")
    func readingThisWindow() async throws {
        let height = try await idealHeight(of: panel([]))

        #expect(height > 0)
        #expect(
            height < Metrics.facetPanelMaxHeight,
            "\(height) pt for one line of text means the empty branch grew a scroll region")
    }

    /// The size the panel offers whoever is about to present it.
    ///
    /// The window and the wait are not ceremony: the height comes from a
    /// geometry reading that writes `@State`, so it lands on a second layout
    /// pass, and a measurement taken before that pass reads the unsettled value.
    private func idealHeight(of view: some View) async throws -> CGFloat {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: Metrics.facetPanelWidth, height: 900),
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -6000, y: -6000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        // Suspends rather than spins: the geometry reading writes `@State` on
        // the main actor, and a synchronous wait would hold it.
        try await Task.sleep(for: .milliseconds(400))
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }
}
