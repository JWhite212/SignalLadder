import XCTest
@testable import NotificationCore

/// What a recipe is, and what it refuses to be (sound editor plan, Task 2,
/// Rulings 2, 3, 11 and 18): the invariants are held by construction.
final class SoundRecipeTests: XCTestCase {
    private typealias F = SoundFixtures

    private func fault(_ segments: [SoundSegment], frames: Int = 1000, file: StaticString = #filePath,
                       line: UInt = #line) -> SoundRecipe.Fault? {
        do {
            _ = try SoundRecipe(source: F.source(frames), segments: segments)
            return nil
        } catch let fault as SoundRecipe.Fault {
            return fault
        } catch {
            XCTFail("\(error)", file: file, line: line)
            return nil
        }
    }

    // MARK: - A source

    func testASourceNeedsANameADigestAndSomeFrames() {
        XCTAssertNotNil(SoundRecipe.Source(name: "a.wav", frames: 1, digest: "d"))
        XCTAssertNil(SoundRecipe.Source(name: " ", frames: 1, digest: "d"))
        XCTAssertNil(SoundRecipe.Source(name: "a.wav", frames: 1, digest: ""))
        XCTAssertNil(SoundRecipe.Source(name: "a.wav", frames: 0, digest: "d"))
        XCTAssertNil(SoundRecipe.Source(name: "a.wav", frames: -5, digest: "d"))
    }

    // MARK: - The whole source

    func testTheWholeOfASourceIsOnePieceAndIsTheOriginal() {
        let recipe = F.whole(1000)
        XCTAssertEqual(recipe.segments, [F.clip(0, 1000)])
        XCTAssertEqual(recipe.frameCount, 1000)
        XCTAssertTrue(recipe.isOriginal)
    }

    func testARecipeThatIsNotTheWholeIsNotTheOriginal() {
        let recipe = F.recipe([F.clip(0, 500)])
        XCTAssertFalse(recipe.isOriginal)
        XCTAssertEqual(recipe.original.segments, [F.clip(0, 10_000)])
        XCTAssertEqual(recipe.original.source, recipe.source)
    }

    func testASourceOfExactlyOneHundredTwentySecondsOpens() {
        XCTAssertEqual(SoundRecipe.maximumFrames, 5_760_000)
        XCTAssertNoThrow(try SoundRecipe(wholeOf: F.source(5_760_000)))
    }

    func testASourceOverOneHundredTwentySecondsCannotBeOpenedAndSaysItsLength() {
        XCTAssertThrowsError(try SoundRecipe(wholeOf: F.source(5_760_001))) { error in
            XCTAssertEqual(error as? SoundEditRefusal, .sourceTooLong(frames: 5_760_001))
        }
    }

    func testDurationIsFramesOverTheRate() {
        XCTAssertEqual(F.whole(96_000).duration, 2)
    }

    // MARK: - What a recipe refuses

    func testAListOfNoPiecesIsRefused() {
        XCTAssertEqual(fault([]), .noPieces)
    }

    func testAnEmptyPieceIsRefusedWhereverItIs() {
        XCTAssertEqual(fault([F.clip(0, 10), F.clip(20, 20)]), .emptyPiece(index: 1))
        XCTAssertEqual(fault([F.clip(30, 20)]), .emptyPiece(index: 0))
        XCTAssertEqual(fault([F.clip(0, 10), .silence(frames: 0)]), .emptyPiece(index: 1))
        XCTAssertEqual(fault([.silence(frames: -4)]), .emptyPiece(index: 0))
    }

    func testAPieceOutsideTheSourceIsRefused() {
        XCTAssertEqual(fault([F.clip(0, 1001)]), .pieceOutsideSource(index: 0))
        XCTAssertEqual(fault([F.clip(0, 10), F.clip(-1, 10)]), .pieceOutsideSource(index: 1))
        XCTAssertNil(fault([F.clip(0, 1000)]))
    }

