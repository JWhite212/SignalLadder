// Sources/SignalLadder/SoundEditorWindowController.swift
import AlertAudio
import AppKit
import SwiftUI
import NotificationCore

/// Holds the sound editor's window, as the rule editor's is held, and every flow that asks the user something: saving
/// over a sound that rules use, a save that failed, and closing, or opening another sound, with edits that are not saved
/// (sound editor plan, Tasks 7 and 9).
///
/// Those flows live here and not in SwiftUI for the reason the rule editor's do: `windowShouldClose` must answer at
/// once, but the question it needs answered is asked in a sheet. So it answers "not yet", asks, and closes only after the
/// answer has been carried out. What is asked, which buttons there are and what each comes to is the core's
/// (`SoundSaveControls`, `SoundCloseQuestion`, `SoundEditorText`).
///
/// The window is kept when closed (an NSWindow made in code is otherwise freed while still referenced), and the app is
/// activated before the window is ordered front, or a menu-bar app opens it behind whatever the user was looking at.
/// It is brought back from the Dock if it was minimised, so that showing it never leaves it there.
///
/// The way in is a button beside Add Sound… in the rule editor (`AlertEditorView`), which hands this the name of the
/// sound the alert plays, the alert's own gain, and what to do with the name a Save as New gave the sound.
///
/// This file may hold no word of its own (the strict list in `ViewLiteralsTests`): the title is `WindowTitles`'.
@MainActor
final class SoundEditorWindowController: NSObject, NSWindowDelegate {
    private let player: AlertPlayer
    private let library: SoundLibrary
    private let rulesNaming: (String) -> Int
    private let soundsChanged: (String) -> Void
    private var window: NSWindow?
    private var model: SoundEditorModel?
    /// Set while carrying out a close the user has already answered, so `windowShouldClose` does not ask again.
    private var closingAnswered = false

    /// - Parameters:
    ///   - player: the one that plays an alert, which only ever plays a preview for the editor and is refused one
    ///     while an alert sounds.
    ///   - library: where the sounds are, to open one by the name a rule gives it.
    ///   - rulesNaming: how many rules play a sound, which Save asks before replacing one that any does.
    ///   - soundsChanged: told the name of a sound that has been saved, so that the player lets go of what it had
    ///     decoded and the rule editor lists the sounds again.
    init(player: AlertPlayer, library: SoundLibrary, rulesNaming: @escaping (String) -> Int,
         soundsChanged: @escaping (String) -> Void) {
        self.player = player
        self.library = library
        self.rulesNaming = rulesNaming
        self.soundsChanged = soundsChanged
    }

    /// Open includes minimised.
    var isOpen: Bool { window.map { $0.isVisible || $0.isMiniaturized } ?? false }

    /// Opens the sound a rule plays in the editor.
    ///
    /// - Parameters:
    ///   - name: the sound's name as the rule has it.
    ///   - ruleGainDB: the rule's gain, which a preview is played with as an alert is.
    ///   - saved: told the name a Save as New gave the sound, so that the rule can name it.
    func show(sound name: String, ruleGainDB: Double, saved: @escaping (String) -> Void) {
        // A window that is showing a sound with edits that are not saved is not given another without asking.
        if isOpen, model?.hasUnsavedEdits == true {
            bringForward()
            askAboutUnsavedEdits { [weak self] proceed in
                if proceed { self?.replace(with: name, ruleGainDB: ruleGainDB, saved: saved) }
            }
        } else {
            replace(with: name, ruleGainDB: ruleGainDB, saved: saved)
        }
    }

    private func replace(with name: String, ruleGainDB: Double, saved: @escaping (String) -> Void) {
        model?.windowClosed()
        let model = SoundEditorModel(soundName: name, ruleGainDB: ruleGainDB, library: library, player: player,
                                     onSaved: saved, onSoundsChanged: soundsChanged)
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
        let actions = SoundEditorActions(saveAsNew: { [weak self] in self?.saveAsNew() },
                                         save: { [weak self] in self?.save() })
        window?.contentView = NSHostingView(rootView: SoundEditorView(model: model, actions: actions))
        Task { await model.open() }
        bringForward()
    }

