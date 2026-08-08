import SwiftUI

/// A togglable category filter carrying its count for the current window, and a
/// disclosure onto everything below the category.
///
/// # The two numbers
///
/// The count is window-scoped and recomputes on every zoom change, so it is a
/// live projection rather than a static total. That was unambiguous while a chip
/// was the only filter. It stops being unambiguous the moment anything else is
/// active: "Files 364" could mean all the file events in the window or the ones
/// surviving the sub-filter, and those are very different sentences.
///
/// So the rule is stated rather than guessed at:
///
/// - **With nothing but chips active** the chip shows one number, the events of
///   that category in the window. Unticking the chip cannot change it, so there
///   is nothing to disambiguate.
/// - **With any sub-filter active** — a type, a source, a subject, a severity
///   floor, or a search — it shows **passing / total**. The first is what you can
///   see, the second is what is there.
///
/// The denominator is always the same number: everything of that category in the
/// window, before any filter. That makes it a stable thing to compare against
/// while the numerator moves under your hands, which is the property that makes
/// two numbers legible at all.
struct FilterChip: View {
    var kind: EventKind
    /// Events of this category in the window, before any filter.
    var count: Int
    /// Events of this category that survive every filter.
    var passing: Int
    /// Whether any filter beyond the chips is active — see the note above.
    var showsBothCounts: Bool
    var isOn: Bool
    /// Whether some of this category's events are hidden by something other
    /// than the chip itself.
    ///
    /// Derived from the two counts rather than from the filter's shape, which is
    /// what makes it exact: attributing a source or a subject back to a category
    /// would mean guessing, and a marker that lights on every chip whenever any
    /// sub-filter exists tells the user nothing about *which* category is
    /// affected.
    var isPartlyHidden: Bool
    var isDetailOpen: Bool
    var action: () -> Void
    var onDisclosure: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: Metrics.space2) {
                    StatusDot(color: kind.hue, isMuted: !isOn)
                    Text(kind.label)
                        .font(Typography.chip)
                        .foregroundStyle(isOn ? Palette.textPrimary : Palette.textTertiary)
                    counts
                }
                .padding(.horizontal, Metrics.space3)
                .frame(height: Metrics.chipHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(kind.label) filter")
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)

            Rectangle()
                .fill(isOn ? Palette.borderStrong : Palette.border)
                .frame(width: Metrics.hairline, height: Metrics.chipHeight - Metrics.space2)

            Button(action: onDisclosure) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: isDetailOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(isPartlyHidden ? Palette.filtered : Palette.textTertiary)
                    // A category with something filtered underneath it must say
                    // so on the chip: the popover is shut most of the time, and
                    // a constraint you cannot see is a constraint you forget.
                    if isPartlyHidden {
                        Circle()
                            .fill(Palette.filtered)
                            .frame(width: 4, height: 4)
                            .offset(x: 4, y: -3)
                    }
                }
                .padding(.horizontal, Metrics.space2)
                .frame(height: Metrics.chipHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(kind.label) details")
            .accessibilityHint(
                isPartlyHidden
                    ? "Some \(kind.label.lowercased()) events are hidden. Opens the values in this window."
                    : "Opens the event types, sources, and subjects in this window.")
        }
        .background(
            Capsule(style: .continuous)
                .fill(isOn ? Palette.surfaceRaised : Palette.surfaceSunken)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    isPartlyHidden ? Palette.filteredEdge : (isOn ? Palette.borderStrong : Palette.border),
                    lineWidth: Metrics.hairline)
        )
    }

    private var counts: some View {
        HStack(spacing: 1) {
            Text("\(showsBothCounts ? passing : count)")
                .font(Typography.chipCount)
                .foregroundStyle(isOn ? Palette.textSecondary : Palette.textQuiet)
            if showsBothCounts {
                Text("/\(count)")
                    .font(Typography.chipCount)
                    .foregroundStyle(Palette.textQuiet)
            }
        }
        .monospacedDigit()
    }

    private var accessibilityValue: String {
        guard showsBothCounts else {
            return "\(count) events in this window, \(isOn ? "shown" : "hidden")"
        }
        return "\(passing) of \(count) events in this window shown, \(count - passing) hidden by filters"
    }
}

#Preview("Filter chips") {
    VStack(alignment: .leading, spacing: Metrics.space3) {
        HStack(spacing: Metrics.space2) {
            FilterChip(
                kind: .session, count: 65, passing: 65, showsBothCounts: false,
                isOn: true, isPartlyHidden: false, isDetailOpen: false, action: {}, onDisclosure: {})
            FilterChip(
                kind: .files, count: 364, passing: 364, showsBothCounts: false,
                isOn: true, isPartlyHidden: false, isDetailOpen: false, action: {}, onDisclosure: {})
            FilterChip(
                kind: .health, count: 0, passing: 0, showsBothCounts: false,
                isOn: false, isPartlyHidden: false, isDetailOpen: false, action: {}, onDisclosure: {})
        }
        HStack(spacing: Metrics.space2) {
            FilterChip(
                kind: .session, count: 65, passing: 2, showsBothCounts: true,
                isOn: true, isPartlyHidden: true, isDetailOpen: false, action: {}, onDisclosure: {})
            FilterChip(
                kind: .files, count: 364, passing: 52, showsBothCounts: true,
                isOn: true, isPartlyHidden: true, isDetailOpen: true, action: {}, onDisclosure: {})
            FilterChip(
                kind: .apps, count: 41, passing: 0, showsBothCounts: true,
                isOn: false, isPartlyHidden: false, isDetailOpen: false, action: {}, onDisclosure: {})
        }
    }
    .padding()
    .background(Palette.canvas)
}
