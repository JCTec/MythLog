import SwiftUI

/// What is wrong with the ledger, said above the history it is wrong about.
///
/// # This is the screen the product exists for
///
/// Everything else MythLog does — the timeline, the filters, the inspector — is
/// in service of one moment: the app telling somebody that their record has been
/// altered, and being believed. Until this banner existed, `IntegrityState`
/// carried full copy for four states and rendered none of it: a failing ledger
/// looked like a working one with a differently-coloured chip in the corner.
///
/// # Why it is not dismissible
///
/// There is no close button, deliberately. A dismissible warning is a warning
/// that gets dismissed, and the state it describes does not go away when it is
/// hidden — the only way to clear this banner is to fix or acknowledge what
/// caused it. It is also why `.unverified` does not show one (see
/// ``IntegrityState/needsBanner``): a banner that appears on every launch and
/// then vanishes teaches exactly the reflex this one cannot afford.
///
/// # Why it sits above the list rather than over it
///
/// A modal would stop the person reading the history at the moment they most
/// need to read it — "which records changed?" is answered by the list, not by
/// the dialog covering it.
struct IntegrityBanner: View {
    var state: IntegrityState
    var onPrimary: () -> Void
    var onSecondary: () -> Void

    private var tint: Color { Palette.tint(for: state.severity) }

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.space3) {
            Image(systemName: state.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Metrics.space2) {
                Text(state.bannerTitle)
                    .font(Typography.rowLabel)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(state.bannerBody)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                actions
            }

            Spacer(minLength: 0)
        }
        .padding(Metrics.space4)
        .background(background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(state.accessibilitySummary)
    }

    private var actions: some View {
        HStack(spacing: Metrics.space2) {
            Button(action: onPrimary) {
                Text(state.bannerAction)
                    .font(Typography.chip)
                    .foregroundStyle(tint)
                    .pillSurface(fill: tint.opacity(0.16), stroke: tint.opacity(0.45))
            }
            .buttonStyle(.plain)

            if let secondary = state.bannerSecondaryAction {
                Button(action: onSecondary) {
                    Text(secondary)
                        .font(Typography.chip)
                        .foregroundStyle(Palette.textSecondary)
                        .pillSurface(fill: Palette.surfaceRaised, stroke: Palette.border)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, Metrics.space1)
    }

    /// The severity carries in three ways at once, so none of them has to carry
    /// alone: a tinted wash, a border whose weight steps up with severity, and —
    /// for `.alarm` only — a hatched backing. In greyscale the hatching is what
    /// separates "your history was altered" from "anchoring is paused".
    private var background: some View {
        ZStack {
            if state.severity == .alarm {
                HatchFill(spacing: 7, lineWidth: 1, color: tint.opacity(0.18))
            }
            RoundedRectangle(cornerRadius: Metrics.radiusPanel, style: .continuous)
                .fill(Palette.wash(for: state.severity))
            RoundedRectangle(cornerRadius: Metrics.radiusPanel, style: .continuous)
                .strokeBorder(
                    Palette.edge(for: state.severity),
                    lineWidth: state.severity == .alarm ? 2 : Metrics.hairline
                )
        }
    }
}
