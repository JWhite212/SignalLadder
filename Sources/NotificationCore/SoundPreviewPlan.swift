// Sources/NotificationCore/SoundPreviewPlan.swift
import Foundation

/// What a press of Play asks the player for: the frame to start from and, when a selection is to be gone round,
/// the range of it (sound editor plan, Task 7). They are `AlertPlayer.testBuffer`'s own arguments, worked out here
/// so that every case is a test and the window only hands them on.
public struct SoundPreviewPlan: Equatable, Sendable {
    /// Where playing begins.
    public let start: Int
    /// The range to go round until stopped, or nil to play to the end once.
    public let loop: Range<Int>?

    public init(start: Int, loop: Range<Int>?) {
        self.start = start
        self.loop = loop
    }

    /// Where the playhead goes back to when the preview ends of itself.
    public var returnsTo: Int { start }

    /// The plan for a sound `length` frames long, or nil when there is none, which is no sound to play.
    ///
    /// With a selection it begins at the start of the selection, and goes round it when `loops` is on; with none
    /// it begins at the playhead, and `loops` has nothing to go round. A `resumingAt` is where a preview that is
    /// already playing carries on from when a move or a change of loop restarts it, and it is used when it lies in
    /// the range gone round, or whenever there is no range. Beginning at the end begins again at the start.
    public static func make(length: Int, playhead: Int, selection: Range<Int>?, loops: Bool,
                            resumingAt: Int? = nil) -> SoundPreviewPlan? {
        guard length > 0 else { return nil }
        let inside: Range<Int>? = selection.flatMap {
            let lower = min(max($0.lowerBound, 0), length)
            let upper = min(max($0.upperBound, lower), length)
            return lower < upper ? lower..<upper : nil
        }
        if loops, let inside {
            let start = resumingAt.flatMap { inside.contains($0) ? $0 : nil } ?? inside.lowerBound
            return SoundPreviewPlan(start: start, loop: inside)
        }
        let start = resumingAt ?? inside?.lowerBound ?? playhead
        return SoundPreviewPlan(start: start >= length || start < 0 ? 0 : start, loop: nil)
    }
}
