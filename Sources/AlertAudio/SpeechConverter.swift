// Sources/AlertAudio/SpeechConverter.swift
// @preconcurrency: in the macOS 26.5 SDK (Xcode 26.6), AVAudioConverter's input block is
// @Sendable and AVAudioPCMBuffer is not Sendable, so returning a buffer from
// it is an error under -warnings-as-errors. The converter calls that block
// synchronously, on the calling thread, before convert returns, so the
// buffer never crosses a thread.
@preconcurrency import AVFoundation

/// Brings one utterance's buffers to `AlertPlayer.speechFormat`.
///
/// Apple's voices already render in it; Eloquence voices render at 16,000 Hz
/// (measured). One converter serves a whole utterance, so the resampler keeps
/// its state from buffer to buffer instead of clicking at every boundary.
/// Every buffer is copied, converted or not: the synthesizer's own may be
/// reused once its callback returns.
@MainActor
final class SpeechConverter {
    private var converter: AVAudioConverter?

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let target = AlertPlayer.speechFormat
        if Self.matches(buffer.format, target) { return copy(buffer) }
        if converter == nil { converter = AVAudioConverter(from: buffer.format, to: target) }
        guard let converter else { return nil }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }

    /// Whatever the resampler still holds at the end of the utterance.
    func flush() -> AVAudioPCMBuffer? {
        guard let converter,
              let output = AVAudioPCMBuffer(pcmFormat: AlertPlayer.speechFormat, frameCapacity: 1024) else { return nil }
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            status.pointee = .endOfStream
            return nil
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }

    private func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let out = AVAudioPCMBuffer(pcmFormat: AlertPlayer.speechFormat, frameCapacity: buffer.frameLength),
              let from = buffer.floatChannelData, let to = out.floatChannelData else { return nil }
        out.frameLength = buffer.frameLength
        to[0].update(from: from[0], count: Int(buffer.frameLength))
        return out
    }

    static func matches(_ a: AVAudioFormat, _ b: AVAudioFormat) -> Bool {
        a.commonFormat == b.commonFormat && a.sampleRate == b.sampleRate
            && a.channelCount == b.channelCount && a.isInterleaved == b.isInterleaved
    }
}

/// Set once. Guards a continuation that two callbacks race to resume, and
/// marks the first of a stream of buffers.
final class Flag {
    private(set) var isSet = false
    /// True the first time only.
    func set() -> Bool {
        if isSet { return false }
        isSet = true
        return true
    }
}
