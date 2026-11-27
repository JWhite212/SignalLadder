// Sources/AlertAudio/SoundDecoding.swift
// @preconcurrency: see AlertPlayer.swift. The converter calls its input block
// synchronously, on the calling thread, before `convert` returns, so the
// buffer it is handed never crosses a thread.
@preconcurrency import AVFoundation
import Foundation
import NotificationCore

/// Reads a sound file whole and brings it to the one format the player plays in:
/// 48 kHz, stereo, float (sound editor plan, Ruling 3).
///
/// This is what `AlertPlayer` did to every sound it loaded, taken out so that the
/// player and the sound editor decode alike: what the editor shows and edits is
/// exactly the audio an alert would play. The player's own words for a sound that
/// cannot be read are made from `Failure`, so they do not change.
///
/// Nothing here belongs to the main actor. The player calls it on the main actor,
/// as it always did, where an alert would otherwise wait on it; the editor calls it
/// from a task of its own, for a sound that may be long, and gets back plain
/// samples, so that no audio buffer crosses to the window (Ruling 5).
public enum SoundDecoding {
    /// What can be the matter with a file. The words a person reads for each are
    /// the player's, and the editor's, not these.
    public enum Failure: Error, Equatable, Sendable {
        /// Longer than the limit it was asked to hold to, which is the file's own
        /// length in seconds, before any of it was read.
        case tooLong(seconds: Double)
        /// Anything else, with the reason the system or this type gave.
        case unreadable(String)
    }

    /// The one format every sound is converted to: the player's graph is connected
    /// to it once.
    static let format = AVAudioFormat(standardFormatWithSampleRate: Double(SampleBuffer.sampleRate), channels: 2)!

    /// The whole file, converted, for the player. Decoded size is not limited unless
    /// `maximumDecodedBytes` says so, which only the editor does: a sound the player
    /// is given has been checked when it was added.
    static func decode(_ url: URL, maximumSeconds: Double, maximumDecodedBytes: Int64? = nil) throws -> AVAudioPCMBuffer {
        do {
            let file = try AVAudioFile(forReading: url)
            let rate = file.processingFormat.sampleRate
            guard Double(file.length) <= maximumSeconds * rate else {
                throw Failure.tooLong(seconds: Double(file.length) / rate)
            }
            if let limit = maximumDecodedBytes,
               file.length * Int64(file.processingFormat.channelCount) * 4 > limit {
                throw Failure.unreadable("it holds more audio than can be edited")
            }
            guard let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
                throw Failure.unreadable("it is empty")
            }
            try file.read(into: source)
            return try convert(source)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.unreadable(error.localizedDescription)
        }
    }

    /// The whole file as plain samples, for the editor.
    public static func samples(of url: URL, maximumSeconds: Double, maximumDecodedBytes: Int64? = nil) throws -> SampleBuffer {
        let buffer = try decode(url, maximumSeconds: maximumSeconds, maximumDecodedBytes: maximumDecodedBytes)
        guard let data = buffer.floatChannelData else { throw Failure.unreadable("its format cannot be converted") }
        let frames = Int(buffer.frameLength)
        let channels = (0..<Int(buffer.format.channelCount)).map { channel in
            Array(UnsafeBufferPointer(start: data[channel], count: frames))
        }
        guard let samples = SampleBuffer(channels: channels) else { throw Failure.unreadable("its format cannot be converted") }
        return samples
    }

    private static func convert(_ source: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let converter = AVAudioConverter(from: source.format, to: format) else {
            throw Failure.unreadable("its format cannot be converted")
        }
        let ratio = format.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw Failure.unreadable("no buffer for conversion")
        }
        var supplied = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return source
        }
        if let conversionError { throw Failure.unreadable(conversionError.localizedDescription) }
        return output
    }
}
