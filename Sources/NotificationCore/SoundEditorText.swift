// Sources/NotificationCore/SoundEditorText.swift
import Foundation

/// Every word the sound editor's window shows or says (sound editor plan, Task 4),
/// worded here where it is tested, as `EditorText` words the rule editor's.
///
/// The window holds no sentence of its own. A sentence about a number says the
/// number the checks use, read from `SoundChecks.Limits`, so setting a threshold
/// by ear changes what the window says and not only what it does. Nothing says
/// "recipe", "frame" or any other word that belongs to the code: a person edits a
/// sound, in seconds.
public enum SoundEditorText {
    // MARK: - The window

    /// Above the waveform: "Editing “Night Alarm”".
    public static func heading(_ name: String) -> String { "Editing “\(name)”" }

    /// Every control the window has that does something to the sound or to what
    /// is played of it. Its title is what the control says, to the eye and to
    /// VoiceOver, so that no control is given a name by the view that draws it.
    public enum Command: CaseIterable, Sendable {
        case play, stop, loopSelection
        case trim, delete, cut, copy, paste, duplicate
        case fadeIn, fadeOut, gain, repeatSelection
        case undo, redo, resetToOriginal
        case selectAll, clearSelection, zoomIn, zoomOut

        public var title: String {
            switch self {
            case .play: return "Play"
            case .stop: return "Stop"
            case .loopSelection: return "Loop Selection"
            case .trim: return "Trim"
            case .delete: return "Delete"
            case .cut: return "Cut"
            case .copy: return "Copy"
            case .paste: return "Paste"
            case .duplicate: return "Duplicate"
            case .fadeIn: return "Fade In"
            case .fadeOut: return "Fade Out"
            case .gain: return "Gain"
            case .repeatSelection: return "Repeat"
            case .undo: return "Undo"
            case .redo: return "Redo"
            case .resetToOriginal: return "Reset to Original"
            case .selectAll: return "Select All"
            case .clearSelection: return "Clear Selection"
            case .zoomIn: return "Zoom In"
            case .zoomOut: return "Zoom Out"
            }
        }
    }

    // MARK: - Gain and repeat

    public static let gainLabel = "Gain on the selection"

    /// Beside the gain, and what Ruling 16 says: the player brings every sound to
    /// the same peak, so only a part against the rest of a sound is heard.
    public static let gainNote = "This changes the selection against the rest of the sound. "
        + "How loud the whole sound plays is set when it plays, so raising all of it would change nothing you can hear."

    /// Said where the gain is, when there is no selection or it is the whole sound.
    public static let gainNeedsASelection = "Select part of the sound, not all of it, to change its gain."

    public static let playsLabel = "Plays"
    public static let gapLabel = "Gap between plays, in seconds"

    // MARK: - Readouts and VoiceOver

    /// "Length: 2.4 seconds".
    public static func lengthReadout(frames: Int) -> String { "Length: \(secondsText(frames: frames))" }

    /// What VoiceOver calls the waveform.
    public static func waveformLabel(_ name: String) -> String { "Waveform of “\(name)”" }

    /// What VoiceOver reads as the waveform's value, in seconds:
    /// "Playhead at 1.5 of 3 seconds. Selected from 0.5 to 1.1 seconds." The
    /// positions and the length are frames of the result.
    public static func waveformValue(playhead: Int, selection: Range<Int>?, length: Int) -> String {
        let place = "Playhead at \(number(frames: playhead)) of \(secondsText(frames: length))."
        guard let selection, !selection.isEmpty else { return place + " Nothing selected." }
        return place + " Selected from \(number(frames: selection.lowerBound)) to "
            + "\(secondsText(frames: selection.upperBound))."
    }

    /// What VoiceOver says of how to use the waveform.
    public static let waveformHint = "Space plays and stops. The left and right arrows move the playhead, and holding Shift "
        + "with them selects. Home and End go to the ends."

    /// Said while a newer render is under way and the last finished one is what plays.
    public static let catchingUp = "Catching up with your last edit…"

    // MARK: - The checks

    public static let checksHeading = "Checks"
    public static let noFindings = "Nothing to warn about."

    /// What a check found, in one sentence. The two that stop a save say so.
    public static func sentence(for finding: SoundFinding) -> String {
        typealias Limits = SoundChecks.Limits
        switch finding.kind {
        case .nothingToHear:
            return "There is nothing to hear: all of it is too quiet to play as an alert. Saving is off until there is."
        case .tooLong:
            let length = finding.frames.map { "It is \(secondsText(frames: $0, .up)) long" } ?? "It is too long"
            return "\(length), and a saved sound can be at most \(secondsText(frames: Limits.longestFrames)). "
                + "Saving is off until it is shorter."
        case .startsAbruptly:
            return "It starts abruptly: it is at half its loudest within \(milliseconds(Limits.abruptWithinSeconds)), "
                + "which can sound like a click."
        case .tooShort:
            let length = finding.frames.map { "It is only \(secondsText(frames: $0, .down))" } ?? "It is short"
            return "\(length), and a sound under \(secondsText(frames: Limits.shortestFrames)) is easy to miss."
        case .silenceAtStart:
            let silence = finding.frames.map { "\(secondsText(frames: $0, .up)) of silence" } ?? "silence"
            return "It begins with \(silence), so the alert would seem to come late."
        case .silenceAtEnd:
            let silence = finding.frames.map { "\(secondsText(frames: $0, .up)) of silence" } ?? "silence"
            return "It ends with \(silence), so it takes longer to finish than it needs to."
        case .clipping:
            return "Part of it is flattened at full level, which sounds harsh. "
                + "The damage is in the sound itself, so start from a cleaner copy of it if you can."
        }
    }

