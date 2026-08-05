import SwiftUI

/// Observable categories and, beside them, the ones this edition cannot see.
///
/// The locked chips are the honesty mechanism: an edition that simply omitted
/// them would let a user read "no failed unlocks" as "there were none", when the
/// truth is "I cannot see them".
struct FilterBar: View {
    var counts: [EventKind: Int]
    var enabled: Set<EventKind>
    var lockedSources: [LockedSource]
    var onToggle: (EventKind) -> Void
    var onExplainEditions: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space2) {
            HStack(spacing: Metrics.space2) {
                ForEach(EventKind.allCases) { kind in
                    FilterChip(
                        kind: kind,
                        count: counts[kind] ?? 0,
                        isOn: enabled.contains(kind)
                    ) { onToggle(kind) }
                }

                if !lockedSources.isEmpty {
                    Rectangle()
                        .fill(Palette.divider)
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, Metrics.space2)

                    ForEach(lockedSources) { FilterChip.Locked(source: $0) }
                }

                Spacer(minLength: 0)
            }

            explanation
        }
    }

    private var explanation: some View {
        HStack(spacing: Metrics.space1) {
            Text("Locked sources can't be observed by sandboxed App Store software — they are shown so their absence is never mistaken for silence.")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)

            Button("What each edition can see", action: onExplainEditions)
                .buttonStyle(.plain)
                .font(Typography.caption)
                .foregroundStyle(Palette.accent)
                .underline()
        }
    }
}
