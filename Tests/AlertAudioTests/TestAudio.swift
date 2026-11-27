import AVFoundation
import Foundation

/// Real audio files for the tests that read and write the sounds folder.
enum TestAudio {
    /// A sine written to `url`, as the type its extension says, and the file's format as `settings` makes it
    /// unless the caller gives its own.
    @discardableResult
    static func write(_ url: URL, seconds: Double = 0.5, rate: Double = 8_000, channels: AVAudioChannelCount = 1,
                      amplitude: Float = 0.5, step: Float = 0.3) throws -> URL {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
        let frames = AVAudioFrameCount(seconds * rate)
        guard frames > 0 else {
            _ = try AVAudioFile(forWriting: url, settings: format.settings)
            return url
        }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            for i in 0..<Int(frames) { buffer.floatChannelData![channel][i] = amplitude * sin(Float(i) * step) }
        }
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
        return url
    }
}
