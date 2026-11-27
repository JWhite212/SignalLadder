import XCTest
@testable import NotificationCore

/// The seven checks of the sound editor (plan, Ruling 12): each fires just past its
/// threshold and not just short of it, and each press clears the finding it is
/// the press of. The thresholds are provisional (O4) and are read here from the one
/// place they are kept, so that setting them by ear changes the numbers and not the
/// tests, except for the one test that holds the figures the plan began with.
final class SoundChecksTests: XCTestCase {
    private typealias Limits = SoundChecks.Limits
    private typealias Samples = SoundFindingSamples

    private func kinds(_ samples: SampleBuffer) -> [SoundFinding.Kind] {
        SoundChecks.findings(in: samples).map(\.kind)
    }

    private func finding(_ kind: SoundFinding.Kind, in samples: SampleBuffer,
                         file: StaticString = #filePath, line: UInt = #line) throws -> SoundFinding {
        try XCTUnwrap(SoundChecks.findings(in: samples).first { $0.kind == kind }, "no \(kind) finding",
                      file: file, line: line)
    }

    /// The samples of `recipe`'s result, made of `source` as the window would make them.
    private func render(_ source: SampleBuffer, _ recipe: SoundRecipe) -> SampleBuffer {
        SoundRender.render(source: source, recipe: recipe)
    }

    /// The recipe after a finding's press, made on the whole of `source`, and what it plays.
    private func afterPress(of kind: SoundFinding.Kind, in source: SampleBuffer,
                            file: StaticString = #filePath, line: UInt = #line) throws -> (SoundRecipe, SampleBuffer) {
        let fix = try XCTUnwrap(try finding(kind, in: source, file: file, line: line).fix, "\(kind) has no press",
                                file: file, line: line)
        guard case .edit(let edit) = fix else {
            XCTFail("\(kind)'s press is not an edit", file: file, line: line)
            return (SoundFixtures.whole(source.frameCount), source)
        }
        let recipe = try edit.applied(to: SoundFixtures.whole(source.frameCount))
        return (recipe, render(source, recipe))
    }

    // MARK: - A sound that is fine

    func testAWellMadeSoundHasNothingToReport() {
        XCTAssertEqual(SoundChecks.findings(in: Samples.goodTone()), [])
    }

    func testEveryKindHasASoundThatSetsItOffAndTheOtherSoundsDoNotSetItOff() {
        for kind in SoundFinding.Kind.allCases {
            XCTAssertTrue(kinds(Samples.setting(off: kind)).contains(kind), "\(kind) did not fire on its own sound")
        }
        XCTAssertEqual(kinds(Samples.setting(off: .tooShort)), [.tooShort])
        XCTAssertEqual(kinds(Samples.setting(off: .silenceAtStart)), [.silenceAtStart])
        XCTAssertEqual(kinds(Samples.setting(off: .silenceAtEnd)), [.silenceAtEnd])
        XCTAssertEqual(kinds(Samples.setting(off: .clipping)), [.clipping])
        XCTAssertEqual(kinds(Samples.setting(off: .tooLong)), [.tooLong])
    }

    // MARK: - Starts too abruptly

    func testASoundThatReachesHalfItsPeakInUnder10msStartsAbruptly() {
        let frames = 48_000
        let justInside = Samples.step(frames: frames, lead: Limits.abruptFrames - 1, quiet: 0.01, loud: 0.8)
        let justOutside = Samples.step(frames: frames, lead: Limits.abruptFrames, quiet: 0.01, loud: 0.8)
        XCTAssertTrue(kinds(justInside).contains(.startsAbruptly))
        XCTAssertFalse(kinds(justOutside).contains(.startsAbruptly))
    }

    func testASoundThatIsAlreadyAtHalfItsPeakOnItsFirstFrameStartsAbruptly() {
        XCTAssertTrue(kinds(SoundSignals.constant(0.3, frames: 48_000)).contains(.startsAbruptly))
    }

