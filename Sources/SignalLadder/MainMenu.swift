// Sources/SignalLadder/MainMenu.swift
import AppKit
import NotificationCore

/// The main menu, which macOS never draws for a menu-bar-only app, and which
/// is needed anyway.
///
/// AppKit delivers ⌘X, ⌘C, ⌘V, ⌘A and ⌘Z to a text field through the main
/// menu's key equivalents: the field itself does not handle them. An accessory
/// app has no main menu unless it makes one, so without this every text field
/// in the rule editor ignored them — a channel name could not be pasted into a
/// condition, and ⌘A inserted nothing and selected nothing. Found in the M3
/// live checks (2026-09-25).
///
/// Deliberately no Quit item. ⌘Q in the editor would end alerting with a
/// keystroke meant for something else; quitting stays in the status menu,
/// where it is chosen on purpose. The application menu holds one item, Settings…
/// on ⌘, (M5 plan, Task 6), which opens the window the status menu's item opens.
enum MainMenu {
    /// - Parameters:
    ///   - settingsTarget: what Settings… is sent to, which opens the window.
    ///   - settingsAction: the action it sends.
    static func make(settingsTarget: AnyObject, settingsAction: Selector) -> NSMenu {
        let main = NSMenu()

        // AppKit treats the first item as the application menu whatever it
        // holds, so one comes first to keep Edit from being taken for it. It
        // holds Settings… and nothing else.
        let app = NSMenuItem()
        let appMenu = NSMenu()
        let settings = NSMenuItem(title: SettingsText.menuTitle, action: settingsAction, keyEquivalent: ",")
        settings.target = settingsTarget
        appMenu.addItem(settings)
        app.submenu = appMenu
        main.addItem(app)

        let editItem = NSMenuItem()
        editItem.submenu = edit()
        main.addItem(editItem)
        return main
    }

    /// The standard Edit items. Each sends its action down the responder
    /// chain with a nil target, so it reaches whichever field has focus and is
    /// disabled when nothing can take it.
    private static func edit() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }
}
