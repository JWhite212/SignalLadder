// Sources/NotificationCore/WaveformPeaks.swift
import Foundation

/// The numbers a waveform is drawn from: the lowest and highest sample of each
/// column of the drawing (sound editor plan, Task 3).
///
/// A column is a stretch of frames, so a sound of any length is drawn in any
/// width, and zooming is asking for the columns of a smaller range.
public enum WaveformPeaks {
    /// The lowest and the highest sample of the frames one column stands for,
    /// over every channel. Both are 0 for a column with nothing to measure.
    public struct Column: Equatable, Sendable {
        public let minimum: Float
        public let maximum: Float

        public init(minimum: Float, maximum: Float) {
            self.minimum = minimum
            self.maximum = maximum
        }
    }

    /// `count` columns across frames `frames` of `samples`.
    ///
    /// Column `c` stands for the frames from `c * length / count` up to
    /// `(c + 1) * length / count` counted from the start of the range, in whole
    /// frames, so every frame is in one column and none in two. When there are
    /// more columns than frames a column stands for the one frame it falls on,
    /// so a sound zoomed in far enough is drawn as steps and not as gaps.
    /// A range that reaches outside the sound is held to the sound, and a
    /// range with nothing in it gives flat columns. Samples that are not
    /// numbers are passed over. `count` is how many columns are drawn, at most a
    /// few thousand.
    public static func columns(of samples: SampleBuffer, frames: Range<Int>, count: Int) -> [Column] {
        guard count > 0 else { return [] }
        let lower = min(max(frames.lowerBound, 0), samples.frameCount)
        let upper = min(max(frames.upperBound, lower), samples.frameCount)
        let length = upper - lower
        guard length > 0 else { return Array(repeating: Column(minimum: 0, maximum: 0), count: count) }

        return (0..<count).map { index in
            let first = lower + index * length / count
            let last = max(lower + (index + 1) * length / count, first + 1)
            var lowest = Float.infinity
            var highest = -Float.infinity
            for channel in samples.channels {
                for frame in first..<last {
                    let sample = channel[frame]
                    guard sample.isFinite else { continue }
                    lowest = min(lowest, sample)
                    highest = max(highest, sample)
                }
            }
            return lowest <= highest ? Column(minimum: lowest, maximum: highest) : Column(minimum: 0, maximum: 0)
        }
    }

    /// `count` columns across the whole sound.
    public static func columns(of samples: SampleBuffer, count: Int) -> [Column] {
        columns(of: samples, frames: 0..<samples.frameCount, count: count)
    }
}