    func testTheRiseIsCountedFromWhereTheSoundBeginsToBeHeardAndNotFromTheFirstFrame() throws {
        // 2,000 frames below the silence floor, under what silence at the start reports, and then a step.
        let lead = 2_000
        let abrupt = Samples.silence(lead, then: SoundSignals.constant(0.3, frames: 48_000))
        XCTAssertLessThan(lead, Limits.leadingSilenceFrames)
        XCTAssertEqual(kinds(abrupt), [.startsAbruptly])
        XCTAssertEqual(try finding(.startsAbruptly, in: abrupt).frames, 0)
        // A rise that takes the whole 10 ms after that lead-in is not abrupt.
        let eased = Samples.silence(lead, then: Samples.step(frames: 48_000, lead: Limits.abruptFrames, quiet: 0.01, loud: 0.8))
        XCTAssertFalse(kinds(eased).contains(.startsAbruptly))
    }

    func testThePressFadesInThe30msAfterWhereTheSoundBeginsToBeHeard() throws {
        let lead = 2_000
        let abrupt = Samples.silence(lead, then: SoundSignals.constant(0.3, frames: 48_000))
        XCTAssertEqual(try finding(.startsAbruptly, in: abrupt).fix,
                       .edit(.fadeIn(lead..<(lead + Limits.abruptFadeFrames))))
    }

    func testAFadeInPressClearsTheFindingItIsThePressOf() throws {
        for lead in [0, 2_000] {
            let source = Samples.silence(lead, then: SoundSignals.constant(0.3, frames: 48_000))
            let (_, result) = try afterPress(of: .startsAbruptly, in: source)
            XCTAssertFalse(kinds(result).contains(.startsAbruptly), "after the press, with \(lead) frames before it")
        }
    }

    func testAFadeInOfASoundShorterThanTheFadeIsOverAllOfIt() throws {
        // Long enough that the fade, which is all of it, takes the rise past what is abrupt.
        let short = SoundSignals.constant(0.3, frames: 1_000)
        XCTAssertLessThan(short.frameCount, Limits.abruptFadeFrames)
        XCTAssertEqual(try finding(.startsAbruptly, in: short).fix, .edit(.fadeIn(0..<1_000)))
        let (_, result) = try afterPress(of: .startsAbruptly, in: short)
        XCTAssertFalse(kinds(result).contains(.startsAbruptly))
    }

    /// A loud part inside the fade stays the loudest the fade leaves, and so is still reached in
    /// well under 10 ms: 5 ms at full level, then a held level a third of it.
    private var burstThenHeld: SampleBuffer { SoundSignals.both(frames: 48_000) { $0 < 240 ? 1 : 0.3 } }

    func testNoPressIsOfferedWhenTheFadeWouldLeaveTheSoundAbruptStill() throws {
        // The burst is 0.17 of its height after the fade and the held level 0.3, and half of that is
        // reached by the burst in 216 frames, so the finding would stand after the press.
        let found = try finding(.startsAbruptly, in: burstThenHeld)
        XCTAssertNil(found.fix)
        // A sound under 10 ms long cannot take 10 ms to rise, whatever is done to it.
        XCTAssertNil(try finding(.startsAbruptly, in: SoundSignals.constant(0.3, frames: 400)).fix)
    }

    func testEveryFadeInPressThatIsOfferedClearsItsFinding() throws {
        let tick = SoundSignals.both(frames: 48_000) { Float(exp(-Double($0) / 300)) }
        let swell = SoundSignals.both(frames: 48_000) { $0 < 100 ? 0.05 : 0.6 }
        let signals: [(String, SampleBuffer)] = [
            ("held", SoundSignals.constant(0.3, frames: 48_000)), ("burst then held", burstThenHeld), ("tick", tick),
            ("a step after a quiet start", swell),
            ("with a lead", Samples.silence(2_000, then: burstThenHeld)),
            ("1,000 frames", SoundSignals.constant(0.3, frames: 1_000)), ("400 frames", SoundSignals.constant(0.3, frames: 400)),
        ]
        for (name, source) in signals {
            guard let found = SoundChecks.findings(in: source).first(where: { $0.kind == .startsAbruptly }),
                  found.fix != nil else { continue }
            let (_, result) = try afterPress(of: .startsAbruptly, in: source)
            XCTAssertFalse(kinds(result).contains(.startsAbruptly), "after the press, \(name)")
        }
    }

