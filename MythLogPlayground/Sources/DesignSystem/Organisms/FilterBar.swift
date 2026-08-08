import SwiftUI

/// Observable categories, what is inside each of them, and the ones this edition
/// cannot see.
///
/// The locked chips are the honesty mechanism: an edition that simply omitted
/// them would let a user read "no failed unlocks" as "there were none", when the
/// truth is "I cannot see them".
///
/// # A chip is still a chip
///
/// Clicking one toggles its category, exactly as before, because that is the
/// gesture people already have and there was nothing wrong with it. The new
/// dimension arrives as a *disclosure* on the same chip — a second, smaller hit
/// target — so nothing is taken away from someone who never opens it and the
/// depth is one click from where they already are rather than behind a settings
/// sheet.
///
/// # Presets come before the machinery
///
/// The row reads presets-first, left of the chips, because the question most
/// people arrive with — "when was this Mac unlocked?" — should not require
/// learning what a facet is. The preset writes an ordinary filter and the bar
/// shows what it wrote, so the machinery is what you learn *from* using it
/// rather than what you must learn *before*.
struct FilterBar: View {
    var filter: EventFilter
    /// Events of each category in the window, before any filter.
    var counts: [EventKind: Int]
    /// Events of each category that survive every filter.
    var passingCounts: [EventKind: Int]
    var severityCounts: [AlarmSeverity: Int]
    var lockedSources: [LockedSource]

    var openCategory: EventKind?
    var categoryDetail: [FacetValues]

    var presets: [FilterPreset]
    var savedFilters: [SavedFilter]
    var activeSavedFilter: SavedFilter?

    var onToggle: (EventKind) -> Void
    var onOpenDetail: (EventKind) -> Void
    var onCloseDetail: () -> Void
    var onSetValue: (EventFacet, String, FacetSelection.ValueState) -> Void
    var onClearFacet: (EventFacet) -> Void
    var onSetMinimumSeverity: (AlarmSeverity?) -> Void
    var onApplyPreset: (FilterPreset) -> Void
    var onApplySaved: (SavedFilter) -> Void
    var onDeleteSaved: (SavedFilter) -> Void
    var onSaveCurrent: (String) -> Void
    var onExplainEditions: () -> Void

