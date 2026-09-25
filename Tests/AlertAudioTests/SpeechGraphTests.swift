import XCTest
import AVFoundation
@testable import AlertAudio

/// The speech path through the graph, proven with synthetic buffers in
/// `speechFormat`: no voice is needed, and nothing reaches a speaker.
@MainActor
final class SpeechGraphTests: XCTestCase {
    private func player() -> AlertPlayer {
        AlertPlayer(library: SoundLibrary(customDirectory: FileManager.default.temporaryDirectory
                        .appendingPathComponent("SpeechGraphTests-\(UUID().uuidString)")),
                    readOutput: { OutputState(muted: false, volume: 0.5) }, mode: .offline)
    }

    private func dBFS(_ amplitude: Float) -> Double { 20 * log10(Double(max(amplitude, 1e-9))) }

    /// A 440 Hz tone standing in for speech.
    private func speech(seconds: Double, amplitude: Float = 0.5) -> AVAudioPCMBuffer {
        let format = AlertPlayer.speechFormat
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            buffer.floatChannelData![0][i] = amplitude * sin(2 * .pi * 440 * Float(i) / Float(format.sampleRate))
        }
        return buffer
    }

    func testSpeechReachesTheOutputAtItsOwnLevel() throws {
        let p = player()
        let play = try p.beginAlert(parts: 1, isAlert: true)
        p.scheduleSpeech(speech(seconds: 1), for: play)
        let (peak, over) = try p.renderOffline(seconds: 1)
        XCTAssertEqual(dBFS(peak), -6, accuracy: 1, "a 0.5 tone at unity gain")
        XCTAssertEqual(over, 0)
    }

    func testSpeechTakesItsOwnGain() throws {
        let p = player()
        p.setSpeechGain(-20)
        let play = try p.beginAlert(parts: 1, isAlert: true)
        p.scheduleSpeech(speech(seconds: 1), for: play)
        let (peak, _) = try p.renderOffline(seconds: 1)
        XCTAssertEqual(dBFS(peak), -26, accuracy: 1)
    }

    func testASoundAloneIsUnchangedByTheSpeechPath() throws {
        // The level tests in AlertPlayerTests cover every system sound; this
        // pins the one fact the new mixer could have broken.
        let p = player()
        try p.play(sound: "Glass", ruleGainDB: 0)
        let (peak, over) = try p.renderOffline(seconds: 3)
        XCTAssertEqual(dBFS(peak), -1, accuracy: 0.5)
        XCTAssertEqual(over, 0)
    }

    func testSoundAndSpeechTogetherStayUnderFullScale() throws {
        let p = player()
        let play = try p.beginAlert(parts: 2, isAlert: true)
        p.schedule(try p.resolve("Hero", ruleGainDB: 12), for: play)
        p.setSpeechGain(12)
        p.scheduleSpeech(speech(seconds: 2, amplitude: 0.9), for: play)
        let (_, over) = try p.renderOffline(seconds: 2)
        XCTAssertEqual(over, 0, "one limiter holds both")
    }

    func testOneAlertWithASoundAndSpeechClaimsTheGraphOnce() throws {
        let p = player()
        let before = p.generation
        let play = try p.beginAlert(parts: 2, isAlert: true)
        p.schedule(try p.resolve("Glass", ruleGainDB: 0), for: play)
        p.scheduleSpeech(speech(seconds: 1), for: play)
        XCTAssertEqual(p.generation, before + 1)
        let (peak, _) = try p.renderOffline(seconds: 1)
        XCTAssertGreaterThan(dBFS(peak), -3, "both parts are playing, neither cut off the other")
    }

    // MARK: - Interruption

    func testANewAlertStopsSpeechStillPlaying() throws {
        let p = player()
        let first = try p.beginAlert(parts: 1, isAlert: true)
        p.scheduleSpeech(speech(seconds: 3), for: first)
        XCTAssertGreaterThan(try p.renderOffline(seconds: 0.2).peak, 0.1)

        _ = try p.beginAlert(parts: 1, isAlert: true)
        _ = try p.renderOffline(seconds: 0.05)   // the limiter's look-ahead drains
        XCTAssertLessThan(try p.renderOffline(seconds: 0.5).peak, 0.001, "the earlier speech was cut off")
    }

    func testANewAlertStopsASoundStillPlaying() throws {
        let p = player()
        try p.play(sound: "Glass", ruleGainDB: 0)
        XCTAssertGreaterThan(try p.renderOffline(seconds: 0.2).peak, 0.1)

        _ = try p.beginAlert(parts: 1, isAlert: true)
        _ = try p.renderOffline(seconds: 0.05)   // the limiter's look-ahead drains
        XCTAssertLessThan(try p.renderOffline(seconds: 0.5).peak, 0.001, "the earlier sound was cut off")
    }

    func testSpeechArrivingForAnInterruptedAlertIsDropped() throws {
        let p = player()
        let first = try p.beginAlert(parts: 1, isAlert: true)
        _ = try p.beginAlert(parts: 1, isAlert: true)
        p.scheduleSpeech(speech(seconds: 1), for: first)
        p.endSpeech(for: first)
        XCTAssertLessThan(try p.renderOffline(seconds: 1).peak, 0.001)
    }

    func testAfterADeviceChangeEarlierSpeechIsDropped() throws {
        let p = player()
        let play = try p.beginAlert(parts: 1, isAlert: true)
        p.outputChanged()
        XCTAssertFalse(p.isPlayingAlert)
        _ = try p.beginAlert(parts: 1, isAlert: false)
        p.scheduleSpeech(speech(seconds: 1), for: play)
        XCTAssertLessThan(try p.renderOffline(seconds: 1).peak, 0.001)
    }

    // MARK: - When an alert is over

    func testAnAlertWithBothPartsEndsOnlyWhenBothHaveFinished() throws {
        let p = player()
        let play = try p.beginAlert(parts: 2, isAlert: true)
        p.finished(play)
        XCTAssertTrue(p.isPlayingAlert, "one part is still playing")
        p.finished(play)
        XCTAssertFalse(p.isPlayingAlert)
    }

    func testTheEndOfSpeechFinishesItsPartOnceItHasBeenHeard() throws {
        let p = player()
        let play = try p.beginAlert(parts: 1, isAlert: true)
        p.scheduleSpeech(speech(seconds: 0.5), for: play)
        p.endSpeech(for: play)
        XCTAssertTrue(p.isPlayingAlert)
        _ = try p.renderOffline(seconds: 1)
        let heard = expectation(for: NSPredicate { _, _ in !p.isPlayingAlert }, evaluatedWith: nil)
        wait(for: [heard], timeout: 3)
    }

    func testATestSoundIsStillRefusedWhileSpeechIsTheAlert() throws {
        let p = player()
        _ = try p.beginAlert(parts: 1, isAlert: true)
        XCTAssertThrowsError(try p.testSound("Glass", ruleGainDB: 0)) {
            XCTAssertEqual($0 as? AlertPlayer.Failure, .alertPlaying)
        }
    }
}
