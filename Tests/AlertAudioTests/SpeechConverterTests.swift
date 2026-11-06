import XCTest
import AVFoundation
@testable import AlertAudio

/// `SpeechConverter` on synthetic buffers, rendered offline: no voice, no
/// synthesizer and nothing that reaches a speaker.
@MainActor
final class SpeechConverterTests: XCTestCase {
    /// What an Eloquence voice renders in.
    private let sixteenKilohertz = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                                 channels: 1, interleaved: false)!

    private func tone(frames: Int, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<Int(format.channelCount) {
            for i in 0..<frames {
                buffer.floatChannelData![channel][i] = 0.5 * sin(Float(i) * 0.2)
            }
        }
        return buffer
    }

    /// A first buffer of 10 frames is below what the resampler needs to
    /// produce anything: that is priming, not a failure.
    func testAShortFirstBufferIsNotAFailure() {
        let converter = SpeechConverter()
        let converted = converter.convert(tone(frames: 10, format: sixteenKilohertz))
        XCTAssertNotNil(converted, "a converter that is still priming has not failed")
    }

    func testAnUtteranceThatBeginsWithAShortBufferConvertsInFull() throws {
        let converter = SpeechConverter()
        var frames = 0
        for count in [10, 1_600, 1_600, 400] {
            let converted = try XCTUnwrap(converter.convert(tone(frames: count, format: sixteenKilohertz)))
            frames += Int(converted.frameLength)
        }
        frames += Int(converter.flush()?.frameLength ?? 0)
        // 3,610 frames at 16,000 Hz are 4,975 at 22,050.
        XCTAssertEqual(Double(frames), 4_975, accuracy: 64)
    }

    func testABufferInTheTargetFormatIsCopiedWhole() throws {
        let converter = SpeechConverter()
        let source = tone(frames: 100, format: AlertPlayer.speechFormat)
        let converted = try XCTUnwrap(converter.convert(source))
        XCTAssertEqual(converted.frameLength, 100)
        XCTAssertFalse(converted === source)
    }

    // MARK: - What a calibration makes of them

    private func frames(_ count: AVAudioFrameCount) -> AVAudioPCMBuffer {
        tone(frames: Int(count), format: AlertPlayer.speechFormat)
    }

    func testAVoiceWhoseFirstBufferGaveNothingIsPlayableOnceLaterBuffersGiveFrames() {
        var tally = AlertPlayer.CalibrationTally()
        tally.add(peak: 0.5, converted: frames(0))
        tally.add(peak: 0.5, converted: frames(1_000))
        tally.add(flushed: nil)
        XCTAssertTrue(tally.isPlayable)
    }

    func testAVoiceWhoseFramesAllComeAtTheFlushIsPlayable() {
        var tally = AlertPlayer.CalibrationTally()
        tally.add(peak: 0.5, converted: frames(0))
        tally.add(flushed: frames(22))
        XCTAssertTrue(tally.isPlayable)
    }

    func testAVoiceThatGivesNoFramesOverTheWholeUtteranceIsUnplayable() {
        var tally = AlertPlayer.CalibrationTally()
        tally.add(peak: 0.5, converted: frames(0))
        tally.add(peak: 0.5, converted: frames(0))
        tally.add(flushed: nil)
        XCTAssertFalse(tally.isPlayable)
    }

    func testABufferThatCannotBeConvertedMakesTheVoiceUnplayable() {
        var tally = AlertPlayer.CalibrationTally()
        tally.add(peak: 0.5, converted: frames(1_000))
        tally.add(peak: 0.5, converted: nil)
        tally.add(peak: 0.5, converted: frames(1_000))
        XCTAssertFalse(tally.isPlayable, "an error is still a refusal, whatever else converted")
    }

    func testAVoiceMeasuredSilentIsUnplayable() {
        var tally = AlertPlayer.CalibrationTally()
        tally.add(peak: 0, converted: frames(1_000))
        XCTAssertFalse(tally.isPlayable)
        var quiet = AlertPlayer.CalibrationTally()
        quiet.add(peak: 0.0001, converted: frames(1_000))
        XCTAssertFalse(quiet.isPlayable, "-80 dBFS cannot be heard")
    }
}
