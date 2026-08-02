import SwiftUI

struct PinnedSummaryTagRow: View {
    let record: TimelineRecord
    let presentation: TimelineEventPresentation

    var body: some View {
        HStack {
            // The tag is drawn in caps for weight, but VoiceOver spells short all-caps words out
            // letter by letter, so it is spoken as an ordinary word instead.
            Tag(record.event.severity.rawValue.uppercased(), color: record.event.severity.timelineTagColor)
                .accessibilityLabel("\(record.event.severity.accessibilityTitle) severity")
            Tag(presentation.title, color: presentation.tintColor)
                .accessibilityLabel("\(presentation.title) category")
            Tag(record.event.source, color: .secondary)
                .accessibilityLabel("Source: \(record.event.source)")
        }
    }
}
