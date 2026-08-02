enum RecorderInstallCopy {
    static let confirmationTitle = "Install MythLog Recorder?"

    static let confirmationMessage =
        """
        MythLog can keep recording important local events after you close the window by adding a visible macOS background item named MythLog.

        What happens:
        - MythLog records to your local ledger in your user account.
        - macOS may ask you to approve MythLog in Background Items.
        - You can stop or uninstall the recorder later from the Recorder menu.

        No admin password or Keychain access is required.
        """

    static let confirmationButtonTitle = "Install & Start"
}