    func testAFadeThatIsEmptyStartsBeforeItselfOrRunsPastItsPieceIsRefused() {
        let empty = SoundFade(kind: .fadeIn, frames: 0, into: 0)
        let before = SoundFade(kind: .fadeIn, frames: 100, into: -1)
        let past = SoundFade(kind: .fadeOut, frames: 100, into: 51)
        XCTAssertEqual(fault([F.clip(0, 50, fades: [empty])]), .badFade(index: 0))
        XCTAssertEqual(fault([F.clip(0, 50, fades: [before])]), .badFade(index: 0))
        XCTAssertEqual(fault([F.clip(0, 50, fades: [past])]), .badFade(index: 0))
        XCTAssertNil(fault([F.clip(0, 50, fades: [SoundFade(kind: .fadeOut, frames: 100, into: 50)])]))
    }

    func testAFadeWhoseNumbersWouldOverflowIsRefusedAsABadFadeAndNotATrap() {
        let farInto = SoundFade(kind: .fadeIn, frames: 100, into: Int.max)
        let longBefore = SoundFade(kind: .fadeIn, frames: Int.max, into: Int.max)
        let negative = SoundFade(kind: .fadeOut, frames: Int.min, into: 0)
        XCTAssertEqual(fault([F.clip(0, 50, fades: [farInto])]), .badFade(index: 0))
        XCTAssertEqual(fault([F.clip(0, 50, fades: [longBefore])]), .badFade(index: 0))
        XCTAssertEqual(fault([F.clip(0, 50, fades: [negative])]), .badFade(index: 0))
        XCTAssertNil(fault([F.clip(0, 50, fades: [SoundFade(kind: .fadeIn, frames: Int.max, into: 0)])]),
                     "a fade may be as long as it likes, so long as the piece lies inside it")
    }

    func testAGainThatIsNotANumberOrIsBeyondSixtyDecibelsIsRefused() {
        XCTAssertEqual(fault([F.clip(0, 10, gain: .nan)]), .badGain(index: 0))
        XCTAssertEqual(fault([F.clip(0, 10, gain: .infinity)]), .badGain(index: 0))
        XCTAssertEqual(fault([F.clip(0, 10, gain: 60.01)]), .badGain(index: 0))
        XCTAssertEqual(fault([F.clip(0, 10, gain: -61)]), .badGain(index: 0))
        XCTAssertNil(fault([F.clip(0, 10, gain: 60)]))
        XCTAssertNil(fault([F.clip(0, 10, gain: -60)]))
    }

    func testAResultOverOneHundredTwentySecondsIsRefused() {
        let source = 5_760_000
        XCTAssertNil(fault([F.clip(0, source)], frames: source))
        XCTAssertEqual(fault([F.clip(0, source), .silence(frames: 1)], frames: source), .tooLong(frames: source + 1))
    }

    func testASilenceOfAnyLengthIsRefusedAsTooLongWhereverItIsAndNotATrap() {
        XCTAssertEqual(fault([.silence(frames: Int.max)]), .tooLong(frames: Int.max))
        XCTAssertEqual(fault([F.clip(0, 10), .silence(frames: Int.max)]), .tooLong(frames: Int.max),
                       "after another piece the total would pass the largest integer")
        XCTAssertEqual(fault([F.clip(0, 10), .silence(frames: Int.max - 5)]), .tooLong(frames: Int.max))
        XCTAssertEqual(fault([.silence(frames: Int.max), .silence(frames: Int.max)]), .tooLong(frames: Int.max))
    }

    func testASourceOverOneHundredTwentySecondsIsRefusedByTheInitialiserToo() {
        XCTAssertEqual(fault([F.clip(0, 10)], frames: 5_760_001), .sourceTooLong(frames: 5_760_001))
    }

    func testMoreThanTheMostPiecesIsRefused() {
        let apart = (0...SoundRecipe.maximumSegments).map { F.clip($0 * 2, $0 * 2 + 1) }
        XCTAssertEqual(fault(apart, frames: 100_000), .tooManyPieces(count: SoundRecipe.maximumSegments + 1))
        XCTAssertNil(fault(Array(apart.dropLast()), frames: 100_000))
    }

