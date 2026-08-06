import SwiftUI

/// Where the chain head is kept, and who that keeps it away from.
///
/// # The reframing
///
/// This setting used to be a path. A path is unanswerable by someone who has not
/// already worked out that an anchor is only worth something if it lives
/// somewhere the person they are worried about cannot reach — which is most
/// people, most of the time, including the ones who need it most.
///
/// So the page opens with why anchors exist at all, presents the two shipped
/// destinations in terms of what each protects against, and says out loud the
/// thing that has never been said anywhere: a synced folder is visible on the
/// adversary's devices too.
///
/// # What this build does and does not do
///
/// It shows and changes the choice in memory. It does not write `config.json` —
/// the recorder owns that file, and this app reads ledgers rather than
/// reconfiguring installs. The page says so rather than pretending, because a
/// settings screen that silently fails to save is worse than one that admits it.
struct AnchorSettingsPage: View {
    @State private var model: Model

    init(model: Model = Model()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.space5) {
                heading
                enabledToggle

                ForEach(AnchorChoice.all) { choice in
                    AnchorChoiceCard(
                        choice: choice,
                        isSelected: model.isSelected(choice),
                        resolvedLocation: model.resolvedLocation(for: choice),
                        onSelect: { model.select(choice) }
                    )
                    .disabled(!model.isEnabled)
                    .opacity(model.isEnabled ? 1 : 0.45)
                }

                usbSuggestion
                notWritableNote
            }
            .padding(Metrics.space6)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(WindowBackground())
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: Metrics.space3) {
            Text("Anchoring".uppercased())
                .font(Typography.sectionKicker)
                .foregroundStyle(Palette.textTertiary)

            Text("Who are you keeping this away from?")
                .font(Typography.inspectorTitle)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(AnchorChoice.rationale)
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var enabledToggle: some View {
        Toggle(isOn: $model.isEnabled) {
            VStack(alignment: .leading, spacing: Metrics.space1) {
                Text("Keep a copy of the chain head somewhere else")
                    .font(Typography.rowLabel)
                    .foregroundStyle(Palette.textPrimary)
                Text(
                    "With this off, the chain still verifies record to record — but records removed from "
                        + "the end become undetectable, because a shortened chain verifies perfectly."
                )
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .tint(Palette.accent)
    }

    /// Called out on its own because it is the largest real-world gain available
    /// and it already works. A bullet inside a list reads as an example; this is
    /// a recommendation.
    private var usbSuggestion: some View {
        HStack(alignment: .top, spacing: Metrics.space3) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: Metrics.space1) {
                Text("The strongest option needs nothing new")
                    .font(Typography.rowLabel)
                    .foregroundStyle(Palette.textPrimary)
                Text(AnchorChoice.usbKeySuggestion)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Metrics.space4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.radiusPanel, style: .continuous)
                .fill(Palette.accent.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radiusPanel, style: .continuous)
                .strokeBorder(Palette.accentBorder.opacity(0.5), lineWidth: Metrics.hairline)
        )
    }

    private var notWritableNote: some View {
        Text(
            "This build shows the choice and does not write it back. `config.json` belongs to the recorder, "
                + "and this app reads ledgers rather than reconfiguring installs."
        )
        .font(Typography.caption)
        .foregroundStyle(Palette.textQuiet)
        .fixedSize(horizontal: false, vertical: true)
    }
}
