import SwiftUI

/// First run, and every run until a ledger is opened.
///
/// # What this page is for
///
/// Two jobs, and the second one is the reason it exists at all.
///
/// The obvious job is choosing a ledger. Before this, the only way to point the
/// app at a real one was to edit a scheme in Xcode and paste a hex key, which
/// meant the answer to "can I look at my own history?" was "install Xcode".
///
/// The job that matters more is stating what the app refuses to do, *before*
/// anyone has trusted it with anything. An app that watches a Mac unsupervised
/// has to earn its place, and the argument for it is not the list of things it
/// records — it is the list of things it declines to. That list is checkable
/// against the binary's entitlements, which is what makes it a promise rather
/// than marketing.
struct WelcomePage: View {
    var candidates: [LedgerCandidate]
    var samples: [SampleLedger]
    var lastOpenedPath: String?
    /// Set when the user pointed at something that turned out not to be a
    /// ledger. Shown here rather than in an alert: the correction and the next
    /// attempt belong on the same screen.
    var problem: String?
    var onOpen: (LedgerCandidate) -> Void
    var onOpenSample: (SampleLedger) -> Void
    var onBrowse: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.space6) {
                masthead
                PrincipleColumns.appStoreEdition
                Divider().overlay(Palette.divider)
                chooser
            }
            .padding(Metrics.space8)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(WindowBackground())
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: Metrics.space3) {
            HStack(spacing: Metrics.space3) {
                MarkGlyph()
                VStack(alignment: .leading, spacing: 0) {
                    Text("MythLog").font(Typography.appName).foregroundStyle(Palette.textPrimary)
                    Text("First run · App Store edition")
                        .font(Typography.editionLabel)
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            Text("A trustworthy record of what happened while you were away.")
                .font(Typography.inspectorTitle)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                "MythLog watches for meaningful local events and writes each one into an append-only "
                    + "ledger, chained record to record. If the history is ever altered, verification fails "
                    + "and MythLog tells you."
            )
            .font(Typography.body)
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: Metrics.space3) {
            Text("Open a ledger".uppercased())
                .font(Typography.sectionKicker)
                .foregroundStyle(Palette.textTertiary)

            if !candidates.isEmpty {
                Text(
                    "A ledger was found on this Mac. It is not opened until you say so — this app is also "
                        + "used for screenshots, and your own history should never appear without being asked for."
                )
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(
                    "No ledger was found where an install would put one. Open one by hand, or explore the "
                        + "sample day below."
                )
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let problem {
                HStack(alignment: .top, spacing: Metrics.space2) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.warning)
                    Text(problem)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Metrics.space3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                        .fill(Palette.warning.opacity(0.10))
                )
            }

            LedgerChooser(
                candidates: candidates,
                samples: samples,
                lastOpenedPath: lastOpenedPath,
                onOpen: onOpen,
                onOpenSample: onOpenSample,
                onBrowse: onBrowse
            )
        }
    }
}
