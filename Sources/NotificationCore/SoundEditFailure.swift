// Sources/NotificationCore/SoundEditFailure.swift
import Foundation

/// Why a sound could not be opened for editing (sound editor plan, Task 5).
///
/// Typed here, where `SoundEditorText` can word it, and made by `AlertAudio`, which
/// reads the files. A failure says what was the matter and carries what a sentence
/// about it needs; no sentence is written anywhere but the text enum.
public enum SoundOpenFailure: Error, Equatable, Sendable {
    /// No sound has this name, in the user's sounds or macOS's.
    case notFound(String)
    /// The file is over the size an added sound may be, which a copy of it kept
    /// beside the edits would be too. Carries the limit, in megabytes.
    case tooLarge(limitMegabytes: Int)
    /// The sound runs past what a recipe may hold (Ruling 18), carrying its length
    /// in frames.
    case tooLong(frames: Int)
    /// It could not be read as audio, for the reason the system gave.
    case unreadable(String)
}

/// Why an edited sound was not saved (Rulings 8, 10 and 11). When one is returned,
/// the sounds in the folder are as they were: a sound that has been given its name
/// is not a failure, whatever happens to its edits after.
///
/// Every refusal that giving a sound its name can make has a case here, so that the
/// window never shows the words of adding a sound ("The sound could not be added")
/// for a sound that was being saved.
public enum SoundSaveFailure: Error, Equatable, Sendable {
    /// The name cannot be a sound's, as a name typed in the window is held to.
    case badName
    /// macOS has a sound of this name, spelt as given here, which a file of the user's
    /// would take the place of for every rule that names it.
    case systemSound(String)
    /// The user has a sound of this name, spelt as given here, and saving over it was
    /// not asked for.
    case alreadyExists(String)
    /// The sound to be replaced has too long a name to be set aside under the name that
    /// lets a stopped replace be put right, so it is not replaced.
    case cannotSetAside(String)
    /// The sound that was made is below the silence floor, so no alert could be heard.
    case silent
    /// The sound that was made is longer than a saved sound may be.
    case tooLong
    /// The sound the edits were made from is not the one that was opened: the file
    /// was changed outside the editor, so what is saved would not be what is shown.
    case sourceChanged
    /// What was written could not be read back as audio, for the reason the system gave.
    case unreadable(String)
    /// Something could not be written or moved. The reason the system gave, when it gave one.
    case couldNotWrite(String?)
}
