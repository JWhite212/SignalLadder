import XCTest
@testable import NotificationCore

/// Every edit as a pure function from one recipe to the next (sound editor plan,
/// Task 2, Rulings 2, 11, 16 and 18).
final class SoundEditTests: XCTestCase {
    private typealias F = SoundFixtures

    /// Two pieces that are not neighbours in the source: 300 frames in all.
    private var joined: SoundRecipe { F.recipe([F.clip(0, 100), F.clip(500, 700)]) }

    // MARK: - Trim

    func testTrimKeepsTheSelectionAndDropsTheRest() throws {
        let trimmed = try SoundEdit.trim(100..<300).applied(to: F.whole(1000))
        XCTAssertEqual(trimmed.segments, [F.clip(100, 300)])
        XCTAssertEqual(trimmed.frameCount, 200)
    }

    func testTrimAcrossAJoinKeepsTheEndsOfBothPieces() throws {
        let trimmed = try SoundEdit.trim(50..<150).applied(to: joined)
        XCTAssertEqual(trimmed.segments, [F.clip(50, 100), F.clip(500, 550)])
    }

    func testTrimToAnEmptySelectionIsRefusedAsLeavingNothing() {
        XCTAssertEqual(F.refusal(.trim(40..<40), F.whole(100)), .wouldLeaveNothing)
    }

    func testTrimThenUndoGivesBackTheRecipe() throws {
        var history = SoundEditHistory(joined)
        let before = history.present
        try history.commit(.trim(50..<150))
        XCTAssertNotEqual(history.present, before)
        history.undo()
        XCTAssertEqual(history.present, before)
    }

    func testTrimInsideAFadedPieceKeepsTheFadeWhereItWas() throws {
        let faded = try SoundEdit.fadeIn(0..<1000).applied(to: F.whole(1000))
        let trimmed = try SoundEdit.trim(400..<600).applied(to: faded)
        XCTAssertEqual(trimmed.segments, [F.clip(400, 600, fades: [SoundFade(kind: .fadeIn, frames: 1000, into: 400)])])
        XCTAssertEqual(F.gain(trimmed, at: 0), F.gain(faded, at: 400))
        XCTAssertEqual(F.gain(trimmed, at: 199), F.gain(faded, at: 599))
    }

    // MARK: - Delete and cut

    func testDeleteTakesTheSelectionOutAndTheRestMovesUp() throws {
        let deleted = try SoundEdit.delete(100..<300).applied(to: F.whole(1000))
        XCTAssertEqual(deleted.segments, [F.clip(0, 100), F.clip(300, 1000)])
        XCTAssertEqual(deleted.frameCount, 800)
    }

    func testDeleteAcrossAJoinKeepsTheArithmeticOfLengths() throws {
        let recipe = joined
        let deleted = try SoundEdit.delete(50..<150).applied(to: recipe)
        XCTAssertEqual(deleted.segments, [F.clip(0, 50), F.clip(550, 700)])
        XCTAssertEqual(deleted.frameCount, recipe.frameCount - 100)
        for low in stride(from: 0, to: 300, by: 7) {
            for high in stride(from: low + 1, through: 300, by: 11) where !(low == 0 && high == 300) {
                let result = try SoundEdit.delete(low..<high).applied(to: recipe)
                XCTAssertEqual(result.frameCount, 300 - (high - low), "\(low)..<\(high)")
                XCTAssertEqual(result.segments.map(\.frames).reduce(0, +), result.frameCount)
            }
        }
    }

    func testDeletingTheWholeResultIsRefusedAsLeavingNothing() {
        XCTAssertEqual(F.refusal(.delete(0..<300), joined), .wouldLeaveNothing)
        XCTAssertEqual(F.refusal(.cut(0..<300), joined), .wouldLeaveNothing)
    }

    func testCutChangesTheRecipeExactlyAsDeleteDoes() throws {
        XCTAssertEqual(try SoundEdit.cut(50..<150).applied(to: joined), try SoundEdit.delete(50..<150).applied(to: joined))
    }

    // MARK: - Paste