    @State private var isNaming = false
    @State private var draftName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space2) {
            HStack(spacing: Metrics.space2) {
                presetMenu
                savedMenu

                Rectangle()
                    .fill(Palette.divider)
                    .frame(width: 1, height: 18)
                    .padding(.horizontal, Metrics.space1)

                ForEach(EventKind.allCases) { chip($0) }

                if !lockedSources.isEmpty {
                    Rectangle()
                        .fill(Palette.divider)
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, Metrics.space1)

                    ForEach(lockedSources) { FilterChip.Locked(source: $0) }
                }

                Spacer(minLength: Metrics.space2)

                SeverityFilterMenu(
                    counts: severityCounts,
                    minimum: filter.minimumSeverity,
                    onChange: onSetMinimumSeverity)
            }

            explanation
        }
    }

    private func chip(_ kind: EventKind) -> some View {
        FilterChip(
            kind: kind,
            count: counts[kind] ?? 0,
            passing: passingCounts[kind] ?? 0,
            showsBothCounts: filter.hasSubFilters,
            isOn: filter.includes(kind),
            isPartlyHidden: isPartlyHidden(kind),
            isDetailOpen: openCategory == kind,
            action: { onToggle(kind) },
            onDisclosure: { onOpenDetail(kind) }
        )
        .popover(
            isPresented: Binding(
                get: { openCategory == kind },
                set: { if !$0 { onCloseDetail() } }),
            arrowEdge: .bottom
        ) {
            FilterFacetPanel(
                kind: kind,
                facetValues: categoryDetail,
                filter: filter,
                onSet: onSetValue,
                onClear: onClearFacet)
        }
    }

    /// Whether some of this category's events are hidden by something other
    /// than the chip.
    ///
    /// Answered from the counts, not from the filter's shape. Attributing a
    /// source or a subject back to a category would mean guessing — the values
    /// only belong to a category by virtue of the events carrying them — and the
    /// version that guessed lit the marker on all six chips the moment any
    /// sub-filter existed, which said nothing about which category was affected.
    ///
    /// The counts already know: a category whose passing count is below its
    /// window count is a category with something hidden inside it, exactly.
    private func isPartlyHidden(_ kind: EventKind) -> Bool {
        guard filter.includes(kind) else { return false }
        return (passingCounts[kind] ?? 0) < (counts[kind] ?? 0)
    }

    // MARK: - Presets

    private var presetMenu: some View {
        Menu {
            ForEach(presets) { preset in
                Button {
                    onApplyPreset(preset)
                } label: {
                    // Both lines: the title is what it is called and the question
                    // is why anybody would press it. A menu of titles alone
                    // teaches nothing.
                    Text("\(preset.title) — \(preset.question)")
                }
            }
        } label: {
            HStack(spacing: Metrics.space2) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                Text("Ask")
                    .font(Typography.chip)
            }
            .foregroundStyle(Palette.textPrimary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, Metrics.space2)
        .frame(height: Metrics.chipHeight)
        .background(Capsule(style: .continuous).fill(Palette.accentDim))
        .overlay(
            Capsule(style: .continuous).strokeBorder(Palette.accentBorder, lineWidth: Metrics.hairline))
        .accessibilityLabel("Common questions")
        .accessibilityHint("Applies a filter that answers one question in a single step.")
    }

    // MARK: - Saved filters

    private var savedMenu: some View {
        Menu {
            if savedFilters.isEmpty {
                Text("No saved filters yet")
            } else {
                ForEach(savedFilters) { saved in
                    Button(saved.name) { onApplySaved(saved) }
                }
                Divider()
                Menu("Delete") {
                    ForEach(savedFilters) { saved in
                        Button(saved.name) { onDeleteSaved(saved) }
                    }
                }
            }

            Divider()

            Button("Save this filter…") {
                draftName = ""
                isNaming = true
            }
            .disabled(!filter.isFiltering)
        } label: {
            HStack(spacing: Metrics.space2) {
                Image(systemName: "bookmark")
                    .font(.system(size: 10, weight: .medium))
                Text(activeSavedFilter?.name ?? "Saved")
                    .font(Typography.chip)
                    .lineLimit(1)
            }
            .foregroundStyle(activeSavedFilter == nil ? Palette.textSecondary : Palette.filtered)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, Metrics.space2)
        .frame(height: Metrics.chipHeight)
        .background(Capsule(style: .continuous).fill(Palette.surfaceRaised))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    activeSavedFilter == nil ? Palette.border : Palette.filteredEdge,
                    lineWidth: Metrics.hairline))
        .accessibilityLabel("Saved filters")
        .popover(isPresented: $isNaming, arrowEdge: .bottom) {
            namingSheet
        }
    }

    private var namingSheet: some View {
        VStack(alignment: .leading, spacing: Metrics.space3) {
            Text("Name this filter")
                .font(Typography.rowLabel)
                .foregroundStyle(Palette.textPrimary)

            Text(filter.summarySentence)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Ignore builds", text: $draftName)
                .textFieldStyle(.plain)
                .font(Typography.chip)
                .foregroundStyle(Palette.textPrimary)
                .pillSurface(fill: Palette.surfaceSunken, stroke: Palette.border)
                .onSubmit(commitName)

            HStack {
                Spacer()
                Button("Cancel") { isNaming = false }
                    .buttonStyle(.plain)
                    .font(Typography.chip)
                    .foregroundStyle(Palette.textSecondary)
                Button("Save", action: commitName)
                    .buttonStyle(.plain)
                    .font(Typography.chip)
                    .foregroundStyle(Palette.textPrimary)
                    .pillSurface(fill: Palette.accentDim, stroke: Palette.accentBorder)
                    .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Metrics.space4)
        .frame(width: 300)
        .background(Palette.surface)
    }

    private func commitName() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        onSaveCurrent(name)
        isNaming = false
    }

    // MARK: -

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
