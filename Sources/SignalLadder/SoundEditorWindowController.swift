// Sources/SignalLadder/SoundEditorWindowController.swift
import AlertAudio
import AppKit
import SwiftUI
import NotificationCore

/// Holds the sound editor's window, as the rule editor's is held (sound editor plan, Task 7).
///
/// The window is kept when closed (an NSWindow made in code is otherwise freed while still referenced), and the app is
/// activated before the window is ordered front, or a menu-bar app opens it behind whatever the user was looking at.
/// It is brought back from the Dock if it was minimised, so that showing it never leaves it there.
///
/// Nothing in the app reaches `show(sound:ruleGainDB:saved:)` yet: the way in is a button in the rule editor, which
/// comes with saving (Task 9). It takes what that button will have, the name of the sound the rule plays, the rule's
/// own gain, and what to do with the name a saved sound is given.
///
/// This file may hold no word of its own (the strict list in `ViewLiteralsTests`): the title is `WindowTitles`'.
@MainActor
final class SoundEditorWindowController: NSObject, NSWindowDelegate {
    private let player: AlertPlayer
    private let library: SoundLibrary
    private var window: NSWindow?
    private var model: SoundEditorModel?

    /// - Parameters:
    ///   - player: the one that plays an alert, which only ever plays a preview for the editor and is refused one
    ///     while an alert sounds.
    ///   - library: where the sounds are, to open one by the name a rule gives it.
    init(player: AlertPlayer, library: SoundLibrary) {
        self.player = player
        self.library = library
    }

    /// Open includes minimised.
    var isOpen: Bool { window.map { $0.isVisible || $0.isMiniaturized } ?? false }

    /// Opens the sound a rule plays in the editor.
    ///
    /// - Parameters:
    ///   - name: the sound's name as the rule has it.
    ///   - ruleGainDB: the rule's gain, which a preview is played with as an alert is.
    ///   - saved: told the name a saved sound was given, so that the rule can name it.
    func show(sound name: String, ruleGainDB: Double, saved: @escaping (String) -> Void) {
        // A window that is already showing another sound is given this one. What was edited in it and not saved is lost,
        // which nothing can ask about until there is a way to save it (Task 9).
        model?.windowClosed()
        let model = SoundEditorModel(soundName: name, ruleGainDB: ruleGainDB, library: library, player: player,
                                     onSaved: saved)
        self.model = model

        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 700),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = WindowTitles.soundEditor
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        window?.contentView = NSHostingView(rootView: SoundEditorView(model: model))
        Task { await model.open() }

        NSApp.activate(ignoringOtherApps: true)
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Closing

    func windowWillClose(_ notification: Notification) {
        model?.windowClosed()
    }
}
