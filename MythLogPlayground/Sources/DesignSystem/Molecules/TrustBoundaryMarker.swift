import SwiftUI

/// The line in the event list where trustworthy history ends.
///
/// # Why a place and not a number
///
/// The banner says "records #1 – #3,200 verify". That is precise, checkable, and
/// almost nobody converts it into "so the four rows I am looking at are the bad
/// ones". Scrolling the list and crossing a rule that says *everything above
/// this cannot be trusted* does the conversion for them.
///
/// The list runs newest first, so the untrusted records are **above** the marker
/// and the trustworthy ones below it. The wording says so rather than relying on
/// the reader to work out which way the list runs.
struct TrustBoundaryMarker: View {
    var boundary: TrustBoundary

    var body: some View {
        HStack(spacing: Metrics.space3) {
            rule
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Palette.critical)
                .fixedSize()
            rule
        }
        .padding(.horizontal, Metrics.space4)
        .padding(.vertical, Metrics.space2)
        .background(Palette.critical.opacity(0.06))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Dashed, not solid. A solid rule in this design means a divider between
    /// sections; a dashed one means a break in something that should have been
    /// continuous — the same vocabulary as the coverage-gap hatching.
    private var rule: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 1)
            .overlay(
                Rectangle()
                    .strokeBorder(
                        Palette.critical.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                    .frame(height: 1)
            )
    }

    private var label: String {
        boundary.nothingIsTrusted
            ? "no record above this line verifies"
            : "everything above this line is untrusted · #\(boundary.firstUntrustedOrdinal.formatted()) onwards"
    }

    private var accessibilityLabel: String {
        boundary.nothingIsTrusted
            ? "Trust boundary. No record in this history verifies against the chain."
            : "Trust boundary. Records up to number \(boundary.lastTrustedOrdinal.formatted()) verify. "
                + "Records from number \(boundary.firstUntrustedOrdinal.formatted()) onwards cannot be trusted."
    }
}