    func testCutThenPastedBackInPlaceGivesTheOriginalRecipe() throws {
        let recipe = joined
        let copied = try recipe.excerpt(of: 50..<150)
        let cut = try SoundEdit.cut(50..<150).applied(to: recipe)
        XCTAssertEqual(cut.frameCount, recipe.frameCount - 100)
        let pasted = try SoundEdit.paste(copied, replacing: 50..<50).applied(to: cut)
        XCTAssertEqual(pasted, recipe, "the pieces rejoin, so no seam is left")
    }

    func testPasteAtAPointInsertsTheCopyAndLosesNothing() throws {
        let copied = try F.whole(1000).excerpt(of: 0..<100)
        let pasted = try SoundEdit.paste(copied, replacing: 500..<500).applied(to: F.whole(1000))
        XCTAssertEqual(pasted.segments, [F.clip(0, 500), F.clip(0, 100), F.clip(500, 1000)])
        XCTAssertEqual(pasted.frameCount, 1100)
    }

    func testPasteReplacesASelection() throws {
        let copied = try F.whole(1000).excerpt(of: 0..<100)
        let pasted = try SoundEdit.paste(copied, replacing: 200..<400).applied(to: F.whole(1000))
        XCTAssertEqual(pasted.frameCount, 1000 - 200 + 100)
        XCTAssertEqual(pasted.segments, [F.clip(0, 200), F.clip(0, 100), F.clip(400, 1000)])
    }

    func testPasteAtTheEndsPutsThePiecesFirstOrLast() throws {
        let copied = try F.whole(1000).excerpt(of: 10..<20)
        XCTAssertEqual(try SoundEdit.paste(copied, replacing: 0..<0).applied(to: F.whole(1000)).segments,
                       [F.clip(10, 20), F.clip(0, 1000)])
        XCTAssertEqual(try SoundEdit.paste(copied, replacing: 1000..<1000).applied(to: F.whole(1000)).segments,
                       [F.clip(0, 1000), F.clip(10, 20)])
    }

    func testPasteOfAnotherSoundsPiecesIsRefused() throws {
        let other = try SoundRecipe(wholeOf: F.source(1000, digest: "another")).excerpt(of: 0..<10)
        XCTAssertEqual(F.refusal(.paste(other, replacing: 0..<0), F.whole(1000)), .excerptFromAnotherSound)
    }

    func testPastedPiecesKeepTheirGainAndFades() throws {
        let recipe = try SoundEdit.fadeIn(0..<200).applied(to: SoundEdit.gain(0..<200, dB: 6).applied(to: F.whole(1000)))
        let copied = try recipe.excerpt(of: 0..<100)
        let pasted = try SoundEdit.paste(copied, replacing: 500..<500).applied(to: recipe)
        XCTAssertEqual(F.gain(recipe, at: 50), Float(pow(10, 6.0 / 20)) * 0.25, accuracy: 0.0001)
        XCTAssertEqual(F.gain(pasted, at: 550), F.gain(recipe, at: 50))
        XCTAssertEqual(F.gain(pasted, at: 599), F.gain(recipe, at: 99))
        XCTAssertEqual(F.gain(pasted, at: 600), F.gain(recipe, at: 500), "what was after it is as it was")
    }

    // MARK: - Duplicate

    func testDuplicatePlaysTheSelectionTwiceStraightAway() throws {
        let duplicated = try SoundEdit.duplicate(100..<200).applied(to: F.whole(1000))
        XCTAssertEqual(duplicated.segments, [F.clip(0, 200), F.clip(100, 1000)])
        XCTAssertEqual(duplicated.frameCount, 1100)
    }

    // MARK: - Repeat

    func testRepeatsLengthIsTheCountTimesTheSelectionPlusTheGaps() throws {
        for times in 2...5 {
            for gap in [0, 1, 480, 14_400] {
                let result = try SoundEdit.repeatSelection(100..<250, times: times, gapFrames: gap).applied(to: F.whole(1000))
                XCTAssertEqual(result.frameCount, 1000 - 150 + times * 150 + (times - 1) * gap, "\(times) times, gap \(gap)")
                let silences = result.segments.filter { if case .silence = $0 { return true } else { return false } }
                XCTAssertEqual(silences.count, gap == 0 ? 0 : times - 1)
            }
        }
    }

