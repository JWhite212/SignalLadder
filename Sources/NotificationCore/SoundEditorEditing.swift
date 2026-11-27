// Sources/NotificationCore/SoundEditorEditing.swift
import Foundation

/// What one of the window's edit commands asks of the history: an edit to make, and a copy to keep first (sound
/// editor plan, Task 8).
public struct SoundEditorEdit: Equatable, Sendable {
    /// The range of the result whose pieces go on the clipboard, taken from the recipe as it is before the edit is
    /// made. nil for a command that keeps nothing.
    public let copying: Range<Int>?
    /// The edit to make, or nil for a command that edits nothing, which is Copy.
    public let edit: SoundEdit?

    public init(copying: Range<Int>?, edit: SoundEdit?) {
        self.copying = copying
        self.edit = edit
    }
}

/// Where the playhead and the selection go once an edit has been made and its result rendered (sound editor plan,
/// Task 8). Said as a value so that the window can hold it until the render comes back, since only then is there a
/// result for it to be held to.
public enum SoundEditPlacement: Equatable, Sendable {
    /// Leave them where they are, held to the new length as a render always does.
    case keep
    /// The playhead here and nothing selected.
    case playhead(Int)
    /// This stretch selected, with the playhead at its start.
    case select(Range<Int>)

    /// Where they go after `edit`. A cut leaves the head where the cut was made, a paste, a duplicate and a repeat
    /// select what they made so that the next press works on it, and a fade or a gain leaves the selection to be
    /// heard.
    public static func after(_ edit: SoundEdit) -> SoundEditPlacement {
        switch edit {
        case .trim:
            return .playhead(0)
        case .delete(let range), .cut(let range):
            return .playhead(range.lowerBound)
        case .paste(let excerpt, let range):
            return .select(range.lowerBound..<(range.lowerBound + min(excerpt.frameCount, SoundRecipe.maximumFrames)))
        case .duplicate(let range):
            let count = min(range.count, SoundRecipe.maximumFrames)
            return .select(range.upperBound..<(range.upperBound + count))
        case .fadeIn, .fadeOut, .gain:
            return .keep
        case .repeatSelection(let range, let times, let gapFrames):
            // The edit has been made, so these are inside what a recipe holds. Held to it all the same, so that a
            // placement worked out for one that was not made can never overflow.
            let plays = min(max(times, 0), SoundEdit.mostPlays)
            let gap = min(max(gapFrames, 0), SoundRecipe.maximumFrames)
            let count = min(range.count, SoundRecipe.maximumFrames)
            return .select(range.lowerBound..<(range.lowerBound + plays * count + max(plays - 1, 0) * gap))
        }
    }
}

extension SoundTimeline {
    /// Puts the playhead and the selection where an edit says. Held to the sound, as every position is.
    public mutating func apply(_ placement: SoundEditPlacement) {
        switch placement {
        case .keep: break
        case .playhead(let frame): place(frame)
        case .select(let range): select(range)
        }
    }
}

/// What each edit command of the sound editor's window comes to (sound editor plan, Rulings 4, 11 and 16 and
/// Task 8): the edit, on the selection with each edge moved to a quiet point, and the ranges the controls that set
/// a gain and a repeat keep to.
///
/// Pure, and given the samples of the result as last rendered, as Ruling 4 asks, so that the edit that goes to the
/// history is a function of the recipe and numbers it is given.
public enum SoundEditorEditing {
    // MARK: - What the gain and the repeat controls offer

    /// The gain the window offers, in decibels. A part is raised or lowered against the rest, and the player decides
    /// how loud the whole plays (Ruling 16), so a range that reaches ±24 dB is far more than that needs. Inside the
    /// ±60 dB a recipe holds, so that every gain offered is one an edit accepts, though two on one part add up.
    public static let gainRangeDB: ClosedRange<Double> = -24...24
    public static let gainStepDB = 1.0

    /// How many plays a repeat offers: at least two, and as many as a person sets by hand. Far under what an edit
    /// takes, which is refused by length and not by count.
    public static let playsRange = 2...20
    public static let defaultPlays = 2

    /// How long a gap between plays the window offers, in seconds, and how it is stepped.
    public static let gapRangeSeconds: ClosedRange<Double> = 0...5
    public static let gapStepSeconds = 0.05
    public static let defaultGapSeconds = 0.0

    /// A gain held to the range offered. Not a number is no gain.
    public static func clampedGainDB(_ value: Double) -> Double {
        guard !value.isNaN else { return 0 }
        return min(max(value, gainRangeDB.lowerBound), gainRangeDB.upperBound)
    }

