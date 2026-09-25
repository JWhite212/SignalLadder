import XCTest
import AVFoundation
@testable import AlertAudio

/// The held synthesizer with real, installed voices. `write` renders without
/// speaking, and the player renders offline: nothing reaches a speaker.
/// Waits spin the main run loop, where the synthesizer calls back; blocking
/// it instead would deadlock.
@MainActor
final class SpeechSynthesisTests: XCTestCase {
    private let daniel = "com.apple.voice.compact.en-GB.Daniel"
    /// An Eloquence voice: it renders at 16,000 Hz, not speech's 22,050.
    private let eddy = "com.apple.eloquence.en-GB.Eddy"

    private func player() -> AlertPlayer {
        AlertPlayer(library: SoundLibrary(customDirectory: FileManager.default.temporaryDirectory
                        .appendingPathComponent("SpeechSynthesisTests-\(UUID().uuidString)")),
                    readOutput: { OutputState(muted: false, volume: 0.5) }, mode: .offline)
    }

    private func dBFS(_ amplitude: Float) -> Double { 20 * log10(Double(max(amplitude, 1e-9))) }

    private func installed(_ id: String) throws {
        try XCTSkipIf(AVSpeechSynthesisVoice(identifier: id) == nil, "voice \(id) is not installed on this Mac")
    }

    private func waitUntil(_ what: String, timeout: TimeInterval = 20, _ condition: @escaping () -> Bool) {
        let met = expectation(for: NSPredicate { _, _ in MainActor.assumeIsolated { condition() } }, evaluatedWith: nil)
        met.expectationDescription = what
        wait(for: [met], timeout: timeout)
    }

    /// The same, from an async test: a blocking wait there holds the main
    /// thread the synthesizer calls back on, and nothing ever arrives.
    private func waitUntil(_ what: String, timeout: TimeInterval = 20, _ condition: @escaping () -> Bool) async {
        let met = expectation(for: NSPredicate { _, _ in MainActor.assumeIsolated { condition() } }, evaluatedWith: nil)
        met.expectationDescription = what
        await fulfillment(of: [met], timeout: timeout)
    }

    /// Speaks, waits until every buffer has arrived, then renders the result.
    private func spokenPeak(_ p: AlertPlayer, _ text: String, voice: String, gain: Double = 0) async throws -> Float {
        try p.speak(text, voiceIdentifier: voice, rate: 0.5, pitchMultiplier: 1, ruleGainDB: gain)
        let play = p.generation
        await waitUntil("the speech has ended") { p.lastSpeechEnded == play }
        return try p.renderOffline(seconds: 6).peak
    }

    // MARK: - Level

    func testAMeasuredVoiceSpeaksAtTheSameLevelAsASound() async throws {
        try installed(daniel)
        let p = player()
        try await p.prepareSpeech(voiceIdentifier: daniel)
        let peak = try await spokenPeak(p, "Microsoft Teams: you were mentioned in All Hands", voice: daniel)
        XCTAssertEqual(dBFS(peak), -1, accuracy: 1.5, "level-matched like a sound at gain 0")
    }

    func testAnUnmeasuredVoiceSpeaksAtOnceAndNeverLouder() throws {
        try installed(daniel)
        let p = player()
        let report = try p.speak("Microsoft Teams: you were mentioned", voiceIdentifier: daniel,
                                 rate: 0.5, pitchMultiplier: 1, ruleGainDB: 0)
        XCTAssertFalse(report.calibrated)
        let play = p.generation
        waitUntil("the speech has ended") { p.lastSpeechEnded == play }
        let peak = try p.renderOffline(seconds: 5).peak
        XCTAssertLessThanOrEqual(dBFS(peak), -0.5, "errs quiet")
        XCTAssertGreaterThan(dBFS(peak), -6, "but is still clearly heard")
    }

    func testTheRulesGainAppliesToSpeech() async throws {
        try installed(daniel)
        let p = player()
        try await p.prepareSpeech(voiceIdentifier: daniel)
        let peak = try await spokenPeak(p, "Quieter now", voice: daniel, gain: -20)
        XCTAssertEqual(dBFS(peak), -21, accuracy: 1.5)
    }

    func testAVoiceThatRendersAtAnotherRateIsConvertedAndHeard() async throws {
        try installed(eddy)
        let p = player()
        try await p.prepareSpeech(voiceIdentifier: eddy)
        let peak = try await spokenPeak(p, "Converted from sixteen kilohertz", voice: eddy)
        XCTAssertEqual(dBFS(peak), -1, accuracy: 2)
    }

    // MARK: - Preparing

    func testAVoiceIsMeasuredOnce() async throws {
        try installed(daniel)
        let p = player()
        try await p.prepareSpeech(voiceIdentifier: daniel)
        try await p.prepareSpeech(voiceIdentifier: daniel)
        XCTAssertEqual(p.calibrationRenders, 1)
        XCTAssertNotNil(p.speechPeaks[daniel])
    }

    func testPreparingAVoiceAlreadyBeingMeasuredWaitsForThatMeasurement() async throws {
        try installed(daniel)
        let p = player()
        async let first: Void = p.prepareSpeech(voiceIdentifier: daniel)
        async let second: Void = p.prepareSpeech(voiceIdentifier: daniel)
        _ = try await (first, second)
        XCTAssertEqual(p.calibrationRenders, 1)
    }

    func testSpeakingAnUnmeasuredVoiceStartsItsMeasurement() throws {
        try installed(daniel)
        let p = player()
        try p.speak("Hello", voiceIdentifier: daniel, rate: 0.5, pitchMultiplier: 1, ruleGainDB: 0)
        let id = daniel
        waitUntil("the voice has been measured") { p.speechPeaks[id] != nil }
    }

