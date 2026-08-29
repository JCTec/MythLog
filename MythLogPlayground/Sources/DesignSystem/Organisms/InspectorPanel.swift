import SwiftUI

/// One event in full, including where it sits in the chain.
///
/// Provenance is not an advanced feature tucked away — it is the reason the app
/// exists, so every selected record shows its link, its HMAC, and what it was
/// verified against.
struct InspectorPanel: View {
    var event: TimelineEvent?
    var integrity: IntegrityState
    /// Where trustworthy history ends. Supplied rather than derived here so the
    /// inspector, the list, and the timeline cannot disagree about it.
    var trustBoundary: TrustBoundary?
    /// Whether the selected record lies outside the visible window — which
    /// panning can arrange, since panning never changes the selection.
    var isOutsideWindow: Bool = false
    /// Moves the window back to the selected record. `nil` where there is no
    /// window to move, as in the previews.
    var onReveal: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space4) {
            if let event {
                if isOutsideWindow { outsideWindowNote }
                // Above the event's own title, deliberately. An untrusted
                // record's verdict is the most consequential thing on this
                // panel and it used to be an 11pt caption at the bottom.
                if !isTrusted(event) {
                    TrustVerdictBadge(
                        isTrusted: false,
                        prominence: .banner,
                        explanation: untrustedExplanation(event)
                    )
                }
                header(event)
                fields(event)
                payload(event)
                provenance(event)
            } else {
                Text("No event selected")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textQuiet)
            }
            Spacer(minLength: 0)
        }
        .padding(Metrics.space4)
        .frame(width: Metrics.inspectorWidth, alignment: .leading)
        .panelSurface()
    }

    /// Says that this record is not on the timeline right now, and offers the
    /// way back.
    ///
    /// The alternative — clearing the selection when it scrolls out of the
    /// window — was rejected: panning to look at the surrounding hours is
    /// exactly when someone wants the record they were reading to stay in front
    /// of them. But an inspector describing a record with nothing on screen to
    /// match it is how a person ends up certain they are looking at the wrong
    /// one, so it says so.
    private var outsideWindowNote: some View {
        HStack(spacing: Metrics.space2) {
            Image(systemName: "eye.slash")
                .font(.system(size: 11))
            Text("Outside the visible window")
                .font(Typography.caption)

            Spacer(minLength: 0)

            if let onReveal {
                Button("Show it", action: onReveal)
                    .buttonStyle(.plain)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel("Move the timeline to the selected record")
            }
        }
        .foregroundStyle(Palette.textTertiary)
        .padding(.horizontal, Metrics.space3)
        .frame(height: Metrics.chipHeight)
        .background(
            RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                .fill(Palette.surfaceSunken)
        )
        .accessibilityElement(children: .combine)
    }

    private func header(_ event: TimelineEvent) -> some View {
        VStack(alignment: .leading, spacing: Metrics.space2) {
            Text("\(event.kind.label.uppercased()) · RECORD #\(event.record.formatted())")
                .font(Typography.sectionKicker)
                .foregroundStyle(event.kind.hue)

            HStack(spacing: Metrics.space2) {
                Image(systemName: event.symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(event.kind.hue)
                Text(event.label)
                    .font(Typography.inspectorTitle)
                    .foregroundStyle(Palette.textPrimary)
            }

            Text(event.detail)
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private func fields(_ event: TimelineEvent) -> some View {
        VStack(spacing: Metrics.space2) {
            field("Time", event.at.clockSecondsText)
            // "Type", not "Kind". The kicker two rows above already says the
            // *kind* — SESSION — and a row labelled the same word holding a
            // different value reads as a contradiction rather than as a
            // refinement. This is the specific event type inside that category,
            // and naming it so is both shorter and true.
            field("Type", event.payloadKind)
            field("Source", event.source)
        }
    }

    private func field(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).font(Typography.body).foregroundStyle(Palette.textTertiary)
            Spacer()
            Text(value).font(Typography.hash).foregroundStyle(Palette.textPrimary)
        }
    }

    private func payload(_ event: TimelineEvent) -> some View {
        VStack(alignment: .leading, spacing: Metrics.space2) {
            Text("PAYLOAD").font(Typography.sectionKicker).foregroundStyle(Palette.textTertiary)
            Text(event.payloadJSON)
                .font(Typography.payload)
                .foregroundStyle(Palette.textSecondary)
                // Wraps; never clips. A path truncated inside its own quotes —
                // `"~/Projects/mythlog/Sources/Ledg…"` — is a payload that
                // cannot be checked against the record it claims to describe,
                // which is the only reason this block exists. Height is cheap in
                // a panel that scrolls; a missing suffix is not.
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(Metrics.space3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.radiusControl)
                        .fill(Palette.surfaceSunken)
                )
        }
    }

    private func provenance(_ event: TimelineEvent) -> some View {
        VStack(alignment: .leading, spacing: Metrics.space2) {
            Text("PROVENANCE").font(Typography.sectionKicker).foregroundStyle(Palette.textTertiary)

            HStack(spacing: Metrics.space2) {
                Image(systemName: "link").font(.system(size: 11)).foregroundStyle(Palette.accent)
                Text("#\(event.record) · chained to #\(event.previousRecord)")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                TrustVerdictBadge(isTrusted: isTrusted(event), prominence: .inline, explanation: nil)
            }

            Text("hmac \(event.hmacShort)")
                .font(Typography.hash)
                .foregroundStyle(Palette.textQuiet)

            Text(anchorLine)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    /// Trust is positional: after a break, later records are untrusted even
    /// though each individually "looks" fine.
    ///
    /// The boundary comes from the verification result rather than a constant.
    /// It used to be `event.record <= 3200`, which was fine while the data was a
    /// fixture and would have been a lie about somebody's history.
    private func isTrusted(_ event: TimelineEvent) -> Bool {
        trustBoundary?.trusts(ordinal: event.record) ?? true
    }

    /// Says why this record is untrusted, in the terms that make it make sense:
    /// not "this record is wrong" — it may be untouched — but "the chain broke
    /// before it, so nothing after the break can be relied on".
    private func untrustedExplanation(_ event: TimelineEvent) -> String {
        guard let trustBoundary else { return "" }
        if trustBoundary.nothingIsTrusted {
            return "No record in this ledger verifies against the chain."
        }
        return "The chain breaks at #\(trustBoundary.firstUntrustedOrdinal.formatted()). "
            + "This record sits after the break, so it cannot be relied on — even though its own hash is "
            + "consistent with the record before it. Anyone able to alter #\(trustBoundary.firstUntrustedOrdinal.formatted()) "
            + "could recompute every hash after it."
    }

    private var anchorLine: String {
        switch integrity {
        case .anchorOffline: "Not anchored — the anchor location is unavailable"
        case .truncated(_, let anchored): "Anchored at \(anchored.formatted()) records; this Mac holds fewer"
        case .verified: "Verified against the chain"
        case .unverified: "Not verified yet"
        case .failed: "The chain does not verify past the break"
        case .unreadable: "The ledger could not be read"
        }
    }
}
