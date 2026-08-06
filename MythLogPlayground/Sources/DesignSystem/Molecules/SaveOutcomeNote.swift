import SwiftUI

/// What the last save did, said without hedging.
///
/// # Three states, never two
///
/// "Saved" and "failed" are not enough. The interesting one is in between:
/// written to disk, permanent, and *not yet in effect* because a recorder is
/// running with the copy it read at startup. Collapsing that into "Saved" makes
/// the app lie by omission — the user changes a setting, watches nothing happen,
/// and concludes it is broken. Collapsing it into a failure is worse, because
/// the file on disk really did change.
struct SaveOutcomeNote: View {
    var result: SettingsSaveResult

    private var tint: Color {
        switch result.kind {
        case .saved: Palette.accent
        case .savedPendingRecorderRestart: Palette.warning
        case .refused: Palette.critical
        }
    }

    private var symbol: String {
        switch result.kind {
        case .saved: "checkmark.circle.fill"
        case .savedPendingRecorderRestart: "clock.badge.checkmark"
        case .refused: "exclamationmark.triangle.fill"
        }
    }

    private var headline: String {
        switch result.kind {
        case .saved: "Saved\(timeSuffix)"
        case .savedPendingRecorderRestart: "Saved\(timeSuffix) — not in effect yet"
        case .refused: "Not saved"
        }
    }

    /// The time is part of the claim. "Saved" with no time is indistinguishable
    /// from a message left over from ten minutes ago.
    private var timeSuffix: String {
        guard let at = result.at else { return "" }
        return " at \(at.clockText)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.space3) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: Metrics.space1) {
                Text(headline)
                    .font(Typography.rowLabel)
                    .foregroundStyle(Palette.textPrimary)
                Text(result.message)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(Metrics.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                .strokeBorder(tint.opacity(0.4), lineWidth: Metrics.hairline)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline). \(result.message)")
    }
}