    func testRepeatPutsTheGapsBetweenThePlaysAndNotAfterTheLast() throws {
        let result = try SoundEdit.repeatSelection(0..<100, times: 3, gapFrames: 40).applied(to: F.whole(1000))
        // The last play meets what was after the selection, so the two are one piece again.
        XCTAssertEqual(result.segments, [
            F.clip(0, 100), .silence(frames: 40), F.clip(0, 100), .silence(frames: 40), F.clip(0, 1000),
        ])
    }

    func testRepeatNeedsAtLeastTwoPlaysAndNoMoreThanTheMost() {
        XCTAssertEqual(F.refusal(.repeatSelection(0..<10, times: 1, gapFrames: 0), F.whole(100)), .playsOutOfRange)
        XCTAssertEqual(F.refusal(.repeatSelection(0..<10, times: 0, gapFrames: 0), F.whole(100)), .playsOutOfRange)
        XCTAssertEqual(F.refusal(.repeatSelection(0..<10, times: -3, gapFrames: 0), F.whole(100)), .playsOutOfRange)
        XCTAssertEqual(F.refusal(.repeatSelection(0..<1, times: SoundEdit.mostPlays + 1, gapFrames: 0), F.whole(100)),
                       .playsOutOfRange)
        XCTAssertNil(F.refusal(.repeatSelection(0..<1, times: SoundEdit.mostPlays, gapFrames: 0), F.whole(100)))
    }

    func testRepeatsGapCannotBeNegativeOrLongerThanTheLongestResult() {
        XCTAssertEqual(F.refusal(.repeatSelection(0..<10, times: 2, gapFrames: -1), F.whole(100)), .gapOutOfRange)
        XCTAssertEqual(F.refusal(.repeatSelection(0..<10, times: 2, gapFrames: SoundRecipe.maximumFrames + 1), F.whole(100)),
                       .gapOutOfRange)
    }

    // MARK: - The longest result

    func testAnEditThatTakesTheResultToExactlyOneHundredTwentySecondsIsMade() throws {
        let half = SoundRecipe.maximumFrames / 2
        let doubled = try SoundEdit.duplicate(0..<half).applied(to: F.whole(half))
        XCTAssertEqual(doubled.frameCount, SoundRecipe.maximumFrames)
    }

    func testAnEditThatTakesTheResultPastOneHundredTwentySecondsIsRefusedWithTheLengthItWouldHave() throws {
        let half = SoundRecipe.maximumFrames / 2
        XCTAssertEqual(F.refusal(.duplicate(0..<(half + 1)), F.whole(half + 1)), .tooLong(frames: 2 * (half + 1)))
        XCTAssertEqual(F.refusal(.duplicate(0..<1), F.whole(SoundRecipe.maximumFrames)),
                       .tooLong(frames: SoundRecipe.maximumFrames + 1))
        let copied = try F.whole(SoundRecipe.maximumFrames).excerpt(of: 0..<10)
        XCTAssertEqual(F.refusal(.paste(copied, replacing: 0..<0), F.whole(SoundRecipe.maximumFrames)),
                       .tooLong(frames: SoundRecipe.maximumFrames + 10))
    }

    func testARepeatPastTheLongestResultIsRefusedBeforeItIsBuilt() {
        let result = F.refusal(.repeatSelection(0..<1, times: SoundEdit.mostPlays, gapFrames: SoundRecipe.maximumFrames),
                               F.whole(SoundRecipe.maximumFrames))
        XCTAssertEqual(result, .tooLong(frames: SoundRecipe.maximumFrames - 1 + SoundEdit.mostPlays
            + (SoundEdit.mostPlays - 1) * SoundRecipe.maximumFrames))
    }

    func testAnEditThatBringsAResultOverThirtySecondsDownIsMadeAndOneThatTakesItBackToThirtyCanBeSaved() throws {
        let long = F.whole(SoundRecipe.savableFrames * 2)
        XCTAssertFalse(long.canBeSaved)
        let kept = try SoundEdit.trim(0..<SoundRecipe.savableFrames).applied(to: long)
        XCTAssertTrue(kept.canBeSaved)
    }