    func testEveryFaultSaysWhatIsWrongInWords() {
        let faults: [SoundRecipe.Fault] = [
            .sourceTooLong(frames: 1), .noPieces, .tooManyPieces(count: 1), .emptyPiece(index: 2),
            .pieceOutsideSource(index: 2), .badFade(index: 2), .badGain(index: 2), .tooLong(frames: 1),
        ]
        for fault in faults {
            XCTAssertFalse(fault.description.isBlank, "\(fault)")
        }
        XCTAssertTrue(SoundRecipe.Fault.emptyPiece(index: 2).description.contains("piece 3"), "pieces are counted from one")
    }

    // MARK: - One form

    func testNeighboursThatAreOnePieceCutInTwoAreOnePiece() {
        XCTAssertEqual(F.recipe([F.clip(0, 100), F.clip(100, 250)]).segments, [F.clip(0, 250)])
    }

    func testPiecesThatMeetAtADifferentGainAreTwoPieces() {
        let recipe = F.recipe([F.clip(0, 100), F.clip(100, 250, gain: 3)])
        XCTAssertEqual(recipe.segments.count, 2)
    }

    func testPiecesThatDoNotMeetInTheSourceAreTwoPieces() {
        XCTAssertEqual(F.recipe([F.clip(0, 100), F.clip(101, 250)]).segments.count, 2)
        XCTAssertEqual(F.recipe([F.clip(100, 200), F.clip(0, 100)]).segments.count, 2)
    }

    func testSilenceBesideSilenceIsOneSilence() {
        let recipe = F.recipe([F.clip(0, 10), .silence(frames: 5), .silence(frames: 7), F.clip(20, 30)])
        XCTAssertEqual(recipe.segments, [F.clip(0, 10), .silence(frames: 12), F.clip(20, 30)])
    }

    func testFadesThatCarryOnFromOnePieceToTheNextMakeOnePiece() {
        let first = F.clip(0, 100, fades: [SoundFade(kind: .fadeIn, frames: 400, into: 0)])
        let second = F.clip(100, 250, fades: [SoundFade(kind: .fadeIn, frames: 400, into: 100)])
        XCTAssertEqual(F.recipe([first, second]).segments,
                       [F.clip(0, 250, fades: [SoundFade(kind: .fadeIn, frames: 400, into: 0)])])
    }

    func testFadesThatDoNotCarryOnLeaveTwoPieces() {
        let fade = SoundFade(kind: .fadeIn, frames: 400, into: 0)
        let restarted = F.clip(100, 250, fades: [SoundFade(kind: .fadeIn, frames: 400, into: 0)])
        let longer = F.clip(100, 250, fades: [SoundFade(kind: .fadeIn, frames: 401, into: 100)])
        let other = F.clip(100, 250, fades: [SoundFade(kind: .fadeOut, frames: 400, into: 100)])
        let none = F.clip(100, 250)
        for next in [restarted, longer, other, none] {
            XCTAssertEqual(F.recipe([F.clip(0, 100, fades: [fade]), next]).segments.count, 2, "\(next)")
        }
    }

    func testAGainIsKeptToHundredthsOfADecibel() {
        XCTAssertEqual(F.recipe([F.clip(0, 10, gain: 1.234)]).segments, [F.clip(0, 10, gain: 1.23)])
    }

    func testFadesAreKeptInOneOrder() {
        let a = SoundFade(kind: .fadeOut, frames: 50, into: 0)
        let b = SoundFade(kind: .fadeIn, frames: 80, into: 0)
        let c = SoundFade(kind: .fadeIn, frames: 20, into: 0)
        XCTAssertEqual(F.recipe([F.clip(0, 10, fades: [a, b, c])]).segments, [F.clip(0, 10, fades: [c, b, a])])
        XCTAssertEqual(F.recipe([F.clip(0, 10, fades: [c, a, b])]), F.recipe([F.clip(0, 10, fades: [b, c, a])]))
    }

    // MARK: - Saving

