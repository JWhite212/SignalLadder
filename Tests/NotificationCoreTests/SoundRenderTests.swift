import XCTest
@testable import NotificationCore

/// A recipe played into samples (sound editor plan, Task 3, Ruling 4): how long
/// the result is, what is done at a join, and what each piece's gain and fades
/// come to.
final class SoundRenderTests: XCTestCase {
    private typealias F = SoundFixtures
    private typealias S = SoundSignals

    /// A source of `frames` frames of 1, so that what a render does to a piece
    /// is read straight off the result.
    private func ones(_ frames: Int) -> SampleBuffer { S.constant(1, frames: frames) }

    private func render(_ source: SampleBuffer, _ segments: [SoundSegment]) -> [Float] {
        let recipe = F.recipe(segments, frames: source.frameCount)
        return SoundRender.render(source: source, recipe: recipe).channels[0]
    }

    // MARK: - Length and shape

    func testTheWholeSourceRendersAsItself() {
        let source = S.sine(frames: 4800, hz: 440)
        XCTAssertEqual(SoundRender.render(source: source, recipe: F.whole(4800)), source)
    }

    func testTheResultIsExactlyAsLongAsTheRecipe() throws {
        let source = ones(1000)
        let recipes: [SoundRecipe] = [
            F.recipe([F.clip(0, 100), .silence(frames: 50), F.clip(500, 700), F.clip(0, 10)], frames: 1000),
            try SoundEdit.delete(100..<900).applied(to: F.whole(1000)),
            try SoundEdit.repeatSelection(200..<300, times: 4, gapFrames: 77).applied(to: F.whole(1000)),
            try SoundEdit.duplicate(0..<1000).applied(to: F.whole(1000)),
            F.recipe([.silence(frames: 12_345)], frames: 1000),
            F.recipe([F.clip(0, 1)], frames: 1000),
        ]
        for recipe in recipes {
            let result = SoundRender.render(source: source, recipe: recipe)
            XCTAssertEqual(result.frameCount, recipe.frameCount)
            XCTAssertTrue(result.channels.allSatisfy { $0.count == recipe.frameCount })
        }
    }

    func testTheResultHasTheChannelsOfTheSource() {
        let recipe = F.recipe([F.clip(0, 100), F.clip(200, 300)], frames: 400)
        XCTAssertEqual(SoundRender.render(source: S.constant(1, frames: 400, channels: 1), recipe: recipe).channelCount, 1)
        XCTAssertEqual(SoundRender.render(source: S.constant(1, frames: 400, channels: 2), recipe: recipe).channelCount, 2)
    }

    func testAResultAtTheLongestARecipeHoldsIsRendered() {
        let frames = SoundRecipe.maximumFrames
        let result = SoundRender.render(source: S.constant(0.25, frames: frames, channels: 1), recipe: F.whole(frames))
        XCTAssertEqual(result.frameCount, frames)
        XCTAssertEqual(result.channels[0].first, 0.25)
        XCTAssertEqual(result.channels[0].last, 0.25)
    }

    func testASourceShorterThanItsRecipeSaysPlaysSilenceForTheRestAndDoesNotFail() {
        let recipe = F.recipe([F.clip(0, 1000)], frames: 1000)
        let result = SoundRender.render(source: S.constant(1, frames: 600), recipe: recipe).channels[0]
        XCTAssertEqual(result.count, 1000)
        XCTAssertEqual(result[599], 1)
        XCTAssertEqual(result[600], 0)
        XCTAssertEqual(result[999], 0)
    }

    // MARK: - Joins

