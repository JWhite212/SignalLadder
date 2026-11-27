import Foundation

/// What a save is asked to do: the name the sound is to have, and whether a sound of that name is to be taken the place of.
/// The window passes exactly this to the store, and a request is made only by `SoundSaveControls`, so that nothing is
/// replaced that was not asked for.
public struct SoundSaveRequest: Equatable, Sendable {
    public let name: String
    public let replacing: Bool

    public init(name: String, replacing: Bool) {
        self.name = name
        self.replacing = replacing
    }
}

/// What the window does when Save is pressed.
public enum SoundSaveStep: Equatable, Sendable {
    /// Save at once.
    case save(SoundSaveRequest)
    /// Ask first, in these words, and save only if the answer is the button that goes ahead.
    case ask(SoundSaveRequest, EditorText.Confirmation)
}

/// What the sound editor's save controls offer, and what pressing them comes to (sound editor plan, Rulings 9, 11 and 12, and
/// Task 9).
///
/// **Save as New is the default and never takes a sound's place.** It saves under the name typed, which starts as the name
/// `SoundSaveNaming` suggests, and the verdict on what is typed is shown as it is typed. A name that is a sound of the user's
/// own is not saved as new: it says so, and Save is the way to replace the sound being edited. **Save** replaces the sound
/// being edited, only when it is one of the user's own that macOS does not also have a sound of the name of, and asks first
/// when any rule plays it, saying how many. A macOS sound is only ever copied. **Nothing saves** while a check that stops a
/// save stands, while a render is under way (the checks are then of the sound before the last edit), while a save is under
/// way, or before the sound is open.
///
/// The core cannot read the folders, so the names are handed in, and names are compared ignoring case as the library
/// compares them.
public struct SoundSaveControls: Equatable, Sendable {
    /// The sound being edited, as its file spells it: the one Save replaces.
    public let editedName: String
    /// What is typed in the name field.
    public let typedName: String
    public let ownSounds: Set<String>
    public let macOSSounds: Set<String>
    public let isReady: Bool
    public let isCatchingUp: Bool
    public let isSaving: Bool
    /// A check that stops a save stands: nothing to hear, or too long.
    public let isBlocked: Bool

    public init(editedName: String, typedName: String, ownSounds: Set<String>, macOSSounds: Set<String>, isReady: Bool,
                isCatchingUp: Bool, isSaving: Bool, isBlocked: Bool) {
        self.editedName = editedName
        self.typedName = typedName
        self.ownSounds = ownSounds
        self.macOSSounds = macOSSounds
        self.isReady = isReady
        self.isCatchingUp = isCatchingUp
        self.isSaving = isSaving
        self.isBlocked = isBlocked
    }

    /// The name the field starts with for the sound being edited: its own with the next number nothing has.
    public static func suggestedName(editing name: String, ownSounds: Set<String>, macOSSounds: Set<String>) -> String {
        SoundSaveNaming.suggestedName(for: name, ownSounds: ownSounds, macOSSounds: macOSSounds)
    }

    // MARK: - Whether anything can be saved

    /// Nothing is in the way: the sound is open and what the checks say is of what would be written.
    public var mayBeSaved: Bool { isReady && !isSaving && !isCatchingUp && !isBlocked }

    // MARK: - Save as New

    /// What would be done with the name as typed.
    public var verdict: SoundSaveNaming.Verdict {
        SoundSaveNaming.verdict(for: typedName, ownSounds: ownSounds, macOSSounds: macOSSounds)
    }

    public var canSaveAsNew: Bool { saveAsNewRequest != nil }

    /// The save Save as New makes, or nil when it is off: only a name nothing has, and never one that replaces.
    public var saveAsNewRequest: SoundSaveRequest? {
        guard mayBeSaved, case .free(let name) = verdict else { return nil }
        return SoundSaveRequest(name: name, replacing: false)
    }

    /// The sentence beside the name field that says what is wrong with the name, or nil for one that is free.
    public var nameNote: String? {
        switch verdict {
        case .free:
            return nil
        case .refused(let problem):
            return SoundEditorText.nameProblem(problem)
        case .yours(let name):
            return SoundEditorText.nameInUse(name, replaceable: offersSave && name.caseInsensitiveCompare(editedName) == .orderedSame)
        }
    }

    /// Whether `request` is one these controls would make now. The window begins no other, so a request made before
    /// something changed is not carried out after.
    public func allows(_ request: SoundSaveRequest) -> Bool {
        if request == saveAsNewRequest { return true }
        return canSave && request == SoundSaveRequest(name: editedName, replacing: true)
    }

    /// The sentences shown with the name, in the order they are shown: what is wrong with it, and that a macOS sound is
    /// only copied.
    public var notes: [String] { [nameNote, macOSNote].compactMap { $0 } }

    // MARK: - Save

    /// Whether the sound being edited is one macOS has, which is never saved over.
    public var isMacOSSound: Bool { has(editedName, in: macOSSounds) }

    /// The sentence that says a macOS sound is saved as a copy, or nil for any other sound.
    public var macOSNote: String? { isMacOSSound ? SoundEditorText.macOSCopyNote(editedName) : nil }

    /// Whether Save is shown: the sound being edited is one of the user's own that macOS has no sound of the name of.
    public var offersSave: Bool {
        SoundSaveNaming.canSaveOver(editedName, ownSounds: ownSounds, macOSSounds: macOSSounds)
    }

    public var canSave: Bool { mayBeSaved && offersSave }

    /// What pressing Save comes to, given how many rules play the sound now, or nil when it is off. It asks first when any
    /// rule does, since all of them then play the new sound and the old is not kept.
    public func saveStep(ruleCount: Int) -> SoundSaveStep? {
        guard canSave else { return nil }
        let request = SoundSaveRequest(name: editedName, replacing: true)
        guard ruleCount > 0 else { return .save(request) }
        return .ask(request, SoundEditorText.saveOverConfirmation(editedName, ruleCount: ruleCount))
    }

    private func has(_ name: String, in names: Set<String>) -> Bool {
        names.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}
