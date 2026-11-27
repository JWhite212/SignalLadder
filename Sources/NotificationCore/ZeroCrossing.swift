// Sources/NotificationCore/ZeroCrossing.swift
import Foundation

/// The nearest quiet point to a frame, for the edge of a selection to be moved
/// to when an edit is made (sound editor plan, Ruling 4).
///
/// A cut at a point where the sound is crossing zero leaves the least step
/// between what comes before it and what comes after, so the join that
/// rendering smooths over has the least left to smooth. The editor's model
/// calls this with the samples of the result as last rendered, and gives the
/// frame it returns to the edit, which stays a pure function of the recipe.
public enum ZeroCrossing {
    /// How far an edge may be moved: 5 ms.
    public static let windowFrames = SampleBuffer.frames(seconds: 0.005)

    /// The frame to cut at in place of `frame`, within `window` frames of it.
    ///
    /// The channels are added together and read as one, so that both move as
    /// one. An edge is a boundary between two frames, and a change of sign is
    /// one between the frame before it and the frame after it, where it passes
    /// zero or touches it. The nearest such boundary within the window is
    /// returned, and the earlier of two the same distance away. Where there is
    /// none, it is the quietest frame in the window, the nearer and then the
    /// earlier of two as quiet. Either way the answer is never further than
    /// `window` from `frame`.
    ///
    /// The start and the end of the sound are not cuts and are returned as
    /// they are, so a selection made to an end of the sound still reaches it. A
    /// frame outside the sound is brought to the nearer end. A sample that is
    /// not a number is never a change of sign and never the quietest.
    public static func nearest(to frame: Int, in samples: SampleBuffer, within window: Int = windowFrames) -> Int {
        let count = samples.frameCount
        guard count > 0, frame > 0 else { return 0 }
        guard frame < count else { return count }
        let reach = max(window, 0)

        func level(_ index: Int) -> Float {
            var sum: Float = 0
            for channel in samples.channels { sum += channel[index] }
            return sum
        }
        /// A change of sign between the frame before `edge` and the frame at it.
        func crosses(at edge: Int) -> Bool {
            guard edge >= 1, edge < count else { return false }
            let before = level(edge - 1)
            let after = level(edge)
            guard before.isFinite, after.isFinite else { return false }
            return (before <= 0 && after >= 0) || (before >= 0 && after <= 0)
        }

        for distance in 0...reach {
            if crosses(at: frame - distance) { return frame - distance }
            if crosses(at: frame + distance) { return frame + distance }
        }

        var quietest = frame
        var quietestLevel = Float.infinity
        var found = false
        for distance in 0...reach {
            for index in [frame - distance, frame + distance] where index >= 0 && index < count {
                let size = abs(level(index))
                let magnitude = size.isFinite ? size : Float.infinity
                if !found || magnitude < quietestLevel {
                    quietest = index
                    quietestLevel = magnitude
                    found = true
                }
            }
        }
        return quietest
    }
}