    func testAnUnknownVoiceIsRefusedBeforeAnythingIsClaimed() async {
        let p = player()
        let before = p.generation
        XCTAssertThrowsError(try p.speak("x", voiceIdentifier: "com.example.gone", rate: 0.5, pitchMultiplier: 1, ruleGainDB: 0)) {
            XCTAssertEqual($0 as? AlertPlayer.Failure, .voiceNotFound("com.example.gone"))
        }
        XCTAssertEqual(p.generation, before, "whatever was playing was not cut off")
        do {
            try await p.prepareSpeech(voiceIdentifier: "com.example.gone")
            XCTFail("an unknown voice cannot be prepared")
        } catch {
            XCTAssertEqual(error as? AlertPlayer.Failure, .voiceNotFound("com.example.gone"))
        }
    }

    // MARK: - Test speech yields to alerts

    func testTestSpeechIsRefusedWhileAnAlertPlays() throws {
        try installed(daniel)
        let p = player()
        try p.play(sound: "Glass", ruleGainDB: 0)
        XCTAssertThrowsError(try p.testSpeech("x", voiceIdentifier: daniel, rate: 0.5, pitchMultiplier: 1, ruleGainDB: 0)) {
            XCTAssertEqual($0 as? AlertPlayer.Failure, .alertPlaying)
        }
    }

    func testAnAlertCutsOffTestSpeech() throws {
        try installed(daniel)
        let p = player()
        try p.testSpeech("A long sentence to be cut off part of the way through", voiceIdentifier: daniel,
                         rate: 0.5, pitchMultiplier: 1, ruleGainDB: 0)
        let test = p.generation
        try p.play(sound: "Glass", ruleGainDB: 0)
        XCTAssertTrue(p.isPlayingAlert)
        XCTAssertNotEqual(p.generation, test, "the test's remaining speech is disowned")
    }

    // MARK: - Sound and speech together

    func testASoundAndSpeechAlertClaimsTheGraphOnceAndPlaysBoth() throws {
        try installed(daniel)
        let p = player()
        let before = p.generation
        let report = p.playAndSpeak(sound: "Glass", soundGainDB: 0, text: "Glass, then this", voiceIdentifier: daniel,
                                    rate: 0.5, pitchMultiplier: 1, speechGainDB: 0)
        XCTAssertEqual(p.generation, before + 1)
        XCTAssertEqual(try report.sound.get().sound, "Glass")
        XCTAssertEqual(try report.speech.get().voiceName, "Daniel")
        let play = p.generation
        waitUntil("the speech has ended") { p.lastSpeechEnded == play }
        XCTAssertTrue(p.isPlayingAlert, "the sound part has not finished yet")
        XCTAssertLessThan(dBFS(try p.renderOffline(seconds: 5).peak), 0.01)
    }

    func testAMissingVoiceDoesNotSilenceTheSound() throws {
        let p = player()
        let report = p.playAndSpeak(sound: "Glass", soundGainDB: 0, text: "x", voiceIdentifier: "com.example.gone",
                                    rate: 0.5, pitchMultiplier: 1, speechGainDB: 0)
        XCTAssertEqual(try report.sound.get().sound, "Glass")
        XCTAssertEqual(report.speech, .failure(.voiceNotFound("com.example.gone")))
        XCTAssertEqual(dBFS(try p.renderOffline(seconds: 3).peak), -1, accuracy: 0.5)
    }

    func testAMissingSoundDoesNotSilenceTheSpeech() throws {
        try installed(daniel)
        let p = player()
        let report = p.playAndSpeak(sound: "Nope", soundGainDB: 0, text: "Still said", voiceIdentifier: daniel,
                                    rate: 0.5, pitchMultiplier: 1, speechGainDB: 0)
        XCTAssertEqual(report.sound, .failure(.soundNotFound("Nope")))
        XCTAssertEqual(try report.speech.get().voiceName, "Daniel")
        let play = p.generation
        waitUntil("the speech has ended") { p.lastSpeechEnded == play }
        XCTAssertGreaterThan(try p.renderOffline(seconds: 5).peak, 0.1)
    }

    func testWhenBothPartsAreMissingNothingIsClaimed() {
        let p = player()
        let before = p.generation
        let report = p.playAndSpeak(sound: "Nope", soundGainDB: 0, text: "x", voiceIdentifier: "com.example.gone",
                                    rate: 0.5, pitchMultiplier: 1, speechGainDB: 0)
        XCTAssertEqual(report.sound, .failure(.soundNotFound("Nope")))
        XCTAssertEqual(report.speech, .failure(.voiceNotFound("com.example.gone")))
        XCTAssertEqual(p.generation, before)
    }

    // MARK: - What a spoken alert leaves behind

    func testEachSpokenAlertReportsItsLatencyAndNothingElse() throws {
        try installed(daniel)
        let p = player()
        var reported: [(Double, Bool)] = []
        p.onSpeechLatency = { reported.append(($0, $1)) }
        try p.speak("Latency only", voiceIdentifier: daniel, rate: 0.5, pitchMultiplier: 1, ruleGainDB: 0)
        let play = p.generation
        waitUntil("the speech has ended") { p.lastSpeechEnded == play }
        XCTAssertEqual(reported.count, 1)
        XCTAssertGreaterThan(reported.first?.0 ?? 0, 0)
        XCTAssertEqual(reported.first?.1, false, "this voice had not been measured yet")
    }
}