    // MARK: - Too short

    func testASoundUnderHalfASecondIsTooShort() {
        XCTAssertTrue(kinds(Samples.goodTone(frames: Limits.shortestFrames - 1)).contains(.tooShort))
        XCTAssertFalse(kinds(Samples.goodTone(frames: Limits.shortestFrames)).contains(.tooShort))
    }

    func testThePressRepeatsTheWholeSoundThreeTimesWithAGapBetween() throws {
        let short = Samples.goodTone(frames: 9_600)
        XCTAssertEqual(try finding(.tooShort, in: short).fix,
                       .edit(.repeatSelection(0..<9_600, times: Limits.shortRepeatTimes,
                                              gapFrames: Limits.shortRepeatGapFrames)))
        XCTAssertEqual(try finding(.tooShort, in: short).frames, 9_600)
    }

    func testARepeatPressClearsTheFindingEvenForAVeryShortSound() throws {
        for frames in [9_600, Limits.shortestFrames - 1, 480, 2] {
            let source = SoundSignals.constant(0.3, frames: frames)
            let (recipe, result) = try afterPress(of: .tooShort, in: source)
            XCTAssertEqual(recipe.frameCount, Limits.shortRepeatTimes * frames + (Limits.shortRepeatTimes - 1) * Limits.shortRepeatGapFrames)
            XCTAssertFalse(kinds(result).contains(.tooShort), "\(frames) frames")
        }
    }

    // MARK: - Silence at the start

    func testMoreThanATenthOfASecondBelowTheFloorAtTheStartIsSilenceAtTheStart() {
        let tone = SoundSignals.constant(0.3, frames: 48_000)
        XCTAssertFalse(kinds(Samples.silence(Limits.leadingSilenceFrames, then: tone)).contains(.silenceAtStart))
        XCTAssertTrue(kinds(Samples.silence(Limits.leadingSilenceFrames + 1, then: tone)).contains(.silenceAtStart))
    }

    func testTheSilenceAtTheStartIsTheFramesBelowTheFloorAndSoItCanBeQuietAndNotZero() throws {
        let lead = Limits.leadingSilenceFrames + 1
        let hiss = Samples.step(frames: 48_000, lead: lead, quiet: 0.00099, loud: 0.3)
        XCTAssertEqual(try finding(.silenceAtStart, in: hiss).frames, lead)
        let heard = Samples.step(frames: 48_000, lead: lead, quiet: 0.00101, loud: 0.3)
        XCTAssertFalse(kinds(heard).contains(.silenceAtStart))
    }

    func testAFrameThatIsSoundInEitherChannelIsNotSilence() {
        let frames = 48_000
        let lead = Limits.leadingSilenceFrames + 1
        let rightOnly = SoundSignals.stereo(frames: frames, left: { _ in 0 }, right: { $0 < lead ? 0 : 0.3 })
        XCTAssertTrue(kinds(rightOnly).contains(.silenceAtStart))
        let rightEarly = SoundSignals.stereo(frames: frames, left: { $0 < lead ? 0 : 0.3 }, right: { _ in 0.3 })
        XCTAssertFalse(kinds(rightEarly).contains(.silenceAtStart))
    }

    func testThePressTrimsTheSilenceAtTheStart() throws {
        let source = Samples.silence(Limits.leadingSilenceFrames + 1, then: Samples.goodTone())
        let lead = try XCTUnwrap(try finding(.silenceAtStart, in: source).frames)
        XCTAssertEqual(try finding(.silenceAtStart, in: source).fix, .edit(.trim(lead..<source.frameCount)))
        let (recipe, result) = try afterPress(of: .silenceAtStart, in: source)
        XCTAssertEqual(recipe.frameCount, source.frameCount - lead)
        XCTAssertFalse(kinds(result).contains(.silenceAtStart))
    }

    // MARK: - Silence at the end

