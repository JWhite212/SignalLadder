// Sources/NotificationCore/SoundRender.swift
import Foundation

/// A recipe played into samples: what the editor shows, plays and saves (sound
/// editor plan, Ruling 4).
///
/// It is arithmetic on arrays, so it sits in the core and may run off the main
/// actor (Ruling 6), and the same recipe and source always give the same
/// samples.
public enum SoundRender {
    /// How long a join is faded down and up over: 5 ms, or half the piece if
    /// that is shorter.
    public static let dipFrames = SampleBuffer.frames(seconds: 0.005)

    /// Where one piece of a recipe lands in the result, and how much of its
    /// front and back is faded for the joins it has.
    private struct Placement {
        let segment: SoundSegment
        let position: Int
        let dipIn: Int
        let dipOut: Int
        /// The piece's gain when no fade is on it, which is the same on every
        /// frame and so is worked out once and not for each.
        let steadyGain: Float?
    }

    /// The samples a recipe makes of `source`, in one pass and into one
    /// allocation for each channel. The result has the source's channels and
    /// exactly `recipe.frameCount` frames, the sum of its pieces' lengths, so a
    /// position in the result is one frame and nothing shifts at a join.
    ///
    /// Each piece is the source's frames under the piece's gain and fades,
    /// through `SoundSegment.gain(atPieceFrame:)`, which is the one definition
    /// of what a piece does. A join between two pieces that were not
    /// neighbours in the source is a dip and not an overlap: the piece before
    /// ends in a fade down and the piece after begins with a fade up, each
    /// `dipFrames` long, or half the piece if that is shorter, so the result
    /// goes through silence at the join and does not step. Neighbours in the
    /// source are not joined by a dip, however their gains differ, and nothing
    /// is faded at the start or the end of the sound, which are not joins. A
    /// piece beside silence is faded on its side of it.
    ///
    /// A recipe is made for one source, and the editor hands this the source it
    /// was made from. If it is given a shorter one, the frames it does not have
    /// play as silence and it does not fail.
    public static func render(source: SampleBuffer, recipe: SoundRecipe) -> SampleBuffer {
        let placements = place(recipe)
        let total = recipe.frameCount
        let channels = source.channels.map { input in
            [Float](unsafeUninitializedCapacity: total) { output, count in
                input.withUnsafeBufferPointer { input in
                    for placement in placements {
                        fill(output, from: input, placement)
                    }
                }
                count = total
            }
        }
        // Every channel is `total` frames long, and a source has at least one.
        return SampleBuffer(channels: channels)!
    }

    private static func place(_ recipe: SoundRecipe) -> [Placement] {
        let segments = recipe.segments
        var placements: [Placement] = []
        placements.reserveCapacity(segments.count)
        var position = 0
        for (index, segment) in segments.enumerated() {
            var dipIn = 0
            var dipOut = 0
            var steadyGain: Float?
            if case .clip(_, _, _, let fades) = segment {
                let dip = min(dipFrames, max(1, segment.frames / 2))
                if index > 0, !neighbours(segments[index - 1], segment) { dipIn = dip }
                if index + 1 < segments.count, !neighbours(segment, segments[index + 1]) { dipOut = dip }
                if fades.isEmpty { steadyGain = segment.gain(atPieceFrame: 0) }
            }
            placements.append(Placement(segment: segment, position: position, dipIn: dipIn, dipOut: dipOut,
                                        steadyGain: steadyGain))
            position += segment.frames
        }
        return placements
    }

    /// Whether `second` carries on from `first` in the source: two stretches of
    /// it that meet. Silence is never a neighbour.
    private static func neighbours(_ first: SoundSegment, _ second: SoundSegment) -> Bool {
        guard case .clip(_, let end, _, _) = first, case .clip(let start, _, _, _) = second else { return false }
        return end == start
    }

    private static func fill(_ output: UnsafeMutableBufferPointer<Float>, from input: UnsafeBufferPointer<Float>,
                             _ placement: Placement) {
        let length = placement.segment.frames
        guard case .clip(let start, _, _, _) = placement.segment else {
            for frame in 0..<length { output[placement.position + frame] = 0 }
            return
        }
        for frame in 0..<length {
            let index = start + frame
            var sample: Float = index >= 0 && index < input.count ? input[index] : 0
            sample *= placement.steadyGain ?? placement.segment.gain(atPieceFrame: frame)
            if frame < placement.dipIn {
                sample *= Float(frame) / Float(placement.dipIn)
            }
            let fromEnd = length - 1 - frame
            if fromEnd < placement.dipOut {
                sample *= Float(fromEnd) / Float(placement.dipOut)
            }
            output[placement.position + frame] = sample
        }
    }
}