    func testAJoinOfPiecesThatWereNotNeighboursDipsToSilenceAndBackOverFiveMilliseconds() {
        let result = render(ones(3000), [F.clip(0, 1000), F.clip(2000, 3000)])
        XCTAssertEqual(SoundRender.dipFrames, 240)
        XCTAssertEqual(result[0], 1, "the front of the sound is not a join")
        XCTAssertEqual(result[759], 1)
        XCTAssertEqual(result[760], 239.0 / 240, accuracy: 1e-6)
        XCTAssertEqual(result[999], 0)
        XCTAssertEqual(result[1000], 0)
        XCTAssertEqual(result[1001], 1.0 / 240, accuracy: 1e-6)
        XCTAssertEqual(result[1239], 239.0 / 240, accuracy: 1e-6)
        XCTAssertEqual(result[1240], 1)
        XCTAssertEqual(result[1999], 1, "the back of the sound is not a join")
    }

    func testTheDipIsHalfAPieceWhenThePieceIsShorterThanFiveMilliseconds() {
        let result = render(ones(600), [F.clip(0, 100), F.clip(500, 600)])
        XCTAssertEqual(result[49], 1)
        XCTAssertEqual(result[50], 49.0 / 50, accuracy: 1e-6)
        XCTAssertEqual(result[99], 0)
        XCTAssertEqual(result[100], 0)
        XCTAssertEqual(result[101], 1.0 / 50, accuracy: 1e-6)
        XCTAssertEqual(result[149], 49.0 / 50, accuracy: 1e-6)
        XCTAssertEqual(result[150], 1)
        XCTAssertEqual(result[199], 1)
    }

    func testAPieceOfOneFrameBetweenJoinsIsSilentAndNotAStep() {
        let result = render(ones(1000), [F.clip(0, 500), F.clip(700, 701), F.clip(900, 1000)])
        XCTAssertEqual(result[500], 0)
        XCTAssertEqual(result[499], 0)
        XCTAssertEqual(result[501], 0)
    }

    func testPiecesThatWereNeighboursInTheSourceGetNoDip() throws {
        let recipe = try SoundEdit.gain(100..<200, dB: -6).applied(to: F.whole(300))
        XCTAssertEqual(recipe.segments.count, 3)
        let result = SoundRender.render(source: ones(300), recipe: recipe).channels[0]
        let half = Float(pow(10, -6.0 / 20))
        XCTAssertEqual(result[99], 1)
        XCTAssertEqual(result[100], half, accuracy: 1e-6)
        XCTAssertEqual(result[199], half, accuracy: 1e-6)
        XCTAssertEqual(result[200], 1)
    }

    func testAPieceBesideSilenceIsFadedOnItsSideOfTheJoinAndSilenceStaysSilent() {
        let result = render(ones(1000), [F.clip(0, 1000), .silence(frames: 500), F.clip(0, 1000)])
        XCTAssertEqual(result.count, 2500)
        XCTAssertEqual(result[759], 1)
        XCTAssertEqual(result[760], 239.0 / 240, accuracy: 1e-6)
        XCTAssertEqual(result[999], 0)
        XCTAssertTrue(result[1000..<1500].allSatisfy { $0 == 0 })
        XCTAssertEqual(result[1500], 0)
        XCTAssertEqual(result[1501], 1.0 / 240, accuracy: 1e-6)
        XCTAssertEqual(result[1740], 1)
        XCTAssertEqual(result[2499], 1)
    }

    func testRepeatedPlaysOfASelectionAreEachDippedAtTheJoin() throws {
        let recipe = try SoundEdit.repeatSelection(0..<1000, times: 3, gapFrames: 0).applied(to: F.whole(1000))
        let result = SoundRender.render(source: ones(1000), recipe: recipe).channels[0]
        XCTAssertEqual(result.count, 3000)
        for join in [1000, 2000] {
            XCTAssertEqual(result[join - 1], 0)
            XCTAssertEqual(result[join], 0)
            XCTAssertEqual(result[join - 241], 1)
            XCTAssertEqual(result[join + 240], 1)
        }
    }

