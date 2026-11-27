import Foundation
@testable import NotificationCore

/// Sounds made to set off one check each, and a sound that sets off none, for the
/// tests of the checks and of the words that say what they found.
enum SoundFindingSamples {
    /// A tone that rises and falls over 50 ms at each end, peaking at 0.5: long
    /// enough, loud enough, not clipped and not abrupt.
    static func goodTone(frames: Int = 48_000) -> SampleBuffer {
        let ramp = Float(SampleBuffer.frames(seconds: 0.05))
        return SoundSignals.both(frames: frames) { index in
            let rise = min(1, Float(index) / ramp)
            let fall = min(1, Float(frames - 1 - index) / ramp)
            return 0.5 * rise * fall * Float(sin(2 * Double.pi * 440 * Double(index) / Double(SampleBuffer.sampleRate)))
        }
    }

    /// `silence` frames of nothing, then `sound`.
    static func silence(_ silence: Int, then sound: SampleBuffer) -> SampleBuffer {
        SampleBuffer(channels: sound.channels.map { Array(repeating: Float(0), count: silence) + $0 })!
    }

    /// `sound`, then `silence` frames of nothing.
    static func sound(_ sound: SampleBuffer, thenSilence silence: Int) -> SampleBuffer {
        SampleBuffer(channels: sound.channels.map { $0 + Array(repeating: Float(0), count: silence) })!
    }

    /// `quiet` for `lead` frames, then `loud`, in both channels, to the end of `frames`: the way
    /// in is a step, and where it is can be put at any frame.
    static func step(frames: Int, lead: Int, quiet: Float, loud: Float) -> SampleBuffer {
        SoundSignals.both(frames: frames) { $0 < lead ? quiet : loud }
    }

    /// A sound that sets off `kind`, and that is made so that nothing else is the matter with it
    /// when that can be had.
    static func setting(off kind: SoundFinding.Kind) -> SampleBuffer {
        switch kind {
        case .nothingToHear: return SoundSignals.constant(0, frames: 48_000)
        case .tooLong: return goodTone(frames: SoundRecipe.savableFrames + 1)
        case .startsAbruptly: return SoundSignals.constant(0.3, frames: 48_000)
        case .tooShort: return goodTone(frames: 9_600)
        case .silenceAtStart: return silence(9_600, then: goodTone())
        case .silenceAtEnd: return sound(goodTone(), thenSilence: 14_400)
        case .clipping:
            var tone = goodTone().channels
            for index in 20_000..<20_004 { tone[0][index] = 1 }
            return SampleBuffer(channels: tone)!
        }
    }
}
