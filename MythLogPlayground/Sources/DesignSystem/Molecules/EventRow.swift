import SwiftUI

/// One line of history: time, category glyph, what happened, and its ledger
/// ordinal. The record number is always present — provenance is not a detail
/// view, it is part of every row.
struct EventRow: View {
    var event: TimelineEvent
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.space3) {
                Text(event.at.clockSecondsText)
                    .font(Typography.rowTime)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: Metrics.rowTimeWidth, alignment: .leading)

                Image(systemName: event.kind.symbol)
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

                Text("#\(event.record)")
                    .font(Typography.rowRecord)
                    .foregroundStyle(Palette.textQuiet)
                    .frame(width: Metrics.rowRecordWidth, alignment: .trailing)
            }
            .padding(.horizontal, Metrics.space4)
            .frame(height: Metrics.rowHeight)
            .background(isSelected ? Palette.selection : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(event.at.clockSecondsText), \(event.label), \(event.detail), record \(event.record)"
        )
        .accessibilityHint("Open in inspector")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
