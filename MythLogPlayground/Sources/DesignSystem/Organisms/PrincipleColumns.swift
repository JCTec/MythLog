import SwiftUI

/// What it records, beside what it never records.
///
/// # Why the second column is the important one
///
/// Any monitoring app can list what it watches. Almost none will commit, in
/// writing, to what it refuses to watch — and for an app that runs
/// unsupervised on somebody's Mac, that refusal is the entire basis for
/// installing it. A list of capabilities reassures nobody; a list of
/// capabilities *declined* is a promise that can be checked against the
/// binary's entitlements.
///
/// The closing line does the work: **"Excluded by principle, not merely
/// unimplemented."** Without it a reader assumes the second column is a roadmap.
struct PrincipleColumns: View {
    var records: [String]
    var neverRecords: [String]
    var closingLine: String

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space4) {
            HStack(alignment: .top, spacing: Metrics.space6) {
                column(
                    title: "What it records",
                    items: records,
                    symbol: "checkmark",
                    tint: Palette.accent
                )
                column(
                    title: "What it never records",
                    items: neverRecords,
                    symbol: "xmark",
                    tint: Palette.textTertiary
                )
            }

            Text(closingLine)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func column(title: String, items: [String], symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Metrics.space3) {
            Text(title.uppercased())
                .font(Typography.sectionKicker)
                .foregroundStyle(Palette.textTertiary)

            VStack(alignment: .leading, spacing: Metrics.space2) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.space2) {
                        Image(systemName: symbol)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 12)
                        Text(item)
                            .font(Typography.body)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title): \(items.joined(separator: ", "))")
    }
}

extension PrincipleColumns {
    /// The App Store edition's promise, as the reference design states it.
    ///
    /// Held here rather than in a page so the same wording cannot drift between
    /// first run, an about panel, and a settings screen. If this list ever
    /// disagrees with the app's entitlements, the list is the bug.
    static var appStoreEdition: PrincipleColumns {
        PrincipleColumns(
            records: [
                "Screen lock and unlock",
                "Sleep, wake, lid and displays",
                "Apps launching and quitting",
                "Folders you choose to watch",
                "Drives mounted and removed",
                "Its own recorder health",
            ],
            neverRecords: [
                "Keystrokes",
                "Screen contents",
                "Microphone or camera",
                "Messages or browsing",
            ],
            closingLine: "Excluded by principle, not merely unimplemented. Everything stays on this Mac — "
                + "no account, no cloud, no analytics."
        )
    }
}
