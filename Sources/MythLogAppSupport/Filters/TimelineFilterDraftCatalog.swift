enum TimelineFilterDraftCatalog {
    static let iconPresets = [
        "tag.fill",
        "bolt.fill",
        "externaldrive.fill",
        "network",
        "eye.fill",
        "exclamationmark.triangle.fill",
    ]

    static let colorPresets = [
        TimelineFilterColorPreset(id: "custom", title: "Purple", color: .custom),
        TimelineFilterColorPreset(id: "unlock", title: "Teal", color: .unlock),
        TimelineFilterColorPreset(id: "file", title: "Orange", color: .file),
        TimelineFilterColorPreset(id: "notification", title: "Rose", color: .notification),
        TimelineFilterColorPreset(id: "lock", title: "Indigo", color: .lock),
    ]
}