    func testAnEditThatWouldLeaveMorePiecesThanARecipeMayHoldIsRefused() {
        let apart = (0..<3000).map { F.clip($0 * 2, $0 * 2 + 1) }
        let recipe = F.recipe(apart, frames: 100_000)
        XCTAssertEqual(F.refusal(.duplicate(0..<3000), recipe), .tooManyPieces)
        XCTAssertEqual(F.refusal(.repeatSelection(0..<3000, times: 2, gapFrames: 0), recipe), .tooManyPieces)
        XCTAssertEqual(F.refusal(.repeatSelection(0..<3000, times: SoundEdit.mostPlays, gapFrames: 1), recipe), .tooManyPieces)
    }

    // MARK: - Fades

    func testAFadeInRampsTheSelectionUpFromSilenceAndLeavesTheRest() throws {
        let faded = try SoundEdit.fadeIn(100..<200).applied(to: F.whole(1000))
        XCTAssertEqual(F.gain(faded, at: 99), 1)
        XCTAssertEqual(F.gain(faded, at: 100), 0)
        XCTAssertEqual(F.gain(faded, at: 150), 0.5, accuracy: 0.0001)
        XCTAssertEqual(F.gain(faded, at: 200), 1)
        XCTAssertEqual(faded.frameCount, 1000)
    }

    func testAFadeOutRampsTheSelectionDownToSilence() throws {
        let faded = try SoundEdit.fadeOut(100..<200).applied(to: F.whole(1000))
        XCTAssertEqual(F.gain(faded, at: 100), 0.99, accuracy: 0.0001)
        XCTAssertEqual(F.gain(faded, at: 199), 0)
        XCTAssertEqual(F.gain(faded, at: 200), 1)
    }

    func testAFadeAcrossTwoPiecesEqualsOneFade() throws {
        let faded = try SoundEdit.fadeIn(0..<600).applied(to: F.recipe([F.clip(0, 300), F.clip(1000, 1300)]))
        let single = try SoundEdit.fadeIn(0..<600).applied(to: F.recipe([F.clip(0, 600)]))
        XCTAssertEqual(faded.segments.count, 2)
        XCTAssertEqual(F.gain(single, at: 0), 0)
        XCTAssertEqual(F.gain(single, at: 450), 0.75, accuracy: 0.0001)
        for frame in 0..<600 {
            XCTAssertEqual(F.gain(faded, at: frame), F.gain(single, at: frame), "frame \(frame)")
        }
    }

    func testAFadeCutAndPutBackIsOneFadeAgain() throws {
        let faded = try SoundEdit.fadeIn(0..<600).applied(to: F.whole(1000))
        let copied = try faded.excerpt(of: 200..<400)
        let cut = try SoundEdit.cut(200..<400).applied(to: faded)
        XCTAssertEqual(cut.segments.count, 3, "the fade goes on from where it was after the cut, and is not joined to what follows it")
        XCTAssertEqual(try SoundEdit.paste(copied, replacing: 200..<200).applied(to: cut), faded)
    }

    func testAFadeOverSilenceFadesTheMaterialAroundItAtTheRightPlaces() throws {
        let recipe = F.recipe([F.clip(0, 100), .silence(frames: 100), F.clip(500, 600)])
        let faded = try SoundEdit.fadeIn(0..<300).applied(to: recipe)
        XCTAssertEqual(faded.segments[1], .silence(frames: 100), "silence takes no fade of its own")
        XCTAssertEqual(F.gain(faded, at: 250), 250.0 / 300, accuracy: 0.0001)
        XCTAssertEqual(F.gain(faded, at: 150), 0)
    }

    func testAFadeOnlyInSilenceChangesNothing() throws {
        let recipe = F.recipe([F.clip(0, 100), .silence(frames: 100)])
        XCTAssertEqual(try SoundEdit.fadeOut(100..<200).applied(to: recipe), recipe)
        let across = try SoundEdit.fadeOut(0..<200).applied(to: recipe)
        XCTAssertEqual(F.gain(across, at: 99), 0.5, accuracy: 0.0001, "the same fade over the sound and the silence after it")
    }

    // MARK: - Gain