    func testMoreThanAQuarterOfASecondBelowTheFloorAtTheEndIsSilenceAtTheEnd() {
        let tone = SoundSignals.constant(0.3, frames: 48_000)
        XCTAssertFalse(kinds(Samples.sound(tone, thenSilence: Limits.trailingSilenceFrames)).contains(.silenceAtEnd))
        XCTAssertTrue(kinds(Samples.sound(tone, thenSilence: Limits.trailingSilenceFrames + 1)).contains(.silenceAtEnd))
    }

    func testTheSilenceAtTheEndIsCountedFromTheLastFrameThatIsHeard() throws {
        let tone = Samples.goodTone()
        let silent = Limits.trailingSilenceFrames + 1
        let source = Samples.sound(tone, thenSilence: silent)
        XCTAssertEqual(try finding(.silenceAtEnd, in: source).frames, silent + trailingQuietFrames(of: tone))
    }

    /// The faded tone's last frames are below the floor too, and are silence at the end as the
    /// check reads it.
    private func trailingQuietFrames(of tone: SampleBuffer) -> Int {
        var count = 0
        for index in stride(from: tone.frameCount - 1, through: 0, by: -1) {
            guard !tone.channels.contains(where: { Loudness.isAudible(peak: abs($0[index])) }) else { break }
            count += 1
        }
        return count
    }

    func testThePressTrimsTheSilenceAtTheEnd() throws {
        let source = Samples.sound(Samples.goodTone(), thenSilence: Limits.trailingSilenceFrames + 1)
        let silent = try XCTUnwrap(try finding(.silenceAtEnd, in: source).frames)
        XCTAssertEqual(try finding(.silenceAtEnd, in: source).fix, .edit(.trim(0..<(source.frameCount - silent))))
        let (recipe, result) = try afterPress(of: .silenceAtEnd, in: source)
        XCTAssertEqual(recipe.frameCount, source.frameCount - silent)
        XCTAssertFalse(kinds(result).contains(.silenceAtEnd))
    }

    func testBothSilencesAreReportedAndEachPressClearsOnlyItsOwn() throws {
        let source = Samples.sound(Samples.silence(Limits.leadingSilenceFrames + 1, then: Samples.goodTone()),
                                   thenSilence: Limits.trailingSilenceFrames + 1)
        XCTAssertEqual(kinds(source), [.silenceAtStart, .silenceAtEnd])
        XCTAssertEqual(kinds(try afterPress(of: .silenceAtStart, in: source).1), [.silenceAtEnd])
        XCTAssertEqual(kinds(try afterPress(of: .silenceAtEnd, in: source).1), [.silenceAtStart])
    }

    // MARK: - Clipping

    private func tone(withRunOf length: Int, in channel: Int = 0, value: Float = 1, at start: Int = 20_000) -> SampleBuffer {
        var channels = Samples.goodTone().channels
        for index in start..<(start + length) { channels[channel][index] = value }
        return SampleBuffer(channels: channels)!
    }

    func testARunOfThreeSamplesAtFullScaleIsClippingAndARunOfTwoIsNot() {
        XCTAssertTrue(kinds(tone(withRunOf: Limits.clippedRunLength)).contains(.clipping))
        XCTAssertFalse(kinds(tone(withRunOf: Limits.clippedRunLength - 1)).contains(.clipping))
    }

    func testARunBelowFullScaleIsNotClippingHoweverLongAndAnyFullScaleSampleCounts() {
        XCTAssertFalse(kinds(tone(withRunOf: 400, value: 0.99)).contains(.clipping))
        XCTAssertTrue(kinds(tone(withRunOf: 3, value: -1)).contains(.clipping))
        XCTAssertTrue(kinds(tone(withRunOf: 3, value: Limits.clippedLevel)).contains(.clipping), "16-bit full scale")
        XCTAssertTrue(kinds(tone(withRunOf: 3, value: 1.5)).contains(.clipping), "a level past full scale")
    }

