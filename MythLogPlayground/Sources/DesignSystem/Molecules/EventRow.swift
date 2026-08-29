import SwiftUI

/// One line of history: time, category glyph, what happened, and its ledger
/// ordinal. The record number is always present — provenance is not a detail
/// view, it is part of every row.
struct EventRow: View {
    var event: TimelineEvent
    var isSelected: Bool
    /// False for records after a verification break. Trust is positional: each
    /// of these still hashes correctly against its own predecessor, which is
    /// exactly why they cannot be judged one at a time. See ``TrustBoundary``.
    var isTrusted: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.space3) {
                Text(event.at.clockSecondsText)
                    .font(Typography.rowTime)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: Metrics.rowTimeWidth, alignment: .leading)

                Image(systemName: event.symbol)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(event.kind.hue)
                    .frame(width: 16)

                Text(event.label)
                    .font(Typography.rowLabel)
                    .foregroundStyle(Palette.textPrimary)

                Text("— \(event.detail)")
                    .font(Typography.rowDetail)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: Metrics.space3)

                if !isTrusted {
                    Image(systemName: "xmark.seal.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.critical)
                        .accessibilityHidden(true)
                }

                Text("#\(event.record)")
                    .font(Typography.rowRecord)
                    .foregroundStyle(isTrusted ? Palette.textQuiet : Palette.critical)
                    .frame(width: Metrics.rowRecordWidth, alignment: .trailing)
            }
            .padding(.horizontal, Metrics.space4)
            .frame(height: Metrics.rowHeight)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(event.at.clockSecondsText), \(event.label), \(event.detail), record \(event.record)"
                + (isTrusted ? "" : ", untrusted")
        )
        .accessibilityHint("Open in inspector")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// Selection still wins visually — it is the thing the user just did — but
    /// an untrusted row keeps a wash underneath it so the state survives being
    /// selected.
    @ViewBuilder
    private var rowBackground: some View {
        ZStack {
            if !isTrusted { Palette.critical.opacity(0.07) }
            if isSelected { Palette.selection }
        }
    }
}
