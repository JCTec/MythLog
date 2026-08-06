import SwiftUI

extension MainPage {
    /// What the Timeline menu can do to the page that is on screen.
    ///
    /// # Why a menu carries these and not just `onKeyPress`
    ///
    /// `onKeyPress` only fires when the view or a descendant has focus, so a
    /// keyboard command that lives there alone is one the user has to *find*
    /// first — and "click the timeline before the arrow keys work" is not a
    /// keyboard path, it is a mouse path with extra steps. A menu key
    /// equivalent works whatever has focus, is discoverable by reading the menu
    /// bar, and is reachable by VoiceOver. That is what makes "a gesture may
    /// never be the only way" true rather than merely claimed.
    ///
    /// # Why it goes through `focusedSceneValue`
    ///
    /// The menu is built in `MythLogApp`, which must not know what a
    /// `MainPage.Model` is, and the model belongs to a page that may not even be
    /// on screen — the app opens on a chooser. A focused scene value is the
    /// bridge SwiftUI provides for exactly this: the page publishes what it can
    /// do while it is the active scene's content, and the menu items disable
    /// themselves when nothing publishes.
    struct Commands {
        var panEarlier: () -> Void
        var panLater: () -> Void
        var jumpToStart: () -> Void
        var jumpToNow: () -> Void
        var selectPrevious: () -> Void
        var selectNext: () -> Void
        var canPanEarlier: Bool
        var canPanLater: Bool
    }
}

/// The published value. Optional, and `nil` in two situations that matter:
/// there is no timeline on screen, and a text field is being edited.
///
/// The second is not a detail. ⌘← and ⌘→ are "beginning of line" and "end of
/// line" in a text field, and ⌥← and ⌥→ move by word; a menu takes its key
/// equivalent *before* the field editor ever sees the key. Publishing nothing
/// while the search field has focus disables the menu items, and the search
/// field keeps the arrow keys a Mac user expects it to have.
struct TimelineCommandsKey: FocusedValueKey {
    typealias Value = MainPage.Commands
}

extension FocusedValues {
    var timelineCommands: MainPage.Commands? {
        get { self[TimelineCommandsKey.self] }
        set { self[TimelineCommandsKey.self] = newValue }
    }
}
