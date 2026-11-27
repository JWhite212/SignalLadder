// Sources/NotificationCore/SoundTimeline.swift
import Foundation

/// Where the playhead is and what is selected in the sound editor's window, and how the keyboard, the pointer and a
/// preview move them (sound editor plan, Ruling 13 and Task 7).
///
/// Every position is a frame of the result, between 0 and its length, and a selection is never empty: nothing
/// between two ends is nothing selected. A selection does not move when the result is previewed, and the playhead
/// does.
public struct SoundTimeline: Equatable, Sendable {
    /// How many frames the result has.
    public private(set) var length: Int
    /// Where playing begins from, and where a preview has got to while it plays.
    public private(set) var playhead = 0
    /// What is selected, or nil.
    public private(set) var selection: Range<Int>?
    /// The end of the selection that Shift with an arrow leaves where it is. Only meant for a selection that is
    /// there: with none, extending begins from the playhead.
    private var anchor: Int?
    private var drag: Drag?

    /// A press of the pointer, from its going down to its coming up.
    private struct Drag: Equatable {
        /// The end of the selection that the drag does not move: where a new selection began, or the end of an
        /// existing one that is opposite the edge that was taken hold of.
        var fixed: Int
        /// Where the pointer went down.
        var down: Int
        /// Whether it took hold of an edge of the selection that was there.
        var tookAnEdge: Bool
        /// Whether it has gone far enough to be more than a click.
        var moved = false
    }

    public init(length: Int) {
        self.length = max(length, 0)
    }

    public var hasSelection: Bool { selection != nil }
    public var selectionIsWhole: Bool { selection == 0..<length }
    public var isDragging: Bool { drag != nil }

    /// Where zooming is aimed: the middle of the selection, or else the playhead.
    public var focus: Int {
        selection.map { $0.lowerBound + $0.count / 2 } ?? playhead
    }

    private func held(_ frame: Int) -> Int { min(max(frame, 0), length) }

    private func ordered(_ first: Int, _ second: Int) -> Range<Int>? {
        first == second ? nil : min(first, second)..<max(first, second)
    }

    // MARK: - Placing and selecting

    /// A click: the playhead goes here and nothing is selected.
    public mutating func place(_ frame: Int) {
        playhead = held(frame)
        selection = nil
        anchor = nil
    }

    /// An arrow key, or Home or End. Without `extending` the playhead goes to `frame` and nothing is selected.
    /// With it the selection runs from the end it already had, or from where the playhead was when there was
    /// none, to `frame`, so a run of presses with Shift held makes one selection, and coming back to where it
    /// began selects nothing.
    public mutating func moveHead(to frame: Int, extending: Bool) {
        let frame = held(frame)
        guard extending else { return place(frame) }
        let fixed = selection == nil ? playhead : (anchor ?? playhead)
        playhead = frame
        selection = ordered(fixed, frame)
        anchor = selection == nil ? nil : fixed
    }

    /// Selects `range`, held to the sound, with the playhead at its start. An empty range selects nothing.
    public mutating func select(_ range: Range<Int>) {
        let lower = held(range.lowerBound)
        let upper = max(held(range.upperBound), lower)
        guard lower < upper else { return clearSelection() }
        selection = lower..<upper
        playhead = lower
        anchor = upper
    }

    public mutating func selectAll() {
        select(0..<length)
    }

    /// Clears the selection and leaves the playhead where it is.
    public mutating func clearSelection() {
        selection = nil
        anchor = nil
    }

    // MARK: - A preview

    /// The playhead follows a preview, which does not change what is selected. Held to the sound.
    public mutating func followPreview(_ frame: Int) {
        playhead = held(frame)
    }

    /// A preview that has ended, of itself, by being stopped elsewhere or by an alert, puts the playhead back where
    /// it began.
    public mutating func previewEnded(returningTo frame: Int) {
        playhead = held(frame)
    }

    // MARK: - A new length

    /// The result is now `newLength` frames long, as it is after a render. Everything is held to it, a selection
    /// that is no longer there is dropped, and a drag that was under way is ended.
    public mutating func setLength(_ newLength: Int) {
        length = max(newLength, 0)
        playhead = held(playhead)
        if let selection {
            let lower = held(selection.lowerBound)
            let upper = held(selection.upperBound)
            self.selection = lower < upper ? lower..<upper : nil
        }
        anchor = selection == nil ? nil : anchor.map(held)
        drag = nil
    }

    // MARK: - The pointer

    /// The pointer went down at `frame`. Within `edgeReach` frames of an edge of the selection it takes hold of the
    /// nearer edge, to move it. Anywhere else it begins a new selection, which a click that does not move turns
    /// into a placing of the playhead.
    public mutating func pointerDown(at frame: Int, edgeReach: Int) {
        let frame = held(frame)
        if let selection {
            let toStart = abs(frame - selection.lowerBound)
            let toEnd = abs(frame - selection.upperBound)
            if min(toStart, toEnd) <= max(edgeReach, 0) {
                // The one nearer is taken; the start when they are as near as each other.
                drag = toStart <= toEnd
                    ? Drag(fixed: selection.upperBound, down: frame, tookAnEdge: true)
                    : Drag(fixed: selection.lowerBound, down: frame, tookAnEdge: true)
                return
            }
        }
        drag = Drag(fixed: frame, down: frame, tookAnEdge: false)
    }

    /// The pointer moved to `frame` with the press still down. Until it has gone more than `slop` frames from
    /// where it went down, a press is still a click, and nothing changes. After that the selection runs between
    /// the end that is fixed and the pointer, whichever way round they are, and is none where they meet.
    public mutating func pointerMoved(to frame: Int, slop: Int) {
        guard var drag else { return }
        let frame = held(frame)
        if !drag.moved {
            guard abs(frame - drag.down) > max(slop, 0) else { return }
            drag.moved = true
            self.drag = drag
        }
        selection = ordered(drag.fixed, frame)
    }

    /// The pointer came up at `frame`. A press that moved leaves its selection and puts the playhead at the
    /// start of it, or where it began when it came back to nothing. One that took an edge and did not move
    /// changes nothing, and one that began a selection and did not move is a click.
    ///
    /// - Returns: whether the press moved the playhead or changed the selection, which is so of a click and of a
    ///   drag and not of one that only took hold of an edge and let go, nor of a release with no press before it.
    ///   Comparing the timeline with a copy of itself made before cannot tell: a press under way is part of what
    ///   is compared, so the two are never equal.
    @discardableResult
    public mutating func pointerUp(at frame: Int) -> Bool {
        guard let drag else { return false }
        self.drag = nil
        if drag.moved {
            playhead = selection?.lowerBound ?? drag.fixed
            anchor = selection?.upperBound
            return true
        }
        guard !drag.tookAnEdge else { return false }
        place(frame)
        return true
    }
}
