import SwiftUI

/// One anchor destination, described by what it protects you from.
///
/// # Why the layout leads with a person, not a path
///
/// The old presentation of this setting was a text field containing a directory.
/// A text field cannot be answered correctly by someone who has not already had
/// the thought that an anchor is only worth anything if it is somewhere the
/// person they are worried about cannot reach. So the card leads with
/// *"keeps it away from …"*, and the path — which still exists and still
/// matters — is demoted to the footer where a path belongs.
///
/// # Both columns, always
///
/// "Does not protect against" is shown for the selected option too, not hidden
/// behind a disclosure. Someone choosing iCloud Drive because it is the default
/// needs to see, at that moment, that it does nothing against a partner who
/// knows the Apple Account password. Putting that behind a tap means the people
/// who most need it are the least likely to find it.
struct AnchorChoiceCard: View {
    var choice: AnchorChoice
    var isSelected: Bool
    var resolvedLocation: String
    var onSelect: () -> Void
    /// Present only on the choice that needs a folder. `nil` elsewhere, so the
    /// button cannot appear on a card where it would mean nothing.
    var onChooseFolder: (() -> Void)?

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Metrics.space3) {
                heading
                Text(choice.keepsItAwayFrom)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: Metrics.space5) {
                    bullets("Protects against", choice.protects, symbol: "checkmark", tint: Palette.accent)
                    bullets(
                        "Does not protect against", choice.doesNotProtect,
                        symbol: "xmark", tint: Palette.textTertiary)
                }

                if let warning = choice.visibilityWarning {
                    visibility(warning)
                }

                HStack(alignment: .firstTextBaseline, spacing: Metrics.space3) {
                    Text(resolvedLocation)
                        .font(Typography.hash)
                        .foregroundStyle(Palette.textQuiet)
                        .lineLimit(2)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)

                    if let onChooseFolder {
                        Button("Choose folder…", action: onChooseFolder)
                            .buttonStyle(.link)
                            .font(Typography.caption)
                            .fixedSize()
                    }
                }
            }
            .padding(Metrics.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.radiusPanel, style: .continuous)
                    .fill(isSelected ? Palette.accentDim : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusPanel, style: .continuous)
                    .strokeBorder(
                        isSelected ? Palette.accentBorder : Palette.border,
                        lineWidth: isSelected ? 2 : Metrics.hairline
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(choice.title). Keeps it away from: \(choice.keepsItAwayFrom)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var heading: some View {
        HStack(spacing: Metrics.space2) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Palette.accent : Palette.textTertiary)

            Text(choice.title)
                .font(Typography.rowLabel)
                .foregroundStyle(Palette.textPrimary)

            if choice.isDefault {
                Text("Default")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.horizontal, Metrics.space2)
                    .frame(height: 18)
                    .background(Capsule().fill(Palette.surfaceRaised))
            }

            Spacer(minLength: 0)
        }
    }

    private func bullets(_ title: String, _ items: [String], symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Metrics.space2) {
            Text(title.uppercased())
                .font(Typography.sectionKicker)
                .foregroundStyle(Palette.textTertiary)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: Metrics.space2) {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 11)
                    Text(item)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The warning that did not exist before. Hatched, like a coverage gap, so
    /// it reads as "something is missing from the protection you think you have"
    /// rather than as an ordinary note.
    private func visibility(_ warning: String) -> some View {
        HStack(alignment: .top, spacing: Metrics.space2) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.warning)
            Text(warning)
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .padding(Metrics.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                HatchFill(spacing: 7, lineWidth: 1, color: Palette.warning.opacity(0.16))
                RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                    .fill(Palette.warning.opacity(0.08))
                RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                    .strokeBorder(Palette.warning.opacity(0.35), lineWidth: Metrics.hairline)
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Visibility warning. \(warning)")
    }
}
