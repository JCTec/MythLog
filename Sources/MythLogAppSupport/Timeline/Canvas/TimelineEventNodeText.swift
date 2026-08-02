extension TimelineDisplayRecord {
    /// Full-sentence VoiceOver label. Sighted users get title, subtitle, and timestamp from the hover
    /// tooltip, so the spoken label carries the same facts: what happened, the detail line, how severe
    /// it is, and when it happened.
    var eventNodeAccessibilityLabel: String {
        var sentences = ["\(title)."]

        if !subtitle.isEmpty, subtitle != title {
            sentences.append("\(subtitle).")
        }

        sentences.append("\(event.severity.accessibilityTitle) severity.")
        sentences.append("\(presentation.title) event at \(timestamp.inspectorDateString).")
        return sentences.joined(separator: " ")
    }

    /// Only set when the event is in a state the visual design conveys by dimming alone, which
    /// VoiceOver cannot perceive.
    var eventNodeAccessibilityValue: String? {
        guard hiddenBySearch else {
            return nil
        }

        return "Hidden by the current category filters, shown because it matches your search."
    }

    var eventNodeAccessibilityHint: String {
        "Opens this event in the inspector."
    }

    var eventNodeHelpText: String {
        "\(title)\n\(subtitle)\n\(timestamp.inspectorDateString)"
    }
}