    func testGainRaisesOrLowersTheSelectionAgainstTheRest() throws {
        let result = try SoundEdit.gain(100..<200, dB: 6).applied(to: F.whole(1000))
        XCTAssertEqual(result.segments, [F.clip(0, 100), F.clip(100, 200, gain: 6), F.clip(200, 1000)])
        XCTAssertEqual(try SoundEdit.gain(100..<200, dB: -6).applied(to: F.whole(1000)).segments[1], F.clip(100, 200, gain: -6))
    }

    func testGainAddsToWhatThePieceHad() throws {
        let once = try SoundEdit.gain(100..<200, dB: 6).applied(to: F.whole(1000))
        let twice = try SoundEdit.gain(150..<300, dB: -2.5).applied(to: once)
        XCTAssertEqual(twice.segments, [F.clip(0, 100), F.clip(100, 150, gain: 6), F.clip(150, 200, gain: 3.5),
                                        F.clip(200, 300, gain: -2.5), F.clip(300, 1000)])
    }

    func testAGainTakenAwayAgainLeavesNoSeam() throws {
        let up = try SoundEdit.gain(100..<200, dB: 0.1).applied(to: F.whole(1000))
        let more = try SoundEdit.gain(100..<200, dB: 0.2).applied(to: up)
        let back = try SoundEdit.gain(100..<200, dB: -0.3).applied(to: more)
        XCTAssertEqual(back, F.whole(1000))
    }

    func testGainOfNothingChangesNothing() throws {
        let recipe = try SoundEdit.gain(100..<200, dB: 6).applied(to: F.whole(1000))
        XCTAssertEqual(try SoundEdit.gain(0..<1000, dB: 0).applied(to: recipe), recipe)
    }

    func testGainThatIsNotANumberOrBeyondSixtyDecibelsInTotalIsRefused() throws {
        XCTAssertEqual(F.refusal(.gain(0..<10, dB: .nan), F.whole(100)), .gainOutOfRange)
        XCTAssertEqual(F.refusal(.gain(0..<10, dB: .infinity), F.whole(100)), .gainOutOfRange)
        XCTAssertEqual(F.refusal(.gain(0..<10, dB: 60.5), F.whole(100)), .gainOutOfRange)
        XCTAssertEqual(F.refusal(.gain(0..<10, dB: -61), F.whole(100)), .gainOutOfRange)
        let high = try SoundEdit.gain(0..<10, dB: 40).applied(to: F.whole(100))
        XCTAssertEqual(F.refusal(.gain(5..<20, dB: 30), high), .gainOutOfRange)
        XCTAssertNil(F.refusal(.gain(5..<20, dB: 20), high))
    }

    func testGainThatIsNotANumberIsRefusedOnSilenceToo() {
        let recipe = F.recipe([F.clip(0, 100), .silence(frames: 100)])
        XCTAssertEqual(F.refusal(.gain(100..<200, dB: .nan), recipe), .gainOutOfRange)
        XCTAssertEqual(F.refusal(.gain(100..<200, dB: 61), recipe), .gainOutOfRange)
        XCTAssertNil(F.refusal(.gain(100..<200, dB: 6), recipe), "a gain on silence is harmless, and is not an error")
    }

    func testGainLeavesSilenceAsItWas() throws {
        let recipe = F.recipe([F.clip(0, 100), .silence(frames: 100), F.clip(500, 600)])
        let result = try SoundEdit.gain(0..<300, dB: 6).applied(to: recipe)
        XCTAssertEqual(result.segments, [F.clip(0, 100, gain: 6), .silence(frames: 100), F.clip(500, 600, gain: 6)])
    }

    func testGainAndFadeGiveTheSameResultInEitherOrder() throws {
        let cases: [(gain: Range<Int>, fade: Range<Int>)] = [
            (100..<500, 100..<500), (100..<500, 300..<700), (300..<700, 100..<500), (0..<1000, 200..<300),
        ]
        for (gain, fade) in cases {
            for edit in [SoundEdit.fadeIn(fade), .fadeOut(fade)] {
                let one = try edit.applied(to: SoundEdit.gain(gain, dB: 6).applied(to: F.whole(1000)))
                let other = try SoundEdit.gain(gain, dB: 6).applied(to: edit.applied(to: F.whole(1000)))
                XCTAssertEqual(one, other, "gain \(gain), fade \(fade)")
                XCTAssertNotEqual(one, F.whole(1000))
                XCTAssertGreaterThan(one.segments.count, 1)
            }
        }
    }