    func testASmoothPeakRaisedPastFullScaleIsNotClipping() {
        // 1 kHz at 48 kHz, 1.5 at its peak: every sample near the top is past full scale and no two are the same,
        // so the sound was made louder than the format can hold and was not flattened.
        let sine = SoundSignals.sine(frames: 48_000, hz: 1_000, amplitude: 1.5)
        XCTAssertGreaterThan(sine.peak, 1)
        XCTAssertFalse(kinds(sine).contains(.clipping))
        // The same sine cut off at full scale has flat tops, and is clipping.
        let flattened = SoundSignals.sine(frames: 48_000, hz: 1_000, amplitude: 1.5).channels.map { $0.map { min(max($0, -1), 1) } }
        XCTAssertTrue(kinds(SampleBuffer(channels: flattened)!).contains(.clipping))
    }

    func testARunAtFullScaleOfSamplesThatDifferByMoreThanAStepIsNotFlat() {
        var channels = Samples.goodTone().channels
        for (offset, value) in [Float(1), 1.01, 1.02, 1.03].enumerated() { channels[0][20_000 + offset] = value }
        XCTAssertFalse(kinds(SampleBuffer(channels: channels)!).contains(.clipping))
        for (offset, value) in [Float(1), 1 + Limits.flatTopTolerance / 2, 1, 1].enumerated() { channels[0][20_000 + offset] = value }
        XCTAssertTrue(kinds(SampleBuffer(channels: channels)!).contains(.clipping), "within a step of one another is flat")
    }

    func testTwoShortRunsWithASampleBetweenAreNotOneRun() {
        var channels = Samples.goodTone().channels
        for index in [20_000, 20_001, 20_003, 20_004] { channels[0][index] = 1 }
        XCTAssertFalse(kinds(SampleBuffer(channels: channels)!).contains(.clipping))
    }

    func testARunHasToBeInOneChannel() {
        var channels = Samples.goodTone().channels
        channels[0][20_000] = 1
        channels[1][20_001] = 1
        channels[0][20_002] = 1
        XCTAssertFalse(kinds(SampleBuffer(channels: channels)!).contains(.clipping))
    }

    func testClippingHasNoPressAndDoesNotStopASave() throws {
        let clipped = try finding(.clipping, in: Samples.setting(off: .clipping))
        XCTAssertNil(clipped.fix)
        XCTAssertFalse(clipped.blocksSaving)
    }

    // MARK: - Too long

    func testASoundOverThirtySecondsIsTooLongAndExactlyThirtyIsNot() {
        let limit = SoundRecipe.savableFrames
        XCTAssertEqual(Limits.longestFrames, limit)
        XCTAssertFalse(kinds(SoundSignals.constant(0.3, frames: limit)).contains(.tooLong))
        XCTAssertTrue(kinds(SoundSignals.constant(0.3, frames: limit + 1)).contains(.tooLong))
    }

    func testTooLongStopsASaveAndItsPressKeepsTheFirstThirtySeconds() throws {
        let source = Samples.setting(off: .tooLong)
        let long = try finding(.tooLong, in: source)
        XCTAssertTrue(long.blocksSaving)
        XCTAssertEqual(long.frames, source.frameCount)
        XCTAssertEqual(long.fix, .edit(.trim(0..<SoundRecipe.savableFrames)))
        let (recipe, result) = try afterPress(of: .tooLong, in: source)
        XCTAssertTrue(recipe.canBeSaved)
        XCTAssertEqual(result.frameCount, SoundRecipe.savableFrames)
        XCTAssertFalse(kinds(result).contains(.tooLong))
    }

    func testASoundOfTwoMinutesIsReportedToo() {
        XCTAssertTrue(kinds(SoundSignals.constant(0.3, frames: SoundRecipe.maximumFrames)).contains(.tooLong))
    }

    // MARK: - Nothing to hear

    func testASoundWhoseWholeLengthIsBelowTheSilenceFloorHasNothingToHear() {
        XCTAssertEqual(kinds(SoundSignals.constant(0, frames: 48_000)), [.nothingToHear])
        XCTAssertEqual(kinds(SoundSignals.constant(0.00099, frames: 48_000)), [.nothingToHear])
        XCTAssertFalse(kinds(SoundSignals.constant(0.00101, frames: 48_000)).contains(.nothingToHear))
    }

