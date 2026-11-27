import Foundation
@testable import NotificationCore

/// Signals made from arithmetic, for the tests of rendering, snapping and the
/// drawing's numbers: a sound whose every sample is known can be checked
/// against what it should come to, and no file is read.
enum SoundSignals {
    /// A sine of `hz` at `amplitude`, the same in each of `channels`.
    static func sine(frames: Int, hz: Double, amplitude: Float = 0.8, channels: Int = 2) -> SampleBuffer {
        let rate = Double(SampleBuffer.sampleRate)
        let samples = (0..<frames).map { Float(Double(amplitude) * sin(2 * Double.pi * hz * Double($0) / rate)) }
        return SampleBuffer(channels: Array(repeating: samples, count: channels))!
    }

    /// `value` in every sample of each of `channels`.
    static func constant(_ value: Float, frames: Int, channels: Int = 2) -> SampleBuffer {
        SampleBuffer(channels: Array(repeating: Array(repeating: value, count: frames), count: channels))!
    }

    /// Two channels, each made of what `left` and `right` say of its frame.
    static func stereo(frames: Int, left: (Int) -> Float, right: (Int) -> Float) -> SampleBuffer {
        SampleBuffer(channels: [(0..<frames).map(left), (0..<frames).map(right)])!
    }

    /// The same samples in both channels.
    static func both(frames: Int, _ sample: (Int) -> Float) -> SampleBuffer {
        stereo(frames: frames, left: sample, right: sample)
    }

    /// The largest step from one sample of a channel to the next, over `frames`.
    static func largestStep(_ buffer: SampleBuffer, in frames: Range<Int>, channel: Int = 0) -> Float {
        var largest: Float = 0
        let samples = buffer.channels[channel]
        for index in max(frames.lowerBound, 1)..<min(frames.upperBound, samples.count) {
            largest = max(largest, abs(samples[index] - samples[index - 1]))
        }
        return largest
    }
}