    func testTwoFadesInEitherOrderGiveTheSameResult() throws {
        let one = try SoundEdit.fadeOut(300..<700).applied(to: SoundEdit.fadeIn(100..<500).applied(to: F.whole(1000)))
        let other = try SoundEdit.fadeIn(100..<500).applied(to: SoundEdit.fadeOut(300..<700).applied(to: F.whole(1000)))
        XCTAssertEqual(one, other)
        XCTAssertEqual(F.gain(one, at: 400), 0.75 * (299.0 / 400) , accuracy: 0.0001, "frames 300 to 500 are under both fades")
    }

    // MARK: - Selections

    func testAnEditThatNeedsASelectionRefusesAnEmptyOne() {
        let recipe = F.whole(1000)
        let edits: [SoundEdit] = [
            .delete(10..<10), .cut(10..<10), .duplicate(10..<10), .fadeIn(10..<10), .fadeOut(10..<10),
            .gain(10..<10, dB: 3), .repeatSelection(10..<10, times: 2, gapFrames: 0),
        ]
        for edit in edits {
            XCTAssertEqual(F.refusal(edit, recipe), .emptySelection, "\(edit)")
        }
    }

    func testAnEditRefusesASelectionOutsideTheResult() throws {
        let recipe = F.whole(1000)
        let copied = try recipe.excerpt(of: 0..<10)
        let outsides: [Range<Int>] = [(-1)..<10, 990..<1001, 1001..<1002, (-5)..<(-2)]
        for outside in outsides {
            let edits: [SoundEdit] = [
                .trim(outside), .delete(outside), .cut(outside), .paste(copied, replacing: outside), .duplicate(outside),
                .fadeIn(outside), .fadeOut(outside), .gain(outside, dB: 3),
                .repeatSelection(outside, times: 2, gapFrames: 0),
            ]
            for edit in edits {
                XCTAssertEqual(F.refusal(edit, recipe), .selectionOutsideSound, "\(edit) \(outside)")
            }
        }
    }

    // MARK: - Held by construction

    /// A few hundred edits, chosen by a fixed sequence of numbers, made one on
    /// another. Each result must be a recipe the initialiser would accept as it
    /// stands, which is what makes the invariants a matter of construction and
    /// not of care, and each must be as long as the arithmetic of its edit says.
    func testEveryRecipeAnyEditMakesIsOneTheInitialiserAcceptsAsItStands() throws {
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        var made = 0
        var refused = 0
        for _ in 0..<12 {
            var recipe = F.whole(4000)
            for _ in 0..<60 {
                let count = recipe.frameCount
                let low = next(count)
                let high = min(count, low + 1 + next(max(count / 3, 1)))
                let range = low..<high
                let edit: SoundEdit
                var expected = count
                switch next(9) {
                case 0: edit = .trim(range); expected = range.count
                case 1: edit = .delete(range); expected = count - range.count
                case 2: edit = .cut(range); expected = count - range.count
                case 3:
                    let copied = try recipe.excerpt(of: range)
                    edit = .paste(copied, replacing: low..<low); expected = count + copied.frameCount
                case 4: edit = .duplicate(range); expected = count + range.count
                case 5: edit = .fadeIn(range)
                case 6: edit = .fadeOut(range)
                case 7: edit = .gain(range, dB: Double(next(25)) - 12)
                default:
                    let times = 2 + next(3), gap = next(3) * 20
                    edit = .repeatSelection(range, times: times, gapFrames: gap)
                    expected = count - range.count + times * range.count + (times - 1) * gap
                }
                do {
                    let result = try edit.applied(to: recipe)
                    made += 1
                    XCTAssertEqual(result.frameCount, expected, "\(edit)")
                    XCTAssertEqual(try SoundRecipe(source: result.source, segments: result.segments), result, "\(edit)")
                    recipe = result
                } catch is SoundEditRefusal {
                    refused += 1
                }
                if recipe.frameCount < 40 { recipe = F.whole(4000) }
            }
        }
        XCTAssertGreaterThan(made, 400)
        XCTAssertLessThan(refused, made)
    }
}