    func testAResultCanBeSavedUpToThirtySecondsAndNotAFrameMore() {
        XCTAssertEqual(SoundRecipe.savableFrames, 1_440_000)
        XCTAssertTrue(F.recipe([F.clip(0, 1_440_000)], frames: 2_000_000).canBeSaved)
        XCTAssertFalse(F.recipe([F.clip(0, 1_440_001)], frames: 2_000_000).canBeSaved)
    }

    // MARK: - Copying

    func testAnExcerptIsThePiecesInTheRangeCutAtItsEdges() throws {
        let recipe = F.recipe([F.clip(0, 100), F.clip(500, 700)])
        let excerpt = try recipe.excerpt(of: 50..<150)
        XCTAssertEqual(excerpt.segments, [F.clip(50, 100), F.clip(500, 550)])
        XCTAssertEqual(excerpt.frameCount, 100)
        XCTAssertEqual(excerpt.sourceDigest, recipe.source.digest)
    }

    func testAnExcerptOfNothingOrOfWhatIsNotThereIsRefused() {
        let recipe = F.whole(100)
        XCTAssertThrowsError(try recipe.excerpt(of: 10..<10)) { XCTAssertEqual($0 as? SoundEditRefusal, .emptySelection) }
        XCTAssertThrowsError(try recipe.excerpt(of: 50..<101)) {
            XCTAssertEqual($0 as? SoundEditRefusal, .selectionOutsideSound)
        }
        XCTAssertThrowsError(try recipe.excerpt(of: (-1)..<5)) {
            XCTAssertEqual($0 as? SoundEditRefusal, .selectionOutsideSound)
        }
    }

    // MARK: - What a piece does to the source

    func testAPieceAtSixDecibelsDoublesTheSourceAndSilencePlaysNothing() {
        XCTAssertEqual(F.clip(0, 10, gain: 6).gain(atPieceFrame: 3), 1.9953, accuracy: 0.0001)
        XCTAssertEqual(F.clip(0, 10).gain(atPieceFrame: 3), 1)
        XCTAssertEqual(SoundSegment.silence(frames: 10).gain(atPieceFrame: 3), 0)
    }

    func testAFadeInBeginsAtZeroAndAFadeOutEndsAtZero() {
        let fadeIn = SoundFade(kind: .fadeIn, frames: 100, into: 0)
        let fadeOut = SoundFade(kind: .fadeOut, frames: 100, into: 0)
        XCTAssertEqual(fadeIn.gain(atPieceFrame: 0), 0)
        XCTAssertEqual(fadeOut.gain(atPieceFrame: 99), 0)
        XCTAssertEqual(fadeIn.gain(atPieceFrame: 50), 0.5, accuracy: 0.0001)
        XCTAssertEqual(fadeOut.gain(atPieceFrame: 49), 0.5, accuracy: 0.0001)
        XCTAssertLessThan(fadeIn.gain(atPieceFrame: 99), 1)
        XCTAssertEqual(fadeOut.gain(atPieceFrame: 0), 0.99, accuracy: 0.0001)
    }

    func testAFadeIsReadFromHowFarIntoItAPieceBegins() {
        let later = SoundFade(kind: .fadeIn, frames: 100, into: 40)
        XCTAssertEqual(later.gain(atPieceFrame: 10), 0.5, accuracy: 0.0001)
    }

    func testAFadeDoesNothingBeyondItsOwnLength() {
        let fade = SoundFade(kind: .fadeIn, frames: 10, into: 0)
        XCTAssertEqual(fade.gain(atPieceFrame: 10), 1)
        XCTAssertEqual(fade.gain(atPieceFrame: -1), 1)
    }

    func testAPieceUnderTwoFadesAndAGainMultipliesThemAll() {
        let piece = F.clip(0, 100, gain: 6, fades: [SoundFade(kind: .fadeIn, frames: 100, into: 0),
                                                    SoundFade(kind: .fadeOut, frames: 100, into: 0)])
        let expected = Float(pow(10, 6.0 / 20)) * 0.5 * 0.49
        XCTAssertEqual(piece.gain(atPieceFrame: 50), expected, accuracy: 0.0001)
    }
}