    func testTheDipIsOnEveryChannelAndNotJustTheFirst() {
        let source = S.stereo(frames: 3000, left: { _ in 1 }, right: { _ in 0.5 })
        let recipe = F.recipe([F.clip(0, 1000), F.clip(2000, 3000)], frames: 3000)
        let result = SoundRender.render(source: source, recipe: recipe)
        XCTAssertEqual(result.channelCount, 2)
        for (channel, level) in [Float(1), 0.5].enumerated() {
            let samples = result.channels[channel]
            for frame in 600..<1400 {
                let ramp: Float
                if frame < 1000 {
                    ramp = min(1, Float(999 - frame) / 240)
                } else {
                    ramp = min(1, Float(frame - 1000) / 240)
                }
                XCTAssertEqual(samples[frame], level * ramp, accuracy: 1e-6, "channel \(channel), frame \(frame)")
            }
            XCTAssertEqual(samples[999], 0, "channel \(channel)")
            XCTAssertEqual(samples[1000], 0, "channel \(channel)")
        }
    }

    func testTheDipIsMultipliedIntoThePiecesOwnGainAndFadesAndDoesNotReplaceThem() throws {
        // Two pieces that were not neighbours, both at -6 dB, the second faded in over its first 600
        // frames and the first faded out over its last 600, so the dip falls on top of both.
        var recipe = try SoundEdit.delete(1000..<2000).applied(to: F.whole(3000))
        recipe = try SoundEdit.gain(0..<2000, dB: -6).applied(to: recipe)
        recipe = try SoundEdit.fadeIn(1000..<1600).applied(to: recipe)
        recipe = try SoundEdit.fadeOut(400..<1000).applied(to: recipe)
        let result = SoundRender.render(source: ones(3000), recipe: recipe).channels[0]
        XCTAssertEqual(result.count, 2000)

        let half = Float(pow(10, -6.0 / 20))
        // Frame 100 of the second piece: its fade in is at 100 / 600 and its dip at 100 / 240.
        XCTAssertEqual(result[1100], half * (100.0 / 600) * (100.0 / 240), accuracy: 1e-6)
        // Frame 100 from the end of the first piece, 99 frames before its last: fade out and dip are
        // each at 99 / 600 and 99 / 240.
        XCTAssertEqual(result[900], half * (99.0 / 600) * (99.0 / 240), accuracy: 1e-6)

        for frame in 760..<1240 {
            let fromJoin = frame < 1000 ? 999 - frame : frame - 1000
            let ramp = Float(fromJoin) / 240
            XCTAssertEqual(result[frame], F.gain(recipe, at: frame) * ramp, accuracy: 1e-6, "frame \(frame)")
        }
    }

    func testASineWithAStretchDeletedHasNoStepAtTheJoin() throws {
        let source = S.sine(frames: 48_000, hz: 440, amplitude: 0.8)
        let samples = source.channels[0]
        let start = 10_000
        // The deletion that, without a dip, would make the biggest jump: the sound would go from
        // one side of the wave to the other in one sample.
        let length = (1..<110).max { abs(samples[start - 1] - samples[start + $0]) < abs(samples[start - 1] - samples[start + $1]) }!
        let jump = abs(samples[start - 1] - samples[start + length])
        XCTAssertGreaterThan(jump, 1.0, "the signal and the cut are chosen so that a bare join would click")

        let recipe = try SoundEdit.delete(start..<(start + length)).applied(to: F.whole(48_000))
        let result = SoundRender.render(source: source, recipe: recipe)
        XCTAssertEqual(result.frameCount, 48_000 - length)
        // A 440 Hz sine of 0.8 steps by at most 0.8 * 2 * pi * 440 / 48000, about 0.046, from one
        // sample to the next, and the ramp of the dip adds 0.8 / 240 to that.
        let bound: Float = 0.055
        XCTAssertLessThan(S.largestStep(result, in: 0..<result.frameCount), bound)
        XCTAssertLessThan(S.largestStep(result, in: (start - 400)..<(start + 400)), bound)
        XCTAssertEqual(result.channels[0][start - 1], 0)
        XCTAssertEqual(result.channels[0][start], 0)
    }