    public static func clampedPlays(_ value: Int) -> Int {
        min(max(value, playsRange.lowerBound), playsRange.upperBound)
    }

    /// A gap held to the range offered and kept to hundredths, so that a step of a twentieth added up never reads as
    /// the float's error. Not a number is no gap.
    public static func clampedGapSeconds(_ value: Double) -> Double {
        guard !value.isNaN else { return 0 }
        let held = min(max(value, gapRangeSeconds.lowerBound), gapRangeSeconds.upperBound)
        return (held * 100).rounded() / 100
    }

    // MARK: - Where an edge goes

    /// `range` with each edge moved to the nearest quiet point of `samples` within `ZeroCrossing.windowFrames`
    /// (Ruling 4). The ends of the sound are not moved. A selection that would be left with nothing in it, because
    /// both edges are nearest to one point, is left as it was: a person who selected so little meant it, and the
    /// render smooths the join all the same.
    public static func snapped(_ range: Range<Int>, in samples: SampleBuffer) -> Range<Int> {
        let length = samples.frameCount
        let lower = min(max(range.lowerBound, 0), length)
        let upper = min(max(range.upperBound, lower), length)
        let first = ZeroCrossing.nearest(to: lower, in: samples)
        let last = ZeroCrossing.nearest(to: upper, in: samples)
        // An edge that has met the other, or gone past it, is a selection that has collapsed. Past it can only be
        // where the quietest frame of each window is not in the order of the edges, and is held to all the same, since
        // a range whose end is before its start is not a range.
        guard first < last else { return lower..<upper }
        return first..<last
    }

    // MARK: - What a command comes to

    /// The edit a command makes, from what the window is showing.
    ///
    /// - Parameters:
    ///   - selection: what is selected, in frames of `samples`. A command that works on a selection is refused
    ///     without one.
    ///   - playhead: where Paste goes in when nothing is selected, moved to a quiet point as an edge is.
    ///   - samples: the result as last rendered, which the edges are moved to a quiet point of.
    ///   - clipboard: what Copy or Cut last kept.
    /// - Returns: nil for a command that is not an edit, and for Paste with nothing to paste. Otherwise the edit, or
    ///   the refusal that no edit can be made without a selection.
    public static func plan(_ command: SoundEditorText.Command, selection: Range<Int>?, playhead: Int, samples: SampleBuffer,
                            clipboard: SoundExcerpt?, gainDB: Double, plays: Int,
                            gapSeconds: Double) -> Result<SoundEditorEdit, SoundEditRefusal>? {
        /// An edit on the selection with its edges moved, or the refusal that there is none.
        func onSelection(_ make: (Range<Int>) -> SoundEditorEdit) -> Result<SoundEditorEdit, SoundEditRefusal> {
            guard let selection, !selection.isEmpty else { return .failure(.emptySelection) }
            return .success(make(snapped(selection, in: samples)))
        }
        switch command {
        case .play, .stop, .loopSelection, .undo, .redo, .resetToOriginal, .selectAll, .clearSelection, .zoomIn, .zoomOut:
            return nil
        case .paste:
            guard let clipboard else { return nil }
            let range: Range<Int>
            if let selection, !selection.isEmpty {
                range = snapped(selection, in: samples)
            } else {
                let point = ZeroCrossing.nearest(to: playhead, in: samples)
                range = point..<point
            }
            return .success(SoundEditorEdit(copying: nil, edit: .paste(clipboard, replacing: range)))
        case .trim: return onSelection { SoundEditorEdit(copying: nil, edit: .trim($0)) }
        case .delete: return onSelection { SoundEditorEdit(copying: nil, edit: .delete($0)) }
        case .cut: return onSelection { SoundEditorEdit(copying: $0, edit: .cut($0)) }
        case .copy: return onSelection { SoundEditorEdit(copying: $0, edit: nil) }
        case .duplicate: return onSelection { SoundEditorEdit(copying: nil, edit: .duplicate($0)) }
        case .fadeIn: return onSelection { SoundEditorEdit(copying: nil, edit: .fadeIn($0)) }
        case .fadeOut: return onSelection { SoundEditorEdit(copying: nil, edit: .fadeOut($0)) }
        case .gain: return onSelection { SoundEditorEdit(copying: nil, edit: .gain($0, dB: gainDB)) }
        case .repeatSelection:
            let gapFrames = SampleBuffer.frames(seconds: gapSeconds)
            return onSelection { SoundEditorEdit(copying: nil, edit: .repeatSelection($0, times: plays, gapFrames: gapFrames)) }
        }
    }
}
