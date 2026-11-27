import Foundation

/// What closing the sound editor's window asks when the sound has edits that are not saved (sound editor plan, Task 9), asked as
/// the rule editor's close is: a sheet with the choice that saves first, Don't Save, and Cancel.
///
/// What saves is Save as New, which is the default of the window and never takes a sound's place, so closing never
/// replaces a sound unasked. When that cannot be done now, because a check that stops a save stands or the name typed
/// is refused, the question has no button that saves, and Cancel is first, so that Return keeps the work.
public enum SoundCloseQuestion {
    /// What closing the window, quitting, or opening another sound does first.
    public enum Step: Equatable, Sendable {
        /// Nothing stands in the way: the edits are saved or there are none.
        case proceed
        /// Edits that are not saved: ask what to do with them.
        case ask
        /// A save is under way: nothing is asked and nothing is done. The save goes on to give the sound its name
        /// and to change the rule being edited, so a question that says the edits are lost would be untrue of it,
        /// and closing would not stop it. Closing is possible once it has finished.
        case wait
    }

    /// What is done first. A save that is under way comes before the edits: while it runs the edits are not marked
    /// as saved, and are saved by it, so they are not the question.
    public static func step(hasUnsavedEdits: Bool, isSaving: Bool) -> Step {
        if isSaving { return .wait }
        return hasUnsavedEdits ? .ask : .proceed
    }

    public enum Choice: Equatable, Sendable {
        case saveAsNew, dontSave, cancel
    }

    /// The buttons in the order they are added, which is the order they are drawn in.
    public static func choices(canSaveAsNew: Bool) -> [Choice] {
        canSaveAsNew ? [.saveAsNew, .dontSave, .cancel] : [.cancel, .dontSave]
    }

    public static func title(of choice: Choice) -> String {
        switch choice {
        case .saveAsNew: return SoundEditorText.saveAsNew
        case .dontSave: return EditorText.dontSave
        case .cancel: return EditorText.cancel
        }
    }

    public static func titles(canSaveAsNew: Bool) -> [String] {
        choices(canSaveAsNew: canSaveAsNew).map(title(of:))
    }

    /// The choice of the button at `index`, counted from the first, or nil for a place with none.
    public static func choice(atButton index: Int, canSaveAsNew: Bool) -> Choice? {
        let all = choices(canSaveAsNew: canSaveAsNew)
        return all.indices.contains(index) ? all[index] : nil
    }

    /// Whether the choice loses the edits, which its button is drawn as destructive for.
    public static func discards(_ choice: Choice) -> Bool { choice == .dontSave }
}
