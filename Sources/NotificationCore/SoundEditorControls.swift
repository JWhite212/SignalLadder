// Sources/NotificationCore/SoundEditorControls.swift
import Foundation

/// What is on and what is off in the sound editor's window, and what its one play button is called (sound editor
/// plan, Task 7). A control that would do nothing is off, and never left on to be pressed for no reason.
public struct SoundEditorControls: Equatable, Sendable {
    public let isReady: Bool
    public let length: Int
    public let canBeHeard: Bool
    public let isPreviewing: Bool
    public let selection: Range<Int>?
    public let viewport: WaveformViewport
    public let loops: Bool

    /// - Parameters:
    ///   - isReady: the sound has been opened and rendered.
    ///   - canBeHeard: the result is above the silence floor, so that an alert of it would be played.
    ///   - loops: Loop Selection was turned on.
    public init(isReady: Bool, length: Int, canBeHeard: Bool, isPreviewing: Bool, selection: Range<Int>?,
                viewport: WaveformViewport, loops: Bool) {
        self.isReady = isReady
        self.length = length
        self.canBeHeard = canBeHeard
        self.isPreviewing = isPreviewing
        self.selection = selection
        self.viewport = viewport
        self.loops = loops
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
}
