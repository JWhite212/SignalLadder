import XCTest
import AVFoundation
@testable import AlertAudio

/// Every test renders the real player graph offline: the audio is measured,
/// and nothing reaches a speaker.
@MainActor
final class AlertPlayerTests: XCTestCase {
    private var custom: URL!

    override func setUpWithError() throws {
        custom = FileManager.default.temporaryDirectory.appendingPathComponent("AlertPlayerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: custom)
    }

    private func player(output: OutputState = OutputState(muted: false, volume: 0.5)) -> AlertPlayer {
        AlertPlayer(library: SoundLibrary(customDirectory: custom), readOutput: { output }, mode: .offline)
    }

    private func dBFS(_ amplitude: Float) -> Double { 20 * log10(Double(max(amplitude, 1e-9))) }

    private var systemSounds: [String] {
        SoundLibrary(customDirectory: custom).availableNames.sorted()
    }

    // MARK: - Level matching, measured on the rendered output

    func testEverySystemSoundPeaksAtTheSameLevelAtGainZero() throws {
        // Their raw peaks span 10 dB (Frog −15, Hero −5). At gain 0 they must
        // come out of the graph within half a decibel of each other.
        XCTAssertGreaterThanOrEqual(systemSounds.count, 10, "expected the macOS system sounds")
        for name in systemSounds {
            let p = player()
            try p.play(sound: name, ruleGainDB: 0)
            let (peak, over) = try p.renderOffline(seconds: 4)
            XCTAssertEqual(dBFS(peak), -1, accuracy: 0.5, "\(name) peaked at \(dBFS(peak)) dBFS")
            XCTAssertEqual(over, 0, name)
        }
    }

    func testAtMaximumGainTheLimiterHoldsEverySoundUnderFullScale() throws {
        for name in systemSounds {
            let p = player()
            try p.play(sound: name, ruleGainDB: 12)
            let (peak, over) = try p.renderOffline(seconds: 4)
            XCTAssertEqual(over, 0, "\(name): \(over) samples over full scale at +12 dB")
            XCTAssertLessThanOrEqual(peak, 1.0, name)
        }
    }

    func testMinimumGainLandsFortyDecibelsDown() throws {
        let p = player()
        try p.play(sound: "Glass", ruleGainDB: -40)
        let (peak, _) = try p.renderOffline(seconds: 3)
        XCTAssertEqual(dBFS(peak), -41, accuracy: 0.5)
    }

    // MARK: - Nothing is reported as played unless it could be heard

    func testAnUnknownSoundThrowsRatherThanPlayingNothing() {
        XCTAssertThrowsError(try player().play(sound: "Glas", ruleGainDB: 0)) {
            XCTAssertEqual($0 as? AlertPlayer.Failure, .soundNotFound("Glas"))
        }
    }

    func testAnUnreadableFileThrows() throws {
        try Data("not audio".utf8).write(to: custom.appendingPathComponent("Broken.aiff"))
        XCTAssertThrowsError(try player().play(sound: "Broken", ruleGainDB: 0)) {
            guard case AlertPlayer.Failure.unreadable(let sound, _)? = $0 as? AlertPlayer.Failure else {
                return XCTFail("expected unreadable, got \($0)")
            }
            XCTAssertEqual(sound, "Broken")
        }
    }

    func testASilentFileThrowsRatherThanReportingItPlayed() throws {
        // A file of zeros would "play" perfectly and nobody would hear it.
        let url = custom.appendingPathComponent("Nothing.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let zeros = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        zeros.frameLength = 44_100
        try file.write(from: zeros)

        XCTAssertThrowsError(try player().play(sound: "Nothing", ruleGainDB: 12)) {
            XCTAssertEqual($0 as? AlertPlayer.Failure, .silent("Nothing"))
        }
    }

    func testALongFileIsRefusedBeforeItIsDecoded() throws {
        // A recording dropped into the Sounds folder by mistake would be
        // decoded whole into memory at the moment of an incident.
        let url = custom.appendingPathComponent("Podcast.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(8_000 * (AlertPlayer.maximumSeconds + 1))
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        try file.write(from: buffer)

        XCTAssertThrowsError(try player().play(sound: "Podcast", ruleGainDB: 0)) {
            XCTAssertEqual($0 as? AlertPlayer.Failure, .tooLong("Podcast"))
        }
        XCTAssertEqual(AlertPlayer.Failure.tooLong("Podcast").description, "sound \"Podcast\" is longer than 30 seconds")
    }

    // MARK: - Preparing sounds when the rules load

    /// A second of 440 Hz at half scale: loud enough to pass, quiet enough
    /// that level-matching has work to do.
    private func writeTone(_ name: String) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: custom.appendingPathComponent("\(name).caf"), settings: format.settings)
        let tone = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        tone.frameLength = 44_100
        for i in 0..<44_100 { tone.floatChannelData![0][i] = 0.5 * sin(2 * .pi * 440 * Float(i) / 44_100) }
        try file.write(from: tone)
    }

    private func writeSilence(_ name: String) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: custom.appendingPathComponent("\(name).caf"), settings: format.settings)
        let zeros = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        zeros.frameLength = 44_100
        try file.write(from: zeros)
    }

    func testPreparingRefusesWhatPlayingWould() throws {
        try writeSilence("Nothing")
        let p = player()
        XCTAssertNoThrow(try p.prepare(sound: "glass"))
        XCTAssertThrowsError(try p.prepare(sound: "Glas")) { XCTAssertEqual($0 as? AlertPlayer.Failure, .soundNotFound("Glas")) }
        XCTAssertThrowsError(try p.prepare(sound: "Nothing")) { XCTAssertEqual($0 as? AlertPlayer.Failure, .silent("Nothing")) }
    }

    func testForgettingPreparedSoundsRereadsAFileChangedOnDisk() throws {
        try writeTone("Pager")
        let p = player()
        try p.prepare(sound: "Pager")

        try FileManager.default.removeItem(at: custom.appendingPathComponent("Pager.caf"))
        try writeSilence("Pager")
        XCTAssertNoThrow(try p.prepare(sound: "Pager"), "without forgetting, the decoded copy is kept")

        p.forgetPreparedSounds()
        XCTAssertThrowsError(try p.prepare(sound: "Pager"), "a reload must see the file as it is now") {
            XCTAssertEqual($0 as? AlertPlayer.Failure, .silent("Pager"))
        }
    }

    // MARK: - A change of output device

    func testAfterADeviceChangeTheNextAlertPlaysNormally() throws {
        let p = player()
        try p.play(sound: "Glass", ruleGainDB: 0)
        p.outputChanged()
        XCTAssertFalse(p.engine.isRunning, "reset to the state between alerts")

        try p.play(sound: "Glass", ruleGainDB: 0)
        let (peak, _) = try p.renderOffline(seconds: 3)
        XCTAssertEqual(dBFS(peak), -1, accuracy: 0.5, "the alert after a device change must be heard like any other")
    }

    func testTheEnginesChangeNotificationTriggersTheReset() throws {
        let p = player()
        try p.play(sound: "Glass", ruleGainDB: 0)
        XCTAssertTrue(p.engine.isRunning)

        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: p.engine)
        let reset = expectation(description: "reset on the main actor")
        DispatchQueue.main.async { reset.fulfill() }
        wait(for: [reset], timeout: 2)

        XCTAssertFalse(p.engine.isRunning)
    }

    // MARK: - The report

    func testTheReportNamesTheSoundAsTheLibraryKnowsIt() throws {
        let report = try player().play(sound: "glass", ruleGainDB: 3)
        XCTAssertEqual(report.sound, "Glass")
    }

    func testTheReportCarriesTheOutputStateAtThatMoment() throws {
        let muted = OutputState(muted: true, volume: 0.8)
        let report = try player(output: muted).play(sound: "Glass", ruleGainDB: 0)
        XCTAssertEqual(report.output, muted)
        XCTAssertTrue(report.output.isEffectivelySilent)
    }

    func testTheReportedGainIsLevelMatchingPlusTheRulesGain() throws {
        // Glass peaks near −14 dBFS, so reaching −1 needs about +13; with a
        // rule gain of +3 the applied total is about +16.
        let report = try player().play(sound: "Glass", ruleGainDB: 3)
        XCTAssertEqual(report.appliedGainDB, 16, accuracy: 1.5)
    }

    // MARK: - The outcome the Inspector records

    func testAnOutcomeRecordsTheRulesGainNotTheLevelMatchingBeneathIt() {
        XCTAssertEqual(player().outcome(ofPlaying: "glass", ruleGainDB: 3),
                       .played(sound: "Glass", gainDB: 3, outputSilent: false),
                       "the user chose +3; the +13 of level-matching is the app's business")
    }

    func testAnOutcomeSaysWhenTheOutputCouldNotBeHeard() {
        XCTAssertEqual(player(output: OutputState(muted: false, volume: 0)).outcome(ofPlaying: "Glass", ruleGainDB: 0),
                       .played(sound: "Glass", gainDB: 0, outputSilent: true))
    }

    func testAnOutcomeRecordsAFailureInsteadOfThrowing() {
        XCTAssertEqual(player().outcome(ofPlaying: "Glas", ruleGainDB: 0),
                       .failed("sound \"Glas\" was not found"))
    }
}

final class OutputStateTests: XCTestCase {
    func testMutedIsSilent() {
        XCTAssertTrue(OutputState(muted: true, volume: 1).isEffectivelySilent)
    }

    func testVolumeAtZeroIsSilent() {
        XCTAssertTrue(OutputState(muted: false, volume: 0).isEffectivelySilent)
        XCTAssertTrue(OutputState(muted: false, volume: 0.01).isEffectivelySilent)
    }

    func testAudibleVolumeIsNotSilent() {
        XCTAssertFalse(OutputState(muted: false, volume: 0.06).isEffectivelySilent)
    }

    func testUnknownIsNotReportedAsSilent() {
        // Claiming the output was muted when it may not have been is the same
        // error as claiming an alert was heard, in the opposite direction.
        XCTAssertFalse(OutputState(muted: nil, volume: nil).isEffectivelySilent)
    }

    func testTheRealDeviceCanBeRead() {
        // Smoke test: reading the default output device must not crash, and on
        // a Mac with built-in audio it reports at least one of the two.
        let state = OutputState.current()
        XCTAssertTrue(state.muted != nil || state.volume != nil, "no output state could be read: \(state)")
    }
}
