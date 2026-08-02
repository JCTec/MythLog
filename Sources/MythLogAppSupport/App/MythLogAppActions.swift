struct MythLogAppActions: Sendable {
    let installAgent: @MainActor @Sendable () -> Void
    let startAgent: @MainActor @Sendable () -> Void
    let exportProofBundle: @MainActor @Sendable () -> Void
    let openNotificationSettings: @MainActor @Sendable () -> Void

    static let disabled = MythLogAppActions(
        installAgent: {},
        startAgent: {},
        exportProofBundle: {},
        openNotificationSettings: {}
    )
}
