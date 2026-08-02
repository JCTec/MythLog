import MythLogCore
import SwiftUI

struct LedgerStatusBadge: View {
    let continuity: LedgerVerification?

    @ScaledMetric(relativeTo: .caption) private var glyphSize: CGFloat = 9

    var body: some View {
        let status = continuityStatus

        StatusBadge {
            // Was a bare colored dot: blue and red read identically in grayscale. A distinct glyph
            // per state carries the same meaning without hue.
            Image(systemName: status.symbolName)
                .font(.system(size: glyphSize, weight: .bold))
                .foregroundStyle(status.color)
        } content: {
            Text(status.title)
            if let continuity {
                Text("\(continuity.recordCount) records")
                    .foregroundStyle(.secondary)
            }
        }
        .help(status.help)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ledger continuity: \(status.title).")
        .accessibilityValue(Text(continuity.map { "\($0.recordCount) records" } ?? ""))
        .accessibilityHint(status.help)
        .accessibilityIdentifier(A11yIdentifier.toolbarLedgerStatus)
    }

    private var continuityStatus: (title: String, symbolName: String, color: Color, help: String) {
        guard let continuity else {
            return (
                "Loading",
                "ellipsis.circle",
                Color.secondary.opacity(0.8),
                "Loading live ledger. Open Ledger Integrity for HMAC verification."
            )
        }

        if continuity.isValid {
            return (
                "Linked",
                "link.circle.fill",
                Color.blue.opacity(0.85),
                "Live timeline continuity check passed. Open Ledger Integrity for HMAC verification."
            )
        }

        return (
            "Chain issue",
            "exclamationmark.triangle.fill",
            Color.red.opacity(0.9),
            "Live timeline detected a broken previous-hash link. Open Ledger Integrity for full HMAC verification."
        )
    }
}
