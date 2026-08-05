import SwiftUI

/// One event in full, including where it sits in the chain.
///
/// Provenance is not an advanced feature tucked away — it is the reason the app
/// exists, so every selected record shows its link, its HMAC, and what it was
/// verified against.
struct InspectorPanel: View {
    var event: TimelineEvent?
    var integrity: IntegrityState

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space4) {
            if let event {
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

    private func header(_ event: TimelineEvent) -> some View {
        VStack(alignment: .leading, spacing: Metrics.space2) {
            Text("\(event.kind.label.uppercased()) · RECORD #\(event.record)")
                .font(Typography.sectionKicker)
                .foregroundStyle(event.kind.hue)

            HStack(spacing: Metrics.space2) {
                Image(systemName: event.kind.symbol)
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
            field("Kind", event.payloadKind)
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
                Text(verdict(for: event))
                    .font(Typography.caption)
                    .foregroundStyle(isTrusted(event) ? Palette.accent : Palette.critical)
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
    private func isTrusted(_ event: TimelineEvent) -> Bool {
        guard integrity == .failed else { return true }
        return event.record <= 3200
    }

    private func verdict(for event: TimelineEvent) -> String {
        isTrusted(event) ? "Verified" : "Untrusted"
    }

    private var anchorLine: String {
        integrity == .anchorOffline
            ? "Not anchored — iCloud unavailable since 09:12"
            : "Verified against the 14:00 iCloud anchor"
    }
}