    /// The button beside a finding's sentence, or nil for a kind of finding that has no press. It is
    /// shown only for a finding whose own `fix` is not nil: the fade in for an abrupt start is left
    /// off a sound that no fade would mend.
    public static func pressLabel(for kind: SoundFinding.Kind) -> String? {
        switch kind {
        case .nothingToHear: return "Undo"
        case .tooLong: return "Keep the First \(secondsText(frames: SoundChecks.Limits.longestFrames).capitalisedWords)"
        case .startsAbruptly: return "Fade In the Start"
        case .tooShort: return "Repeat It \(SoundChecks.Limits.shortRepeatTimes) Times"
        case .silenceAtStart: return "Trim the Silence at the Start"
        case .silenceAtEnd: return "Trim the Silence at the End"
        case .clipping: return nil
        }
    }

    // MARK: - Why an edit was not made

    /// The sentence for an edit that was refused, which changed nothing.
    public static func refusal(_ refusal: SoundEditRefusal) -> String {
        let editing = secondsText(frames: SoundRecipe.maximumFrames)
        switch refusal {
        case .sourceTooLong(let frames):
            return "This sound is \(secondsText(frames: frames, .up)) long, and the editor opens sounds of up to \(editing)."
        case .tooLong(let frames):
            return "That would make the sound \(secondsText(frames: frames, .up)) long. While you edit, a sound can be up to "
                + "\(editing), and it saves at up to \(secondsText(frames: SoundRecipe.savableFrames))."
        case .wouldLeaveNothing:
            return "That would leave nothing of the sound, so it was not done."
        case .emptySelection:
            return "Select part of the sound first."
        case .selectionOutsideSound:
            return "The selection reaches outside the sound. Select again."
        case .tooManyPieces:
            return "That would cut the sound into too many parts. Undo some edits first."
        case .excerptFromAnotherSound:
            return "What you copied is from a different sound, so it cannot be pasted here."
        case .gainOutOfRange:
            return "A gain must be a number, and no part of a sound can be raised or lowered by more than "
                + "\(Int(SoundRecipe.maximumGainDB)) dB in all."
        case .playsOutOfRange:
            return "A repeat plays the selection from 2 to \(SoundEdit.mostPlays) times."
        case .gapOutOfRange:
            return "The gap between plays must not be negative, and can be at most \(editing)."
        }
    }

    /// Said when a preview is asked for while an alert is sounding (Ruling 7).
    public static let previewRefused = "An alert is sounding, so the preview did not play."

    // MARK: - Saving

    public static let nameLabel = "Name"

    /// What a sound with no name of its own is called when a name is suggested for what is made of it.
    public static let untitledSoundName = "Sound"
    public static let saveAsNew = "Save as New"
    public static let save = "Save"
    public static let saveOver = "Save Over"

    /// Asked before a sound of the user's own is saved over.
    public static func saveOverQuestion(_ name: String) -> String { "Save over your sound “\(name)”?" }

    /// How many rules will play the new sound, and that the old one is not kept.
    public static func saveOverDetail(ruleCount: Int) -> String {
        let uses: String
        switch ruleCount {
        case 0: uses = "No rule uses it."
        case 1: uses = "1 rule uses it, and will play the new sound."
        default: uses = "\(ruleCount) rules use it, and all of them will play the new sound."
        }
        return uses + " The sound it replaces is not kept."
    }

    /// Said beside the name when the sound being edited is one macOS has, which is
    /// never saved over.
    public static func macOSCopyNote(_ name: String) -> String {
        "“\(name)” is a macOS sound and cannot be changed, so this is saved as a copy under a new name."
    }

    public static func nameProblem(_ problem: SoundSaveNaming.Problem) -> String {
        switch problem {
        case .blank: return "Give the sound a name."
        case .tooLong: return "A name can be at most \(SoundSaveNaming.longestName) characters."
        case .tooLongAsAFileName: return "That name is too long to be a file name. Use a shorter one."
        case .startsWithDot: return "A name cannot begin with a dot."
        case .unsafeCharacter: return "A name cannot contain “/”, “:” or “\\”, or a line break or tab."
        case .macOSSound(let name): return "macOS already has a sound called “\(name)”. Choose another name."
        }
    }

