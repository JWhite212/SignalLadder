import XCTest
import AVFoundation
import NotificationCore
@testable import AlertAudio

/// What the sound editor hears through `testBuffer`, rendered through the real graph offline, as
/// `AlertPlayerTests` renders an alert: the audio is measured and nothing reaches a speaker.
@MainActor
final class AlertPlayerPreviewTests: XCTestCase {
    private var custom: URL!

    override func setUpWithError() throws {
        custom = FileManager.default.temporaryDirectory.appendingPathComponent("AlertPlayerPreviewTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: custom)
    }

    private func player(output: OutputState = OutputState(muted: false, volume: 0.5)) -> AlertPlayer {
        AlertPlayer(library: SoundLibrary(customDirectory: custom), readOutput: { output }, mode: .offline)
    }

    private func dBFS(_ amplitude: Float) -> Double { 20 * log10(Double(max(amplitude, 1e-9))) }

    private let rate = SampleBuffer.sampleRate

    // MARK: - Signals

    /// A 440 Hz sine, `frames` long, at `amplitude`.
    private func sine(_ frames: Int, _ amplitude: Float) -> [Float] {
        (0..<frames).map { amplitude * sin(2 * .pi * 440 * Float($0) / Float(rate)) }
    }

    private func nothing(_ frames: Int) -> [Float] { Array(repeating: 0, count: frames) }

    /// The same samples in both channels.
    private func stereo(_ parts: [Float]...) -> SampleBuffer {
        let samples = Array(parts.joined())
        return SampleBuffer(channels: [samples, samples])!
    }

    private func gainForAnAlert(of sound: SampleBuffer) -> Double {
        Loudness.appliedGainDB(forPeak: sound.peak, ruleGainDB: 0)!
    }

    /// A sound the library can play, written as a WAV of the player's own format, so that what an alert plays is
    /// the very samples a preview is given.
    private func write(_ sound: SampleBuffer, as name: String) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: AVAudioChannelCount(sound.channelCount))!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sound.frameCount))!
        buffer.frameLength = AVAudioFrameCount(sound.frameCount)
        for (channel, samples) in sound.channels.enumerated() {
            for (i, sample) in samples.enumerated() { buffer.floatChannelData![channel][i] = sample }
        }
        try AVAudioFile(forWriting: custom.appendingPathComponent("\(name).caf"), settings: format.settings).write(from: buffer)
    }

    /// One second of 440 Hz at half scale, as a sound an alert can play.
    private func writeTone(_ name: String) throws {
        try write(stereo(sine(rate, 0.5)), as: name)
    }

    /// What the graph puts out, in consecutive slices of `blocks` blocks of 4096 frames, which is 0.256 seconds
    /// for the three of a default slice: each slice's peak, and how many of the samples were not numbers. It is
    /// rendered in whole blocks, the most the engine is asked for at a time, since a render of fewer was seen to
    /// leave the sound later than the frames delivered say, and every position below is counted in them.
    /// The graph's limiter holds what it passes back by 96 frames (measured), so a sound's last frames are heard
    /// in the block after it, and the tests look for silence a block on.
    private func rendered(_ p: AlertPlayer, slices: Int, blocks: Int = 3) throws -> (peaks: [Float], notNumbers: Int) {
        let out = AVAudioPCMBuffer(pcmFormat: p.engine.manualRenderingFormat, frameCapacity: 4096)!
        var peaks: [Float] = []
        var notNumbers = 0
        for _ in 0..<slices {
            var peak: Float = 0
            for _ in 0..<blocks {
                guard try p.engine.renderOffline(4096, to: out) == .success else { break }
                for channel in 0..<Int(out.format.channelCount) {
                    for i in 0..<Int(out.frameLength) {
                        let sample = out.floatChannelData![channel][i]
                        if sample.isFinite { peak = max(peak, abs(sample)) } else { notNumbers += 1 }
                    }
                }
            }
            peaks.append(peak)
        }
        return (peaks, notNumbers)
    }

    /// Gives the player's completions, which hop to the main queue, the turn they need.
    private func waitUntil(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    // MARK: - A preview is refused while an alert plays, and an alert stops a preview

    func testAPreviewIsRefusedWhileAnAlertPlays() throws {
        try writeTone("Pager")
        let p = player()
        try p.play(sound: "Pager", ruleGainDB: 0)
        let alert = p.generation
        XCTAssertThrowsError(try p.testBuffer(stereo(sine(rate, 0.5)), gainDB: 0)) {
            XCTAssertEqual($0 as? AlertPlayer.Failure, .alertPlaying)
        }
        XCTAssertEqual(p.generation, alert, "nothing was scheduled over the alert")
        XCTAssertTrue(p.isPlayingAlert)
        XCTAssertFalse(p.isPreviewing)
        let (peaks, _) = try rendered(p, slices: 4)
        XCTAssertEqual(dBFS(peaks.max()!), -1, accuracy: 0.5, "the alert is heard whole, at its own level")
    }

    func testAnAlertStartingStopsAPreviewAndItsLoop() throws {
        try writeTone("Pager")
        let p = player()
        try p.testBuffer(stereo(sine(rate / 2, 0.5)), gainDB: 6, loop: 0..<4_800)
        XCTAssertTrue(p.isPreviewing)

        try p.play(sound: "Pager", ruleGainDB: 0)
        XCTAssertFalse(p.isPreviewing)
        XCTAssertNil(p.previewFrame)
        XCTAssertTrue(p.isPlayingAlert)

        // The alert is a second long. Were the loop still going it would be heard after it.
        let (peaks, _) = try rendered(p, slices: 8)
        XCTAssertEqual(dBFS(Array(peaks[0..<4]).max()!), -1, accuracy: 0.5, "the alert is heard")
        XCTAssertEqual(Array(peaks[4..<8]).max()!, 0, "the loop is not")
    }

    func testAPreviewIsNotTakenForAnAlert() throws {
        let p = player()
        try p.testBuffer(stereo(sine(rate, 0.5)), gainDB: 0)
        XCTAssertTrue(p.isPreviewing)
        XCTAssertFalse(p.isPlayingAlert, "an alert may start at once, and a second test may too")
        XCTAssertNoThrow(try p.testBuffer(stereo(sine(rate, 0.5)), gainDB: 0))
    }

    func testATestSoundCutsOffAPreviewAsAnAlertDoes() throws {
        let p = player()
        try p.testBuffer(stereo(sine(rate, 0.5)), gainDB: 0)
        try p.testSound("Glass", ruleGainDB: 0)
        XCTAssertFalse(p.isPreviewing)
    }

    // MARK: - stopTest

    func testStopTestStopsAPreviewAndTheEngine() throws {
        let p = player()
        try p.testBuffer(stereo(sine(rate, 0.5)), gainDB: 0, loop: 0..<4_800)
        XCTAssertTrue(p.engine.isRunning)

        p.stopTest()
        XCTAssertFalse(p.isPreviewing)
        XCTAssertNil(p.previewFrame)
        XCTAssertFalse(p.isPlayingAlert)
        XCTAssertFalse(p.engine.isRunning, "the state between alerts")
    }

    func testAnAlertAfterAStoppedPreviewIsHeardNormally() throws {
        try writeTone("Pager")
        let p = player()
        try p.testBuffer(stereo(sine(rate, 0.5)), gainDB: -30, loop: 0..<4_800)
        p.stopTest()
        try p.play(sound: "Pager", ruleGainDB: 0)
        let (peaks, _) = try rendered(p, slices: 4)
        XCTAssertEqual(dBFS(peaks.max()!), -1, accuracy: 0.5)
    }

    func testStopTestDuringAnAlertLeavesTheAlertWhole() throws {
        try writeTone("Pager")
        let p = player()
        try p.play(sound: "Pager", ruleGainDB: 0)
        let alert = p.generation

        p.stopTest()
        XCTAssertTrue(p.isPlayingAlert)
        XCTAssertEqual(p.generation, alert, "nothing was disowned")
        XCTAssertTrue(p.engine.isRunning)
        let (peaks, _) = try rendered(p, slices: 4)
        XCTAssertGreaterThan(peaks.min()!, 0.5, "every part of the alert is heard")
    }

    func testStopTestLeavesATestSoundAlone() throws {
        let p = player()
        try p.testSound("Glass", ruleGainDB: 0)
        let play = p.generation

        p.stopTest()
        XCTAssertEqual(p.generation, play)
        XCTAssertTrue(p.engine.isRunning)
    }

    func testStopTestWithNothingPlayingChangesNothing() {
        let p = player()
        let before = p.generation
        p.stopTest()
        XCTAssertEqual(p.generation, before)
        XCTAssertFalse(p.engine.isRunning)
    }

    func testAPreviewThatHasEndedIsNoLongerPreviewing() throws {
        let p = player()
        try p.testBuffer(stereo(sine(4_800, 0.5)), gainDB: 0)
        XCTAssertTrue(p.isPreviewing)
        _ = try rendered(p, slices: 2)
        waitUntil { !p.isPreviewing }
        XCTAssertFalse(p.isPreviewing)
        XCTAssertNil(p.previewFrame)
        XCTAssertFalse(p.isPlayingAlert)
    }

    func testALoopIsNeverOver() throws {
        let p = player()
        try p.testBuffer(stereo(sine(rate, 0.5)), gainDB: 0, loop: 0..<4_800)
        _ = try rendered(p, slices: 8)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertTrue(p.isPreviewing, "it goes on until it is stopped")
    }

    func testASecondPreviewTakesTheFirstsPlace() throws {
        let p = player()
        let sound = stereo(sine(rate, 0.5))
        try p.testBuffer(sound, gainDB: 0, from: 0)
        let first = p.generation
        try p.testBuffer(sound, gainDB: 0, from: 12_000)
        XCTAssertNotEqual(p.generation, first)
        XCTAssertTrue(p.isPreviewing)
        XCTAssertEqual(p.previewFrame, 12_000)
    }

    // MARK: - Level: a preview is as loud as the sound is as an alert

    func testAQuietPartOfALoudSoundIsHeardAsQuietAsItIsInTheWhole() throws {
        // A second at 0.9 and a second at a tenth of that, 20 dB down. The alert's level is worked out from
        // the 0.9, and the quiet part is played at that: not raised to a peak of its own.
        let whole = stereo(sine(rate, 0.9), sine(rate, 0.09))
        let gain = gainForAnAlert(of: whole)

        let wholePlayer = player()
        try wholePlayer.testBuffer(whole, gainDB: gain)
        let heardWhole = try rendered(wholePlayer, slices: 8)
        XCTAssertEqual(dBFS(heardWhole.peaks.max()!), -1, accuracy: 0.5, "the whole is at an alert's level")
        XCTAssertEqual(dBFS(Array(heardWhole.peaks[4..<8]).max()!), -21, accuracy: 0.6, "and its second half is 20 dB below")

        let part = player()
        try part.testBuffer(whole, gainDB: gain, from: rate)
        let heardPart = try rendered(part, slices: 4)
        XCTAssertEqual(dBFS(heardPart.peaks.max()!), -21, accuracy: 0.6, "played on its own, it is not raised to full level")
    }

    func testALoopedSelectionIsHeardAtTheLevelOfTheWhole() throws {
        let whole = stereo(sine(rate, 0.9), sine(rate, 0.09))
        let p = player()
        try p.testBuffer(whole, gainDB: gainForAnAlert(of: whole), loop: rate..<(2 * rate))
        let (peaks, _) = try rendered(p, slices: 12)
        XCTAssertEqual(dBFS(peaks.max()!), -21, accuracy: 0.6)
        XCTAssertGreaterThan(peaks.min()!, 0.05, "round and round, with no gap")
    }

    func testAPartIsAsLoudAsTheAlertOfTheSameSoundWouldBeThere() throws {
        let whole = stereo(sine(rate, 0.9), sine(rate, 0.09))
        try write(whole, as: "Both")

        let alert = player()
        try alert.play(sound: "Both", ruleGainDB: 0)
        let heardAlert = try rendered(alert, slices: 8)

        let preview = player()
        try preview.testBuffer(whole, gainDB: gainForAnAlert(of: whole))
        let heardPreview = try rendered(preview, slices: 8)

        for slice in 0..<8 {
            XCTAssertEqual(dBFS(heardPreview.peaks[slice]), dBFS(heardAlert.peaks[slice]), accuracy: 0.3, "slice \(slice)")
        }
    }

    func testTheGainIsAppliedAsGivenAndNotWorkedOutFromWhatIsPlayed() throws {
        let sound = stereo(sine(rate, 0.5))
        let p = player()
        try p.testBuffer(sound, gainDB: -12)
        let (peaks, _) = try rendered(p, slices: 4)
        XCTAssertEqual(dBFS(peaks.max()!), dBFS(0.5) - 12, accuracy: 0.5)
    }

    func testAGainThatIsNotANumberIsSilenceAndNotNoise() throws {
        let p = player()
        try p.testBuffer(stereo(sine(rate, 0.5)), gainDB: .nan)
        let (peaks, notNumbers) = try rendered(p, slices: 2)
        XCTAssertEqual(notNumbers, 0)
        XCTAssertLessThan(dBFS(peaks.max()!), -60)
    }

    // MARK: - Nothing in it

    func testASelectionWithNothingInItPlaysSilenceAndIsNotAnError() throws {
        let p = player()
        XCTAssertNoThrow(try p.testBuffer(SampleBuffer.silence(frames: rate), gainDB: 12), "a silent part is not a silent sound")
        XCTAssertTrue(p.isPreviewing)
        let (peaks, notNumbers) = try rendered(p, slices: 2)
        XCTAssertEqual(peaks.max(), 0)
        XCTAssertEqual(notNumbers, 0)
    }

    func testAnEmptySelectionPlaysSilenceAndEndsAtOnce() throws {
        let p = player()
        let sound = stereo(sine(rate, 0.5))
        XCTAssertNoThrow(try p.testBuffer(sound, gainDB: 0, loop: 5_000..<5_000))
        let (peaks, _) = try rendered(p, slices: 2)
        XCTAssertEqual(peaks.max(), 0)
        waitUntil { !p.isPreviewing }
        XCTAssertFalse(p.isPreviewing, "a loop of nothing is not a loop")
    }

    func testASelectionPastTheEndOfTheSoundPlaysSilenceAndEndsAtOnce() throws {
        let p = player()
        let sound = stereo(sine(rate, 0.5))
        XCTAssertNoThrow(try p.testBuffer(sound, gainDB: 0, loop: (2 * rate)..<(3 * rate)))
        let (peaks, _) = try rendered(p, slices: 2)
        XCTAssertEqual(peaks.max(), 0)
        waitUntil { !p.isPreviewing }
        XCTAssertFalse(p.isPreviewing)
    }

    func testAStartAtTheEndOfTheSoundPlaysSilenceAndEndsAtOnce() throws {
        let p = player()
        let sound = stereo(sine(rate, 0.5))
        XCTAssertNoThrow(try p.testBuffer(sound, gainDB: 0, from: rate))
        XCTAssertNoThrow(try p.testBuffer(sound, gainDB: 0, from: 10 * rate))
        let (peaks, _) = try rendered(p, slices: 2)
        XCTAssertEqual(peaks.max(), 0)
        waitUntil { !p.isPreviewing }
        XCTAssertFalse(p.isPreviewing)
    }

    func testASoundWithNoFramesAtAllIsNotAnError() throws {
        let p = player()
        XCTAssertNoThrow(try p.testBuffer(SampleBuffer(channels: [[], []])!, gainDB: 0))
        XCTAssertNoThrow(try p.testBuffer(SampleBuffer(channels: [[], []])!, gainDB: 0, from: 7, loop: 3..<9))
    }

    // MARK: - Where it starts and what it goes round

    func testItStartsFromTheFrameItIsGiven() throws {
        // Three blocks of nothing, then three blocks of tone.
        let sound = stereo(nothing(12_288), sine(12_288, 0.5))

        let fromTheStart = player()
        try fromTheStart.testBuffer(sound, gainDB: 0, from: 0)
        let heardFromTheStart = try rendered(fromTheStart, slices: 8, blocks: 1).peaks
        XCTAssertEqual(Array(heardFromTheStart[0..<3]).max(), 0, "the nothing")
        XCTAssertGreaterThan(Array(heardFromTheStart[4..<6]).min()!, 0.4, "then the tone")
        XCTAssertEqual(heardFromTheStart[7], 0, "then the end")

        let fromTheTone = player()
        try fromTheTone.testBuffer(sound, gainDB: 0, from: 12_288)
        let heardFromTheTone = try rendered(fromTheTone, slices: 8, blocks: 1).peaks
        XCTAssertGreaterThan(Array(heardFromTheTone[0..<3]).min()!, 0.4, "it began at the tone")
        XCTAssertEqual(Array(heardFromTheTone[4..<8]).max(), 0, "and went on to the end of the sound, once")
    }

    func testAStartBeforeTheSoundIsTheStartOfTheSound() throws {
        let sound = stereo(nothing(12_288), sine(12_288, 0.5))
        let p = player()
        try p.testBuffer(sound, gainDB: 0, from: -500)
        XCTAssertEqual(p.previewFrame, 0)
        let peaks = try rendered(p, slices: 6, blocks: 1).peaks
        XCTAssertEqual(Array(peaks[0..<3]).max(), 0)
        XCTAssertGreaterThan(peaks[4], 0.4)
    }

    func testALoopGoesRoundTheRangeItIsGiven() throws {
        // A little over half a second of nothing, a block of tone, then nothing again.
        let sound = stereo(nothing(24_000), sine(4_096, 0.5), nothing(19_904))
        let tone = 24_000..<28_096

        let once = player()
        try once.testBuffer(sound, gainDB: 0, from: tone.lowerBound)
        let heardOnce = try rendered(once, slices: 5, blocks: 1)
        XCTAssertGreaterThan(heardOnce.peaks[0], 0.4)
        XCTAssertEqual(Array(heardOnce.peaks[2..<5]).max(), 0, "without a loop it is heard once")

        let looped = player()
        try looped.testBuffer(sound, gainDB: 0, from: tone.lowerBound, loop: tone)
        let heardLooped = try rendered(looped, slices: 5, blocks: 1)
        XCTAssertGreaterThan(heardLooped.peaks.min()!, 0.4, "with one it is heard again and again")
    }

    func testALoopStartedOutsideItsRangeBeginsAtTheStartOfTheRange() throws {
        let sound = stereo(nothing(24_000), sine(4_096, 0.5), nothing(19_904))
        let tone = 24_000..<28_096
        for from in [0, 30_000, tone.upperBound] {
            let p = player()
            try p.testBuffer(sound, gainDB: 0, from: from, loop: tone)
            XCTAssertEqual(p.previewFrame, tone.lowerBound, "from \(from)")
            let (peaks, _) = try rendered(p, slices: 3, blocks: 1)
            XCTAssertGreaterThan(peaks.min()!, 0.4, "from \(from), the selection is heard at once")
        }
    }

    func testALoopStartedInsideItsRangeFinishesTheRangeAndThenGoesRound() throws {
        // A range of six blocks, nothing and then tone, started in the tone.
        let sound = stereo(nothing(12_288), sine(12_288, 0.5))
        let p = player()
        try p.testBuffer(sound, gainDB: 0, from: 12_288, loop: 0..<24_576)
        XCTAssertEqual(p.previewFrame, 12_288)
        let peaks = try rendered(p, slices: 9, blocks: 1).peaks
        XCTAssertGreaterThan(Array(peaks[0..<3]).min()!, 0.4, "the rest of the range, which is the tone")
        XCTAssertEqual(Array(peaks[4..<6]).max(), 0, "then round to the start of it, which is nothing")
        XCTAssertGreaterThan(Array(peaks[7..<9]).min()!, 0.4, "and the whole of it again")
    }

    func testARangeLongerThanTheSoundIsHeldToTheSound() throws {
        let sound = stereo(sine(4_800, 0.5))
        let p = player()
        XCTAssertNoThrow(try p.testBuffer(sound, gainDB: 0, loop: -10_000..<100_000))
        let (peaks, _) = try rendered(p, slices: 3, blocks: 1)
        XCTAssertGreaterThan(peaks.min()!, 0.4)
    }

    // MARK: - Where it has got to

    func testItSaysWhereItStartedBeforeAnythingIsHeard() throws {
        let p = player()
        try p.testBuffer(stereo(sine(rate, 0.5)), gainDB: 0, from: 1_000)
        XCTAssertEqual(p.previewFrame, 1_000)
    }

    func testItSaysWhereItHasGotTo() throws {
        let p = player()
        try p.testBuffer(stereo(sine(rate, 0.5)), gainDB: 0, from: 1_000)
        _ = try rendered(p, slices: 1)
        let frame = try XCTUnwrap(p.previewFrame)
        XCTAssertEqual(frame, 1_000 + 12_288, accuracy: 4_096, "a quarter of a second on, to the block it was rendered in")
    }

    func testInALoopItStaysInsideTheRange() throws {
        let p = player()
        let range = 10_000..<14_800
        try p.testBuffer(stereo(sine(rate, 0.5)), gainDB: 0, from: 12_000, loop: range)
        _ = try rendered(p, slices: 5, blocks: 4)
        let frame = try XCTUnwrap(p.previewFrame)
        XCTAssertTrue(range.contains(frame), "\(frame) is inside \(range)")
    }

    func testInALoopItAdvancesAndThenGoesRoundToTheStartOfTheRange() throws {
        // A range of 40,000 frames, started 10,000 frames from its end. Frames are counted in the blocks
        // the graph is rendered in, so each position is the block it was rendered in, and the range is wide
        // enough that a frame that never moved, or never went round, is far from where it should be.
        let p = player()
        try p.testBuffer(stereo(sine(rate, 0.5)), gainDB: 0, from: 30_000, loop: 0..<40_000)

        _ = try rendered(p, slices: 1, blocks: 2)
        let advanced = try XCTUnwrap(p.previewFrame)
        XCTAssertEqual(advanced, 30_000 + 8_192, accuracy: 4_096, "two blocks on, still in the first time through")

        _ = try rendered(p, slices: 1, blocks: 3)
        let roundAgain = try XCTUnwrap(p.previewFrame)
        XCTAssertEqual(roundAgain, 20_480 - 10_000, accuracy: 4_096, "five blocks on, round to the start and a little way in")
    }

    func testTheTimelineOfASoundPlayedOnce() {
        let timeline = AlertPlayer.PreviewTimeline(start: 100, end: 1_000, loopStart: nil)
        XCTAssertEqual(timeline.frame(afterPlaying: 0), 100)
        XCTAssertEqual(timeline.frame(afterPlaying: 50), 150)
        XCTAssertEqual(timeline.frame(afterPlaying: 900), 1_000)
        XCTAssertEqual(timeline.frame(afterPlaying: 5_000), 1_000, "never past its end")
        XCTAssertEqual(timeline.frame(afterPlaying: -5), 100, "never before its start")
    }

    func testTheTimelineOfALoopStartedPartWayRound() {
        let timeline = AlertPlayer.PreviewTimeline(start: 150, end: 200, loopStart: 100)
        XCTAssertEqual(timeline.frame(afterPlaying: 0), 150)
        XCTAssertEqual(timeline.frame(afterPlaying: 49), 199)
        XCTAssertEqual(timeline.frame(afterPlaying: 50), 100, "round to the start")
        XCTAssertEqual(timeline.frame(afterPlaying: 51), 101)
        XCTAssertEqual(timeline.frame(afterPlaying: 149), 199)
        XCTAssertEqual(timeline.frame(afterPlaying: 150), 100, "and round again")
        XCTAssertEqual(timeline.frame(afterPlaying: 50 + 100 * 1_000 + 7), 107)
    }

    func testTheTimelineOfALoopStartedAtItsStart() {
        let timeline = AlertPlayer.PreviewTimeline(start: 100, end: 200, loopStart: 100)
        XCTAssertEqual(timeline.frame(afterPlaying: 0), 100)
        XCTAssertEqual(timeline.frame(afterPlaying: 99), 199)
        XCTAssertEqual(timeline.frame(afterPlaying: 100), 100)
    }

    // MARK: - What a sound may hold, and what it is played through

    func testSamplesThatAreNotNumbersNeverReachTheGraph() throws {
        // The limiter carries what it has seen from one sample to the next, and what a preview puts into
        // it is what the next alert is limited by.
        var samples = sine(rate, 0.5)
        samples[100] = .nan
        samples[200] = .infinity
        samples[300] = -.infinity
        let p = player()
        try p.testBuffer(SampleBuffer(channels: [samples, samples])!, gainDB: 0)
        let (peaks, notNumbers) = try rendered(p, slices: 4)
        XCTAssertEqual(notNumbers, 0)
        XCTAssertLessThanOrEqual(peaks.max()!, 1)
    }

    func testAMonoSoundIsHeardInBothChannels() throws {
        let p = player()
        try p.testBuffer(SampleBuffer(channels: [sine(rate, 0.5)])!, gainDB: 0)
        let out = AVAudioPCMBuffer(pcmFormat: p.engine.manualRenderingFormat, frameCapacity: 4096)!
        XCTAssertEqual(try p.engine.renderOffline(4096, to: out), .success)
        let channels = out.floatChannelData!
        let left = (0..<Int(out.frameLength)).map { abs(channels[0][$0]) }.max()!
        let right = (0..<Int(out.frameLength)).map { abs(channels[1][$0]) }.max()!
        XCTAssertGreaterThan(left, 0.2)
        XCTAssertEqual(left, right, accuracy: 0.0001)
    }

    func testItReportsTheOutputAsAnAlertWouldBeHeardOn() throws {
        let muted = OutputState(muted: true, volume: 0.8)
        let output = try player(output: muted).testBuffer(stereo(sine(rate, 0.5)), gainDB: 0)
        XCTAssertEqual(output, muted)
    }

    // MARK: - It changes nothing an alert reads

    func testAnAlertAfterAPreviewIsAsLoudAsOneBefore() throws {
        try writeTone("Pager")
        let fresh = try player().play(sound: "Pager", ruleGainDB: -6)

        let p = player()
        try p.testBuffer(stereo(sine(rate, 0.5)), gainDB: -40, loop: 0..<4_800)
        XCTAssertFalse(p.isPlayingAlert)
        let after = try p.play(sound: "Pager", ruleGainDB: -6)
        XCTAssertEqual(after, fresh, "the same report, as if nothing had been previewed")
        let (peaks, _) = try rendered(p, slices: 4)
        XCTAssertEqual(dBFS(peaks.max()!), -1 - 6, accuracy: 0.6)
        XCTAssertTrue(p.speechPeaks.isEmpty)
    }

    /// What a fresh player gives for the alert of `writeTone`, at -6 dB, in four slices: the yardstick for an alert
    /// that follows a preview.
    private func heardAsAFreshPlayerWouldGiveIt() throws -> (report: AlertPlayer.Report, peaks: [Float]) {
        let fresh = player()
        let report = try fresh.play(sound: "Pager", ruleGainDB: -6)
        return (report, try rendered(fresh, slices: 4).peaks)
    }

    func testAnAlertAfterALoudLoopedPreviewIsHeardAsOneBefore() throws {
        try writeTone("Pager")
        let fresh = try heardAsAFreshPlayerWouldGiveIt()

        // As loud as the graph's own range lets a full-scale sound be, round and round, so that whatever the
        // limiter keeps of what it has seen is at its most.
        let p = player()
        try p.testBuffer(stereo(sine(rate, 1)), gainDB: 24, loop: 0..<4_800)
        let loud = try rendered(p, slices: 4)
        XCTAssertLessThanOrEqual(loud.peaks.max()!, 1, "the limiter held it")
        p.stopTest()

        let report = try p.play(sound: "Pager", ruleGainDB: -6)
        XCTAssertEqual(report, fresh.report)
        let heard = try rendered(p, slices: 4)
        XCTAssertEqual(heard.notNumbers, 0)
        for slice in 0..<4 {
            XCTAssertEqual(dBFS(heard.peaks[slice]), dBFS(fresh.peaks[slice]), accuracy: 0.3, "slice \(slice)")
        }
    }

    func testAnAlertAfterAPreviewOfSamplesThatAreNotNumbersIsHeardAsOneBefore() throws {
        try writeTone("Pager")
        let fresh = try heardAsAFreshPlayerWouldGiveIt()

        // Every few frames of a loud, looped sound is not a number. Were any let into the graph, what the
        // limiter carries from one sample to the next would be what the next alert is limited by.
        var samples = sine(4_800, 1)
        for i in stride(from: 0, to: samples.count, by: 7) {
            samples[i] = [Float.nan, .infinity, -.infinity][(i / 7) % 3]
        }
        let p = player()
        try p.testBuffer(SampleBuffer(channels: [samples, samples])!, gainDB: 24, loop: 0..<4_800)
        let poisoned = try rendered(p, slices: 4)
        XCTAssertEqual(poisoned.notNumbers, 0)
        p.stopTest()

        try p.play(sound: "Pager", ruleGainDB: -6)
        let heard = try rendered(p, slices: 4)
        XCTAssertEqual(heard.notNumbers, 0, "the alert is made of numbers")
        for slice in 0..<4 {
            XCTAssertEqual(dBFS(heard.peaks[slice]), dBFS(fresh.peaks[slice]), accuracy: 0.3, "slice \(slice)")
        }
    }

    func testAnAlertThatInterruptsALoudLoopedPreviewIsHeardAsOneBefore() throws {
        try writeTone("Pager")
        let fresh = try heardAsAFreshPlayerWouldGiveIt()

        // Not stopped first: the alert's own start ends the preview, with the limiter in the middle of it.
        let p = player()
        try p.testBuffer(stereo(sine(rate, 1)), gainDB: 24, loop: 0..<4_800)
        _ = try rendered(p, slices: 4)

        try p.play(sound: "Pager", ruleGainDB: -6)
        let heard = try rendered(p, slices: 4)
        XCTAssertEqual(heard.notNumbers, 0)
        for slice in 0..<4 {
            XCTAssertEqual(dBFS(heard.peaks[slice]), dBFS(fresh.peaks[slice]), accuracy: 0.3, "slice \(slice)")
        }
    }
}
