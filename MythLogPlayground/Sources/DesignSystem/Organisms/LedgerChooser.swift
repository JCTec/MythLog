import SwiftUI

/// The ledgers this Mac has, offered rather than opened.
///
/// # Offered, never opened for you
///
/// A found ledger appears here as a row with a button. It is not loaded until
/// somebody presses it. See ``LedgerDiscovery`` for why — briefly: this app is
/// run on other people's machines to take screenshots, and a real history
/// appearing unbidden is a failure even when every step that produced it worked.
///
/// The fixture is listed alongside rather than beneath. It is not a fallback for
/// when the real thing is missing; it is the right choice for design work, and
/// the layout should say so.
struct LedgerChooser: View {
    var candidates: [LedgerCandidate]
    /// Ready-made histories, supplied by the composition root. See
    /// ``SampleLedger`` for why this layer cannot build them itself.
    var samples: [SampleLedger]
    /// The path last opened, so it can be marked. Marked, not auto-opened.
    var lastOpenedPath: String?
    var onOpen: (LedgerCandidate) -> Void
    var onOpenSample: (SampleLedger) -> Void
    var onBrowse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space3) {
            ForEach(candidates) { candidate in
                row(
                    title: candidate.title,
                    detail: candidate.detail,
                    badge: candidate.badge,
                    isRealHistory: true,
                    isLastOpened: candidate.ledgerURL.path == lastOpenedPath,
                    warnsAboutKey: !candidate.canVerify,
                    sizeLabel: candidate.sizeLabel
                ) { onOpen(candidate) }
            }

            ForEach(samples) { sample in
                row(
                    title: sample.title,
                    detail: sample.detail,
                    badge: "Sample",
                    isRealHistory: false,
                    isLastOpened: false,
                    warnsAboutKey: false,
                    sizeLabel: nil
                ) { onOpenSample(sample) }
            }

            Button(action: onBrowse) {
                HStack(spacing: Metrics.space2) {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .medium))
                    Text("Open ledger…")
                        .font(Typography.chip)
                }
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                        .fill(Palette.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                        .strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose any events.jsonl file, including a copy made for testing")
        }
    }

    /// One row, described by what it says rather than by which type produced
    /// it — a real ledger and a sample must look like siblings, because for
    /// design work the sample is the right answer and a row that looked like a
    /// fallback would say otherwise.
    private func row(
        title: String,
        detail: String,
        badge: String,
        isRealHistory: Bool,
        isLastOpened: Bool,
        warnsAboutKey: Bool,
        sizeLabel: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Metrics.space3) {
                Image(systemName: isRealHistory ? "shield.lefthalf.filled" : "sparkles")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isRealHistory ? Palette.accent : Palette.textTertiary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: Metrics.space1) {
                    HStack(spacing: Metrics.space2) {
                        Text(title)
                            .font(Typography.rowLabel)
                            .foregroundStyle(Palette.textPrimary)

                        tag(badge)
                        if isLastOpened { tag("Last opened") }
                        if warnsAboutKey { tag("No key", tint: Palette.warning) }
                    }

                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: Metrics.space3)

                VStack(alignment: .trailing, spacing: Metrics.space1) {
                    Text("Open")
                        .font(Typography.chip)
                        .foregroundStyle(Palette.accent)
                        .pillSurface(fill: Palette.accentDim, stroke: Palette.accentBorder)
                    if let sizeLabel {
                        Text(sizeLabel)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textQuiet)
                    }
                }
            }
            .padding(Metrics.space4)
            .background(
                RoundedRectangle(cornerRadius: Metrics.radiusPanel, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusPanel, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: Metrics.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityHint("Opens this ledger")
        .accessibilityAddTraits(.isButton)
    }

    private func tag(_ text: String, tint: Color = Palette.textTertiary) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, Metrics.space2)
            .frame(height: 18)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.3), lineWidth: Metrics.hairline))
    }
}