    public static func saved(_ name: String) -> String { "Saved as “\(name)”." }

    public static let saveFailedTitle = "The sound could not be saved."
    public static func saveFailedDetail(_ reason: String) -> String {
        "\(reason)\n\nYour sounds are as they were, and your edits are still here."
    }

    /// Said when the sound was saved and its edits could not be kept beside it
    /// (Task 5): it plays, and opens next time as a sound of its own.
    public static let editsCannotBeReopened = "The sound was saved and plays as it should, "
        + "but its edits could not be kept, so the editor will open it as a new sound next time."

    public static func cannotOpen(_ name: String, reason: String) -> String {
        "“\(name)” could not be opened for editing: \(reason)"
    }

    /// Why a sound could not be opened, to follow the colon of `cannotOpen`: a phrase that
    /// begins in lower case and has no full stop.
    public static func openReason(_ failure: SoundOpenFailure) -> String {
        switch failure {
        case .notFound:
            return "there is no sound of that name"
        case .tooLarge(let limit):
            return "the file is larger than \(limit) MB"
        case .tooLong(let frames):
            return "it is \(secondsText(frames: frames, .up)) long, and the editor opens sounds of up to "
                + secondsText(frames: SoundRecipe.maximumFrames)
        case .unreadable(let reason):
            return "it could not be read as audio: \(reason)"
        }
    }

    /// The whole sentence for a sound that could not be opened.
    public static func cannotOpen(_ name: String, failure: SoundOpenFailure) -> String {
        sentence(cannotOpen(name, reason: openReason(failure)))
    }

    /// Why a sound was not saved, as a sentence, to go where `saveFailedDetail` is given its
    /// reason. It names no step of the save: only what a person can do about it.
    public static func saveFailure(_ failure: SoundSaveFailure) -> String {
        switch failure {
        case .badName:
            return "That name cannot be used for a sound. Choose another."
        case .systemSound(let name):
            return nameProblem(.macOSSound(name))
        case .alreadyExists(let name):
            return "You already have a sound called “\(name)”. Choose another name, or save over it."
        case .cannotSetAside(let name):
            return "Your sound “\(name)” has too long a name to be replaced safely. "
                + "Save under another name, or give it a shorter name in your sounds folder."
        case .silent:
            return "There is nothing to hear in it, so it was not saved."
        case .tooLong:
            return "It is longer than \(secondsText(frames: SoundRecipe.savableFrames)), so it was not saved."
        case .sourceChanged:
            return "The sound was changed outside the editor after it was opened. Close this window and open it again."
        case .unreadable(let reason):
            return sentence("The sound that was made could not be read back, so it was not kept: \(reason)")
        case .couldNotWrite(let reason):
            guard let reason, !reason.isEmpty else { return "The sound could not be written." }
            return sentence("The sound could not be written: \(reason)")
        }
    }

    /// `text` as a sentence: with a full stop unless it already ends one.
    private static func sentence(_ text: String) -> String {
        guard let last = text.last else { return text }
        return ".!?".contains(last) ? text : text + "."
    }

    // MARK: - Closing

    public static func closeQuestion(_ name: String) -> String { "Save the changes to “\(name)”?" }
    public static let closeDetail = "Changes are lost if you don't save them."

    // MARK: - Times

    /// How a time is rounded to the hundredths a sentence says it in.
    private enum Rounding {
        case nearest
        /// For a time that is past a limit it is said beside, so that it is not written as the limit.
        case up
        /// For a time that is under a limit it is said beside, for the same reason.
        case down
    }

    /// A time to hundredths, without a trailing zero: "0.4", "2", "31.25". Worked out in whole
    /// frames and not in floats, in which 0.07 seconds is 7.000000000000001 hundredths and rounds
    /// up to 8.
    private static func number(frames: Int, _ rounding: Rounding = .nearest) -> String {
        let rate = SampleBuffer.sampleRate
        let frames = max(frames, 0)
        // Whole seconds and what is left apart, so that no length can overflow when it is multiplied.
        let left = (frames % rate) * 100
        let part: Int
        switch rounding {
        case .nearest: part = (left + rate / 2) / rate
        case .up: part = (left + rate - 1) / rate
        case .down: part = left / rate
        }
        return NumberText.plain(Double(frames / rate * 100 + part) / 100)
    }

    /// "2.4 seconds", "1 second".
    private static func secondsText(frames: Int, _ rounding: Rounding = .nearest) -> String {
        let text = number(frames: frames, rounding)
        return "\(text) second\(text == "1" ? "" : "s")"
    }

    /// "10 milliseconds", "1 millisecond".
    private static func milliseconds(_ seconds: Double) -> String {
        let count = Int((seconds * 1000).rounded())
        return "\(count) millisecond\(count == 1 ? "" : "s")"
    }
}

private extension String {
    /// "30 seconds" as "30 Seconds", for a button's title.
    var capitalisedWords: String {
        split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
