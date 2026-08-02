import MythLogCore
import SwiftUI

struct TimelineStatusRow: View {
    let continuity: LedgerVerification?
    let visibleCount: Int
    let totalCount: Int
    let loadError: String?
    let showLedgerIntegrity: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            // A Button, not a tap gesture: this is the only route to ledger integrity from the main
            // window, and a tap gesture cannot be reached by keyboard or activated by VoiceOver.
            Button(action: showLedgerIntegrity) {
                LedgerStatusBadge(continuity: continuity)
            }
            .buttonStyle(.plain)

            Text("\(visibleCount) / \(totalCount)")
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(visibleCount) of \(totalCount) events shown")

            if let error = loadError {
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .accessibilityLabel("Timeline load error: \(error)")
            }

            Spacer()
        }
        .font(.caption)
    }
}