    func testTheFloorIsTheOneThePlayerRefusesASoundBelow() {
        for level in [Float(0.0005), 0.00099, 0.001, 0.00101, 0.002, 0.3] {
            let silent = !Loudness.isAudible(peak: level)
            XCTAssertEqual(kinds(SoundSignals.constant(level, frames: 48_000)).contains(.nothingToHear), silent,
                           "\(level): \(Loudness.peakDBFS(level) ?? -.infinity) dBFS against \(Loudness.silenceFloorDBFS)")
        }
    }

    func testNothingToHearStopsASaveAndItsPressIsUndo() throws {
        let nothing = try finding(.nothingToHear, in: SoundSignals.constant(0, frames: 48_000))
        XCTAssertTrue(nothing.blocksSaving)
        XCTAssertEqual(nothing.fix, .undo)
    }

    func testASoundThatIsNotThereIsNotAlsoToldItIsShortOrSilentOrThatItStartsAbruptly() {
        for frames in [0, 100, 4_800, 48_000] {
            XCTAssertEqual(kinds(SoundSignals.constant(0, frames: frames)), [.nothingToHear], "\(frames) frames")
        }
        // What cannot be heard cannot be too long to save either way: the length still stops it.
        XCTAssertEqual(kinds(SoundSignals.constant(0, frames: SoundRecipe.savableFrames + 1)), [.nothingToHear, .tooLong])
    }

    func testASampleThatIsNotANumberIsNotHeard() {
        XCTAssertEqual(kinds(SoundSignals.constant(.nan, frames: 48_000)), [.nothingToHear])
    }

    // MARK: - Which stop a save

    func testOnlyNothingToHearAndTooLongStopASave() {
        for kind in SoundFinding.Kind.allCases {
            let finding = SoundFinding(kind: kind, frames: nil, fix: nil)
            XCTAssertEqual(finding.blocksSaving, kind == .nothingToHear || kind == .tooLong, "\(kind)")
        }
    }

    func testTheOnesThatStopASaveAreReportedFirst() {
        // Too long, set off by a sound that is also abrupt and clipped, and has no silence to trim.
        var channels = SoundSignals.constant(0.3, frames: SoundRecipe.savableFrames + 1).channels
        for index in 0..<5 { channels[0][index] = 1 }
        XCTAssertEqual(kinds(SampleBuffer(channels: channels)!), [.tooLong, .startsAbruptly, .clipping])
    }

    func testEveryPressOtherThanUndoIsAnEditTheRecipeAccepts() throws {
        for kind in SoundFinding.Kind.allCases where kind != .nothingToHear && kind != .clipping {
            let source = Samples.setting(off: kind)
            let (recipe, result) = try afterPress(of: kind, in: source)
            XCTAssertEqual(result.frameCount, recipe.frameCount, "\(kind)")
            XCTAssertFalse(kinds(result).contains(kind), "\(kind)")
        }
    }

    // MARK: - The thresholds, as the plan began with them (O4)

    /// The figures of Ruling 12 as written on 2026-11-26. They are to be set by ear before release
    /// (O4). When they are, change them here with the constants, and nowhere else.
    func testTheThresholdsAreTheOnesThePlanBeganWith() {
        XCTAssertEqual(Limits.abruptWithinSeconds, 0.010)
        XCTAssertEqual(Limits.abruptFractionOfPeak, 0.5)
        XCTAssertEqual(Limits.abruptFadeSeconds, 0.030)
        XCTAssertEqual(Limits.shortestSeconds, 0.5)
        XCTAssertEqual(Limits.shortRepeatTimes, 3)
        XCTAssertEqual(Limits.shortRepeatGapSeconds, 0.3)
        XCTAssertEqual(Limits.leadingSilenceSeconds, 0.1)
        XCTAssertEqual(Limits.trailingSilenceSeconds, 0.25)
        XCTAssertEqual(Limits.clippedRunLength, 3)
        XCTAssertEqual(Limits.longestFrames, 30 * 48_000)
    }
}
