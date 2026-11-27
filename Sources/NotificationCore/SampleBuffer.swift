// Sources/NotificationCore/SampleBuffer.swift
import Foundation

/// Audio as plain numbers: one array of samples for each channel, at 48 kHz.
///
/// This is how a sound crosses between `AlertAudio`, which reads and writes
/// files, and the core, which may touch neither files nor audio hardware: no
/// `AVAudioPCMBuffer` leaves the function that made it (sound editor plan,
/// Ruling 5). It is a value of `Float`s and so `Sendable`, which is what lets a
/// render run off the main actor and hand its result back.
///
/// Every channel is the same length, held by construction: the initialiser
/// refuses what is not, so nothing downstream has to ask.
public struct SampleBuffer: Equatable, Sendable {
    /// The one rate every sound in the editor is counted in. The player's own
    /// format is 48 kHz stereo float, and a position in a recipe is a whole
    /// number of frames of it (Ruling 3).
    public static let sampleRate = 48_000

    /// Each channel's samples, in order.
    public let channels: [[Float]]

    /// nil when there are no channels or the channels are not all the same
    /// length. A buffer with no frames is allowed.
    public init?(channels: [[Float]]) {
        guard let first = channels.first, channels.allSatisfy({ $0.count == first.count }) else { return nil }
        self.channels = channels
    }

    /// `frames` of nothing, in `channelCount` channels (stereo unless said).
    public static func silence(frames: Int, channelCount: Int = 2) -> SampleBuffer {
        let count = max(channelCount, 1)
        return SampleBuffer(channels: Array(repeating: Array(repeating: 0, count: max(frames, 0)), count: count))!
    }

    public var channelCount: Int { channels.count }

    /// The number of frames: samples in any one channel.
    public var frameCount: Int { channels[0].count }

    public var isEmpty: Bool { frameCount == 0 }

    public var duration: TimeInterval { SampleBuffer.seconds(frames: frameCount) }

    /// The largest absolute sample in any channel, which is what the player
    /// measures a sound's loudness by. 0 for an empty buffer. A sample that is
    /// not a number is passed over rather than allowed to make the answer one.
    public var peak: Float {
        var peak: Float = 0
        for channel in channels {
            for sample in channel where sample.isFinite {
                peak = max(peak, abs(sample))
            }
        }
        return peak
    }

    /// Whole frames in a time, rounded to the nearest. The only place a time
    /// becomes a position, so no two reads of one value can differ by rounding.
    /// A time too long to count is counted as a very long one, far past the
    /// longest sound a recipe holds, and not as a trap.
    public static func frames(seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(min((seconds * Double(sampleRate)).rounded(), 1e15))
    }

    public static func seconds(frames: Int) -> TimeInterval {
        TimeInterval(frames) / TimeInterval(sampleRate)
    }
}