    private func bringForward() {
        NSApp.activate(ignoringOtherApps: true)
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Saving

    /// Save as New, under the name typed. `done` is told whether the sound was saved.
    func saveAsNew(then done: @escaping (Bool) -> Void = { _ in }) {
        guard let model, let request = model.saveControls.saveAsNewRequest else { return done(false) }
        run(request, then: done)
    }

    /// Save, over the sound being edited: at once when no rule plays it, and after asking when any does.
    func save() {
        guard let model, let step = model.saveControls.saveStep(ruleCount: rulesNaming(model.displayName)) else { return }
        switch step {
        case .save(let request):
            run(request)
        case .ask(let request, let confirmation):
            ask(confirmation) { [weak self] in self?.run(request) }
        }
    }

    private func run(_ request: SoundSaveRequest, then done: @escaping (Bool) -> Void = { _ in }) {
        guard let model else { return done(false) }
        Task { [weak self] in
            switch await model.save(request) {
            case .saved:
                done(true)
            case .refused(let failure):
                self?.showFailure(failure)
                done(false)
            case .notBegun:
                done(false)
            }
        }
    }

    private func showFailure(_ failure: SoundSaveFailure) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = SoundEditorText.saveFailedTitle
        alert.informativeText = SoundEditorText.saveFailedDetail(SoundEditorText.saveFailure(failure))
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    /// Asks in a sheet, with Cancel first so Return keeps the sound, and carries out `proceed` on the one button that
    /// goes ahead, drawn as destructive.
    private func ask(_ confirmation: EditorText.Confirmation, then proceed: @escaping () -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = confirmation.title
        alert.informativeText = confirmation.detail
        for (index, title) in confirmation.buttons.enumerated() {
            alert.addButton(withTitle: title).hasDestructiveAction = confirmation.proceeds(atButton: index)
        }
        alert.beginSheetModal(for: window) { response in
            let first = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            if confirmation.proceeds(atButton: response.rawValue - first) { proceed() }
        }
    }

    // MARK: - Closing

    /// Edits that are not saved, which closing the window or quitting the app would lose.
    var hasUnsavedEdits: Bool { model?.hasUnsavedEdits == true }

    /// Whether a save is under way, which quitting waits for as closing the window does, whether or not there are edits
    /// that are not saved: a Save as New of a sound with none still gives it its name.
    var isSaving: Bool { model?.isSaving == true }

    /// Asks what to do with edits that are not saved when the app is to quit, which never asks the window: the same question
    /// closing the window asks, over the window, brought forward first as the rule editor's is. `then` is told whether it is
    /// now safe to quit.
    func confirmDiscardingEdits(then: @escaping (Bool) -> Void) {
        switch SoundCloseQuestion.step(hasUnsavedEdits: hasUnsavedEdits, isSaving: model?.isSaving == true) {
        case .proceed:
            then(true)
        case .ask:
            bringForward()
            askAboutUnsavedEdits(then: then)
        case .wait:
            then(false)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !closingAnswered else { return true }
        switch SoundCloseQuestion.step(hasUnsavedEdits: model?.hasUnsavedEdits == true, isSaving: model?.isSaving == true) {
        case .proceed:
            return true
        case .ask:
            askAboutUnsavedEdits { [weak self] proceed in if proceed { self?.close(sender) } }
            return false
        case .wait:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        model?.windowClosed()
    }

    /// Asks what to do with edits that are not saved: Save as New, Don't Save or Cancel, or only the last two when a
    /// save cannot be made now. `then` is told whether it is now safe to let the edits go: saved, or deliberately
    /// discarded.
    private func askAboutUnsavedEdits(then: @escaping (Bool) -> Void) {
        guard let model, model.hasUnsavedEdits else { return then(true) }
        // Not while a save is under way, which finishes whatever is answered.
        guard !model.isSaving else { return then(false) }
        guard let window else { return then(false) }
        let canSaveAsNew = model.saveControls.canSaveAsNew
        let alert = NSAlert()
        alert.messageText = SoundEditorText.closeQuestion(model.displayName)
        alert.informativeText = SoundEditorText.closeDetail
        for choice in SoundCloseQuestion.choices(canSaveAsNew: canSaveAsNew) {
            alert.addButton(withTitle: SoundCloseQuestion.title(of: choice)).hasDestructiveAction = SoundCloseQuestion.discards(choice)
        }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return then(false) }
            let first = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            switch SoundCloseQuestion.choice(atButton: response.rawValue - first, canSaveAsNew: canSaveAsNew) {
            case .saveAsNew: self.saveAsNew(then: then)
            case .dontSave: then(true)
            case .cancel, nil: then(false)
            }
        }
    }

    private func close(_ window: NSWindow) {
        closingAnswered = true
        window.close()
        closingAnswered = false
    }
}

/// What the sound editor's view may ask of the window controller.
struct SoundEditorActions {
    /// Save as New, under the name typed.
    let saveAsNew: () -> Void
    /// Save over the sound being edited, which asks first when a rule plays it.
    let save: () -> Void
}
