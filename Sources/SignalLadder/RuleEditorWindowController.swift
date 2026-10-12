// Sources/SignalLadder/RuleEditorWindowController.swift
import AppKit
import SwiftUI
import NotificationCore

/// Holds the rule editor's window, and every flow that asks the user
/// something: saving, a save refused because the file changed, and closing
/// with unsaved changes.
///
/// Those flows live here rather than in SwiftUI because they are AppKit's to
/// run: `windowShouldClose` must answer at once, but the question it needs
/// answered is asked in a sheet. So it answers "not yet", asks, and closes
/// only after the answer has been carried out.
///
/// As for the Inspector: the window is kept when closed (an NSWindow made in
/// code is otherwise freed while still referenced), and the app is activated
/// before the window is ordered front, or a menu-bar app opens it behind
/// whatever the user was looking at — and its text fields never take keys.
@MainActor
final class RuleEditorWindowController: NSObject, NSWindowDelegate {
    let model: RuleEditorModel
    /// Opens rules.json in the user's text editor.
    var openInTextEditor: () -> Void = {}

    private var window: NSWindow?
    /// Set while carrying out a close the user has already answered, so
    /// `windowShouldClose` does not ask again.
    private var closingAnswered = false

    init(model: RuleEditorModel) {
        self.model = model
    }

    /// Open includes minimised: a minimised editor may hold a draft, and
    /// treating it as closed would re-read the file over it.
    var isOpen: Bool { window.map { $0.isVisible || $0.isMiniaturized } ?? false }

    /// Opens the editor, reading the file afresh unless it is already open —
    /// an open window may hold a draft, and reading would discard it. With a
    /// notification, a new rule is made from it.
    func show(makingRuleFrom entry: InspectorEntry? = nil) {
        if !isOpen { model.reloadFromDisk() }
        if let entry { model.makeRule(from: entry) }

        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = WindowTitles.ruleEditor
            window.contentView = NSHostingView(rootView: RuleEditorView(
                model: model,
                actions: RuleEditorActions(save: { [weak self] in self?.save() },
                                           openInTextEditor: { [weak self] in self?.openInTextEditor() })))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Saving

    /// Saves, handling a refusal. `done` is told whether the draft ended up
    /// on disk.
    func save(then done: @escaping (Bool) -> Void = { _ in }) {
        switch model.save() {
        case .saved:
            done(true)
        case .failed(let reason):
            showFailure(reason)
            done(false)
        case .conflict(let change):
            askAboutConflict(change, then: done)
        }
    }

    private func askAboutConflict(_ change: RulesChange, then done: @escaping (Bool) -> Void) {
        guard let window else { return done(false) }
        let alert = NSAlert()
        alert.messageText = EditorText.conflictTitle
        alert.informativeText = EditorText.conflictDetail(change) + "\n\n" + EditorText.conflictKeepNote
        alert.addButton(withTitle: "Reload from Disk")
        alert.addButton(withTitle: "Save Anyway")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                // The draft is discarded, so it did not reach the disk: a
                // close waiting on this stays open, showing what is there now.
                self.model.reloadFromDisk()
                done(false)
            case .alertSecondButtonReturn:
                switch self.model.saveReplacingDisk() {
                case .saved:
                    done(true)
                case .failed(let reason):
                    self.showFailure(reason)
                    done(false)
                case .conflict:
                    done(false)
                }
            default:
                done(false)
            }
        }
    }

    private func showFailure(_ reason: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The rules could not be saved."
        alert.informativeText = "\(reason)\n\nNothing was changed: rules.json is as it was, and your draft is still here."
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    // MARK: - Closing

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.hasUnsavedChanges, !closingAnswered else { return true }
        confirmDiscardingDraft { [weak self] proceed in if proceed { self?.close(sender) } }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        model.forgetSource()
    }

    /// Asks what to do with an unsaved draft: Save, Don't Save or Cancel.
    /// `then` is told whether it is now safe to let the draft go — saved, or
    /// deliberately discarded. Used when the window closes and when the app
    /// quits, which never asks the window.
    func confirmDiscardingDraft(then: @escaping (Bool) -> Void) {
        guard model.hasUnsavedChanges else { return then(true) }
        show()
        guard let window else { return then(false) }
        let alert = NSAlert()
        alert.messageText = EditorText.closeTitle
        alert.informativeText = EditorText.closeDetail
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return then(false) }
            switch response {
            case .alertFirstButtonReturn:
                self.save(then: then)
            case .alertSecondButtonReturn:
                self.model.revert()
                then(true)
            default:
                then(false)
            }
        }
    }

    private func close(_ window: NSWindow) {
        closingAnswered = true
        window.close()
        closingAnswered = false
    }
}

/// What the editor's views may ask of the window controller.
struct RuleEditorActions {
    let save: () -> Void
    let openInTextEditor: () -> Void
}