    // MARK: - Gain and fades

    func testAFadeInBeginsAtZeroAndAFadeOutEndsAtZero() throws {
        var recipe = try SoundEdit.fadeIn(0..<1000).applied(to: F.whole(3000))
        recipe = try SoundEdit.fadeOut(2000..<3000).applied(to: recipe)
        let result = SoundRender.render(source: ones(3000), recipe: recipe).channels[0]
        XCTAssertEqual(result[0], 0)
        XCTAssertEqual(result[500], 0.5, accuracy: 1e-6)
        XCTAssertEqual(result[999], 0.999, accuracy: 1e-6)
        XCTAssertEqual(result[1000], 1)
        XCTAssertEqual(result[2000], 0.999, accuracy: 1e-6)
        XCTAssertEqual(result[2999], 0)
    }

    func testAFadeGoesOnAcrossACutFromWhereItWould() throws {
        var recipe = try SoundEdit.fadeIn(0..<1000).applied(to: F.whole(2000))
        recipe = try SoundEdit.delete(200..<400).applied(to: recipe)
        let result = SoundRender.render(source: ones(2000), recipe: recipe).channels[0]
        // 500 frames past the cut is frame 700 of the source, which the fade has taken to 0.7.
        XCTAssertEqual(result[200 + 300], 0.7, accuracy: 1e-6)
        XCTAssertEqual(result[50], 0.05, accuracy: 1e-6)
    }

    func testGainIsAppliedToEveryChannelAndOnlyToItsSelection() throws {
        let source = S.stereo(frames: 300, left: { _ in 1 }, right: { _ in 0.5 })
        let recipe = try SoundEdit.gain(100..<200, dB: 20).applied(to: F.whole(300))
        let result = SoundRender.render(source: source, recipe: recipe)
        XCTAssertEqual(result.channels[0][99], 1)
        XCTAssertEqual(result.channels[0][150], 10, accuracy: 1e-4)
        XCTAssertEqual(result.channels[1][150], 5, accuracy: 1e-4)
        XCTAssertEqual(result.channels[0][200], 1)
        XCTAssertEqual(result.channels[1][200], 0.5)
    }

    func testAwayFromAJoinEachFrameIsTheSourceTimesTheRecipesOwnGain() throws {
        var recipe = try SoundEdit.fadeIn(0..<2000).applied(to: F.whole(5000))
        recipe = try SoundEdit.gain(1000..<3000, dB: -3).applied(to: recipe)
        recipe = try SoundEdit.delete(3500..<4000).applied(to: recipe)
        recipe = try SoundEdit.fadeOut(3000..<4500).applied(to: recipe)
        let result = SoundRender.render(source: ones(5000), recipe: recipe).channels[0]
        XCTAssertEqual(result.count, recipe.frameCount)
        for frame in 0..<result.count where abs(frame - 3500) > SoundRender.dipFrames {
            XCTAssertEqual(result[frame], F.gain(recipe, at: frame), accuracy: 1e-6, "frame \(frame)")
        }
    }

    func testTheSamplesOfTheSourceAreCarriedNotJustItsGain() throws {
        let source = S.both(frames: 1000) { Float($0) / 1000 }
        let recipe = F.recipe([F.clip(100, 400), F.clip(600, 900)], frames: 1000)
        let result = SoundRender.render(source: source, recipe: recipe).channels[0]
        // Clear of the dips, which are 150 frames of a piece this short, a frame is the source's own sample.
        XCTAssertEqual(result[10], 0.110, accuracy: 1e-6)
        XCTAssertEqual(result[100], 0.200, accuracy: 1e-6)
        XCTAssertEqual(result[450], 0.750, accuracy: 1e-6)
    }
}
