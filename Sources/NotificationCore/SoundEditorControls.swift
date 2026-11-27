// Sources/NotificationCore/SoundEditorControls.swift
import Foundation

/// What is on and what is off in the sound editor's window, and what its one play button is called (sound editor
/// plan, Tasks 7 and 8). A control that would do nothing is off, and never left on to be pressed for no reason.
///
/// An edit that reads a position, which is every one that works on a selection or goes in at the playhead, waits for
/// the render of the last edit to come back. The selection and the playhead are frames of the result as last rendered,
/// and an edit is made to the recipe as it is now: while the two are not the same sound, a selection would be read
/// against a sound that has moved on. Undo, redo and reset read no position and do not wait.
public struct SoundEditorControls: Equatable, Sendable {
    public let isReady: Bool
    public let length: Int
    public let canBeHeard: Bool
    public let isPreviewing: Bool
    public let selection: Range<Int>?
    public let viewport: WaveformViewport
    public let loops: Bool
    public let canUndo: Bool
    public let canRedo: Bool
    public let canReset: Bool
    public let hasClipboard: Bool
    public let isCatchingUp: Bool
    public let gainDB: Double
    public let isSaving: Bool

    /// - Parameters:
    ///   - isReady: the sound has been opened and rendered.
    ///   - canBeHeard: the result is above the silence floor, so that an alert of it would be played.
    ///   - loops: Loop Selection was turned on.
    ///   - canUndo: the history has an edit to take back, and `canRedo` one that was taken back.
    ///   - canReset: the sound is not the source as it was, so Reset to Original would change it.
    ///   - hasClipboard: Cut or Copy has kept something to paste.
    ///   - isCatchingUp: a render of the last change is still under way, so what is shown is the one before.
    ///   - gainDB: the gain the gain control is set to.
    ///   - isSaving: a save is under way. What it writes is the recipe as it was when it began, so nothing that changes the
    ///     recipe is on until it is done.
    public init(isReady: Bool, length: Int, canBeHeard: Bool, isPreviewing: Bool, selection: Range<Int>?,
                viewport: WaveformViewport, loops: Bool, canUndo: Bool = false, canRedo: Bool = false,
                canReset: Bool = false, hasClipboard: Bool = false, isCatchingUp: Bool = false, gainDB: Double = 0,
                isSaving: Bool = false) {
        self.isReady = isReady
        self.length = length
        self.canBeHeard = canBeHeard
        self.isPreviewing = isPreviewing
        self.selection = selection
        self.viewport = viewport
        self.loops = loops
        self.canUndo = canUndo
        self.canRedo = canRedo
        self.canReset = canReset
        self.hasClipboard = hasClipboard
        self.isCatchingUp = isCatchingUp
        self.gainDB = gainDB
        self.isSaving = isSaving
    }

    private var hasSelection: Bool { isReady && !(selection?.isEmpty ?? true) }

    /// The one button plays, and while it plays stops.
    public var playCommand: SoundEditorText.Command { isPreviewing ? .stop : .play }

    /// Whatever is playing can be stopped. Otherwise a sound is played only when it is there and an alert of it
    /// would be heard.
    public var canPlayOrStop: Bool { isPreviewing || (isReady && length > 0 && canBeHeard) }

    /// There is something to go round only when something is selected.
    public var canLoop: Bool { hasSelection }

    /// Whether the loop is on: asked for, and with a selection to go round.
    public var loopIsOn: Bool { loops && canLoop }

    public var canSelectAll: Bool { isReady && length > 0 && selection != 0..<length }
    public var canClearSelection: Bool { hasSelection }
    public var canZoomIn: Bool { isReady && viewport.canZoomIn }
    public var canZoomOut: Bool { isReady && viewport.canZoomOut }

    // MARK: - Editing

    /// Whether an edit that reads a position can be made: the sound is open and not empty, and what is shown is what the
    /// recipe now makes.
    private var editsAreAllowed: Bool { isReady && length > 0 && !isCatchingUp && !isSaving }

    private var hasSelectionToEdit: Bool { editsAreAllowed && hasSelection }

    /// Gain is for a part of the sound against the rest, and offered for nothing else (Ruling 16): a gain on all of it
    /// changes nothing anyone hears. Offered while a render is under way too, so that it does not come and go.
    public var offersGain: Bool { hasSelection && selection != 0..<length }

    /// Whether `command` can be made now. One answer for every command, so that a button, a shortcut and a menu agree
    /// and none is left on for a press that would do nothing.
    public func canPerform(_ command: SoundEditorText.Command) -> Bool {
        switch command {
        case .play, .stop: return canPlayOrStop
        case .loopSelection: return canLoop
        case .selectAll: return canSelectAll
        case .clearSelection: return canClearSelection
        case .zoomIn: return canZoomIn
        case .zoomOut: return canZoomOut
        // Trim of all that there is would change nothing. Delete and Cut of all of it are on, to be refused with the
        // sentence that says why (Ruling 18), which a button that was off would not.
        case .trim: return hasSelectionToEdit && selection != 0..<length
        case .delete, .cut, .copy, .duplicate, .fadeIn, .fadeOut, .repeatSelection: return hasSelectionToEdit
        case .gain: return hasSelectionToEdit && offersGain && gainDB != 0
        case .paste: return editsAreAllowed && hasClipboard
        case .undo: return isReady && !isSaving && canUndo
        case .redo: return isReady && !isSaving && canRedo
        case .resetToOriginal: return isReady && !isSaving && canReset
        }
    }

    /// Whether the press of a check can be made now. An edit is of frames of the result as last rendered, so it waits
    /// as the others do. Undo reads no position.
    public func canPress(_ fix: SoundFix) -> Bool {
        switch fix {
        case .edit: return editsAreAllowed
        case .undo: return isReady && !isSaving && canUndo
        }
    }
}
