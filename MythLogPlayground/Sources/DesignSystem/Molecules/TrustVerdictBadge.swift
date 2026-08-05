import SwiftUI

/// "Verified" or "Untrusted", for one record.
///
/// # Why this is loud
///
/// The verdict used to be an eleven-point caption at the bottom of the
/// inspector, the same size as the HMAC beside it. That is the right weight for
/// a detail and the wrong weight for the single most consequential sentence the
/// app says about a record — and it is *always* "Verified" until the one time it
/// is not, which is exactly the pattern that trains people not to look.
///
/// So an untrusted record gets a full-width strip at the top of the inspector,
/// above the event's own title. It is the first thing read, not the last.
///
/// # Greyscale
///
/// Colour is the least of the three signals here: the strip changes its symbol,
/// its border weight, and — for untrusted — gains a hatched backing. Photocopy
/// it and the difference survives.
struct TrustVerdictBadge: View {
    enum Prominence {
        /// Full-width strip. Used where the verdict is the headline.
        case banner
        /// Inline pill. Used where the verdict annotates something else.
        case inline
    }

    var isTrusted: Bool
    var prominence: Prominence
    /// The record this verdict is about, so the strip can say *why* rather than
    /// just what.
    var explanation: String?

    private var tint: Color { isTrusted ? Palette.accent : Palette.critical }
    private var symbol: String { isTrusted ? "checkmark.seal.fill" : "xmark.seal.fill" }
    private var text: String { isTrusted ? "Verified" : "Untrusted" }

    var body: some View {
        switch prominence {
        case .inline: inlineBadge
        case .banner: bannerStrip
        }
    }

    private var inlineBadge: some View {
        HStack(spacing: Metrics.space1) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            Text(text).font(Typography.caption)
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This record is \(text.lowercased())")
    }

    private var bannerStrip: some View {
        HStack(alignment: .top, spacing: Metrics.space3) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: Metrics.space1) {
                Text(text.uppercased())
                    .font(Typography.sectionKicker)
                    .foregroundStyle(tint)

                if let explanation {
                    Text(explanation)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Metrics.space3)
        .background(
            ZStack {
                // Hatching only on the untrusted side: a texture difference
                // survives greyscale, and a photocopy, and colour blindness.
                if !isTrusted {
                    HatchFill(spacing: 6, lineWidth: 1, color: Palette.critical.opacity(0.22))
                }
                RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                    .fill(tint.opacity(0.10))
                RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                    .strokeBorder(tint.opacity(0.45), lineWidth: isTrusted ? Metrics.hairline : 2)
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This record is \(text.lowercased()). \(explanation ?? "")")
    }
}
