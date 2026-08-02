import AppKit

struct MythLogMenuItemFactory {
    let target: AnyObject

    func command(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        // Every menu command gets a test identifier here rather than at each call site, so no menu
        // can be added without one.
        item.identifier = NSUserInterfaceItemIdentifier(
            A11yIdentifier.menuCommand(selectorName: NSStringFromSelector(action))
        )
        return item
    }

    func shiftCommand(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = command(title: title, action: action, keyEquivalent: keyEquivalent.lowercased())
        item.keyEquivalentModifierMask = [.command, .shift]
        return item
    }
}
