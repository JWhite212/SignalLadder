import XCTest
@testable import NotificationCore

/// What each of the sound editor's edit commands comes to, before it is handed to the history, and where the playhead
/// and the selection go after it (sound editor plan, Rulings 4 and 18 and Task 8). The window only hands on what this
/// says, so every case is a test and none is a line of the window.
final class SoundEditorEditingTests: XCTestCase {
    /// A square wave that changes sign at every thousandth frame, so that where an edge is moved to is known.
    private let samples = SoundSignals.both(frames: 8000) { (($0 / 1000) % 2 == 0) ? 0.5 : -0.5 }
    /// Whose edges are moved to the changes of sign at 1000 and 3000.
    private let selection = 1100..<3050
    private let snapped = 1000..<3000

    private func plan(_ command: SoundEditorText.Command, selection: Range<Int>? = 1100..<3050, playhead: Int = 5020,
                      clipboard: SoundExcerpt? = nil, gainDB: Double = 6, plays: Int = 3,
                      gapSeconds: Double = 0.3) -> Result<SoundEditorEdit, SoundEditRefusal>? {
        SoundEditorEditing.plan(command, selection: selection, playhead: playhead, samples: samples, clipboard: clipboard,
                                gainDB: gainDB, plays: plays, gapSeconds: gapSeconds)
    }

    /// The edit a command plans, which fails the test when it is refused or has no plan.
    private func planned(_ command: SoundEditorText.Command, selection: Range<Int>? = 1100..<3050, playhead: Int = 5020,
                         clipboard: SoundExcerpt? = nil, gainDB: Double = 6, plays: Int = 3, gapSeconds: Double = 0.3,
                         file: StaticString = #filePath, line: UInt = #line) throws -> SoundEditorEdit {
        let result = try XCTUnwrap(plan(command, selection: selection, playhead: playhead, clipboard: clipboard, gainDB: gainDB,
                                        plays: plays, gapSeconds: gapSeconds), "\(command) has a plan", file: file, line: line)
        return try result.get()
    }

    private func excerpt() throws -> SoundExcerpt { try SoundFixtures.whole(8000).excerpt(of: 100..<200) }

    // MARK: - Where an edge goes (Ruling 4)

    func testTheEdgesOfASelectionAreMovedToTheNearestChangeOfSign() {
        XCTAssertEqual(SoundEditorEditing.snapped(selection, in: samples), snapped)
        // The sign changes every thousand frames, so each edge goes to the thousand it is within 240 frames of, whichever
        // side it is on.
        XCTAssertEqual(SoundEditorEditing.snapped(1900..<3900, in: samples), 2000..<4000)
        XCTAssertEqual(SoundEditorEditing.snapped(2100..<4100, in: samples), 2000..<4000)
    }

    func testAnEdgeFurtherFromAChangeOfSignThanTheWindowIsLeftWhereItIs() {
        // 2300 is 300 frames from the change of sign at 2000, which is more than 5 ms (240 frames), and the square
        // wave is as quiet at every frame, so the edge stays.
        XCTAssertEqual(SoundEditorEditing.snapped(2300..<4400, in: samples), 2300..<4400)
    }

    func testTheEndsOfTheSoundAreNotMovedSoASelectionMadeToAnEndStillReachesIt() {
        XCTAssertEqual(SoundEditorEditing.snapped(0..<8000, in: samples), 0..<8000)
        XCTAssertEqual(SoundEditorEditing.snapped(0..<3050, in: samples), 0..<3000)
        XCTAssertEqual(SoundEditorEditing.snapped(1100..<8000, in: samples), 1000..<8000)
    }

    func testASelectionThatBothEdgesWouldCollapseIntoOnePointIsLeftWhereItIs() {
        // Both edges are nearest to the one change of sign at 1000, which would select nothing.
        XCTAssertEqual(ZeroCrossing.nearest(to: 1001, in: samples), ZeroCrossing.nearest(to: 1003, in: samples),
                       "the two do land on one frame")
        XCTAssertEqual(SoundEditorEditing.snapped(1001..<1003, in: samples), 1001..<1003)
    }

    func testAnEdgeThatTheQuietestFrameWouldTakeToTheStartOfTheSoundIsNotTrimmedOrGivenGainAsIfItWereAll() throws {
        // A rise from just above silence with no change of sign in it, so that the quietest frame within 5 ms of the
        // edge at 3 is the first of the sound, and the snapped selection is all of it.
        let rise = SoundSignals.both(frames: 8000) { 0.001 + Float($0) * 0.0001 }
        XCTAssertEqual(SoundEditorEditing.snapped(3..<8000, in: rise), 0..<8000, "the case this holds: snapped is all of it")
        func edit(_ command: SoundEditorText.Command) throws -> SoundEdit? {
            let result = SoundEditorEditing.plan(command, selection: 3..<8000, playhead: 0, samples: rise, clipboard: nil,
                                                 gainDB: 6, plays: 3, gapSeconds: 0.3)
            return try XCTUnwrap(result, "\(command)").get().edit
        }
        // Trim of all of a sound changes nothing, and Gain on all of it is not offered (Ruling 16): both are made of what
        // was selected and not of what the snap would have made all of.
        XCTAssertEqual(try edit(.trim), .trim(3..<8000))
        XCTAssertEqual(try edit(.gain), .gain(3..<8000, dB: 6))
    }

    func testASelectionOutsideTheSoundIsHeldToIt() {
        XCTAssertEqual(SoundEditorEditing.snapped(-50..<9000, in: samples), 0..<8000)
    }

    // MARK: - Each command

    func testTrimDeleteDuplicateAndTheFadesAreMadeOnTheSnappedEdges() throws {
        XCTAssertEqual(try planned(.trim), SoundEditorEdit(copying: nil, edit: .trim(snapped)))
        XCTAssertEqual(try planned(.delete), SoundEditorEdit(copying: nil, edit: .delete(snapped)))
        XCTAssertEqual(try planned(.duplicate), SoundEditorEdit(copying: nil, edit: .duplicate(snapped)))
        XCTAssertEqual(try planned(.fadeIn), SoundEditorEdit(copying: nil, edit: .fadeIn(snapped)))
        XCTAssertEqual(try planned(.fadeOut), SoundEditorEdit(copying: nil, edit: .fadeOut(snapped)))
    }

    func testCutTakesItsCopyOfWhatItCutsAndCopyEditsNothing() throws {
        XCTAssertEqual(try planned(.cut), SoundEditorEdit(copying: snapped, edit: .cut(snapped)))
        XCTAssertEqual(try planned(.copy), SoundEditorEdit(copying: snapped, edit: nil))
    }

    func testGainIsOfTheSnappedSelectionByTheGainGiven() throws {
        XCTAssertEqual(try planned(.gain).edit, .gain(snapped, dB: 6))
        XCTAssertEqual(try planned(.gain, gainDB: -4.5).edit, .gain(snapped, dB: -4.5))
    }

    func testRepeatPlaysTheSnappedSelectionTheTimesAskedWithTheGapInWholeFrames() throws {
        XCTAssertEqual(try planned(.repeatSelection).edit, .repeatSelection(snapped, times: 3, gapFrames: 14_400),
                       "0.3 seconds at 48 kHz")
        XCTAssertEqual(try planned(.repeatSelection, plays: 5, gapSeconds: 0).edit,
                       .repeatSelection(snapped, times: 5, gapFrames: 0))
    }

    func testACommandThatNeedsASelectionIsRefusedWithNone() {
        for command in [SoundEditorText.Command.trim, .delete, .cut, .copy, .duplicate, .fadeIn, .fadeOut, .gain,
                        .repeatSelection] {
            for none in [nil, 40..<40] as [Range<Int>?] {
                XCTAssertEqual(plan(command, selection: none), .failure(.emptySelection), "\(command) \(String(describing: none))")
            }
        }
    }

    func testPasteReplacesTheSnappedSelection() throws {
        let clip = try excerpt()
        XCTAssertEqual(try planned(.paste, clipboard: clip), SoundEditorEdit(copying: nil, edit: .paste(clip, replacing: snapped)))
    }

    func testPasteWithNothingSelectedGoesInAtThePlayheadMovedToAChangeOfSignAsAnEdgeIs() throws {
        let clip = try excerpt()
        XCTAssertEqual(try planned(.paste, selection: nil, playhead: 5020, clipboard: clip).edit,
                       .paste(clip, replacing: 5000..<5000))
        XCTAssertEqual(try planned(.paste, selection: nil, playhead: 0, clipboard: clip).edit, .paste(clip, replacing: 0..<0))
        XCTAssertEqual(try planned(.paste, selection: nil, playhead: 8000, clipboard: clip).edit,
                       .paste(clip, replacing: 8000..<8000), "the end of the sound is not a cut")
    }

    func testPasteWithNothingOnTheClipboardHasNothingToDo() {
        XCTAssertNil(plan(.paste))
        XCTAssertNil(plan(.paste, selection: nil))
    }

    func testACommandThatIsNotAnEditHasNoPlan() {
        for command in [SoundEditorText.Command.play, .stop, .loopSelection, .undo, .redo, .resetToOriginal, .selectAll,
                        .clearSelection, .zoomIn, .zoomOut] {
            XCTAssertNil(plan(command), "\(command)")
        }
    }

    func testEveryCommandIsEitherAnEditThatHasAPlanOrNotAnEditAtAll() throws {
        let clip = try excerpt()
        let edits: Set<SoundEditorText.Command> = [.trim, .delete, .cut, .copy, .paste, .duplicate, .fadeIn, .fadeOut, .gain,
                                                   .repeatSelection]
        for command in SoundEditorText.Command.allCases {
            XCTAssertEqual(plan(command, clipboard: clip) != nil, edits.contains(command), "\(command)")
        }
    }

    // MARK: - Through the history

    private func recipeAfter(_ planned: SoundEditorEdit, from recipe: SoundRecipe) throws -> SoundRecipe {
        var history = SoundEditHistory(recipe)
        try history.commit(try XCTUnwrap(planned.edit))
        return history.present
    }

    func testCuttingAPieceAndPastingItBackWhereItWasGivesTheRecipeBack() throws {
        let original = SoundFixtures.whole(8000)
        let cut = try planned(.cut)
        let copied = try original.excerpt(of: try XCTUnwrap(cut.copying))
        let without = try recipeAfter(cut, from: original)
        XCTAssertEqual(without.frameCount, 8000 - snapped.count)
        let pasted = try SoundEdit.paste(copied, replacing: snapped.lowerBound..<snapped.lowerBound).applied(to: without)
        XCTAssertEqual(pasted, original, "the pieces that were one are one again, so there is no seam")
    }

    func testTheWholeOfASoundCannotBeDeletedAndTheHistoryRefusesItWithTheReasonThePlanLeavesToIt() throws {
        let made = try planned(.delete, selection: 0..<8000)
        XCTAssertEqual(made.edit, .delete(0..<8000))
        var history = SoundEditHistory(SoundFixtures.whole(8000))
        XCTAssertThrowsError(try history.commit(try XCTUnwrap(made.edit))) {
            XCTAssertEqual($0 as? SoundEditRefusal, .wouldLeaveNothing)
        }
        XCTAssertFalse(history.canUndo, "a refused edit adds nothing to the past")
    }

    func testDuplicateMakesTheSnappedPieceTwiceAndTheLengthIsTheSumOfThePieces() throws {
        let result = try recipeAfter(try planned(.duplicate), from: SoundFixtures.whole(8000))
        XCTAssertEqual(result.frameCount, 8000 + snapped.count)
    }

    func testARepeatOfTheSnappedSelectionIsTheSelectionTimesTheCountPlusTheGaps() throws {
        let result = try recipeAfter(try planned(.repeatSelection), from: SoundFixtures.whole(8000))
        XCTAssertEqual(result.frameCount, 8000 - snapped.count + 3 * snapped.count + 2 * 14_400)
    }

    // MARK: - What the controls hold to

    func testAGainIsHeldToTheRangeTheWindowOffers() {
        XCTAssertEqual(SoundEditorEditing.gainRangeDB, -24...24)
        XCTAssertEqual(SoundEditorEditing.clampedGainDB(30), 24)
        XCTAssertEqual(SoundEditorEditing.clampedGainDB(-30), -24)
        XCTAssertEqual(SoundEditorEditing.clampedGainDB(5), 5)
        XCTAssertEqual(SoundEditorEditing.clampedGainDB(.nan), 0, "not a number is no gain")
        XCTAssertEqual(SoundEditorEditing.clampedGainDB(.infinity), 24)
    }

    func testEveryGainTheWindowOffersIsOneTheEditAccepts() {
        for dB in [SoundEditorEditing.gainRangeDB.lowerBound, SoundEditorEditing.gainRangeDB.upperBound] {
            XCTAssertNil(SoundFixtures.refusal(.gain(0..<100, dB: dB), SoundFixtures.whole(8000)), "\(dB)")
        }
    }

    func testThePlaysOfARepeatAreHeldToTwoAndTheMostTheWindowOffers() {
        XCTAssertEqual(SoundEditorEditing.playsRange.lowerBound, 2)
        XCTAssertLessThanOrEqual(SoundEditorEditing.playsRange.upperBound, SoundEdit.mostPlays)
        XCTAssertEqual(SoundEditorEditing.clampedPlays(1), 2)
        XCTAssertEqual(SoundEditorEditing.clampedPlays(-5), 2)
        XCTAssertEqual(SoundEditorEditing.clampedPlays(7), 7)
        XCTAssertEqual(SoundEditorEditing.clampedPlays(Int.max), SoundEditorEditing.playsRange.upperBound)
        XCTAssertTrue(SoundEditorEditing.playsRange.contains(SoundEditorEditing.defaultPlays))
    }

    func testTheGapOfARepeatIsHeldToTheRangeAndKeptToHundredthsSoAStepNeverReadsAsAFloatsError() {
        XCTAssertEqual(SoundEditorEditing.clampedGapSeconds(-1), 0)
        XCTAssertEqual(SoundEditorEditing.clampedGapSeconds(99), SoundEditorEditing.gapRangeSeconds.upperBound)
        XCTAssertEqual(SoundEditorEditing.clampedGapSeconds(0.1 + 0.2), 0.3)
        XCTAssertEqual(SoundEditorEditing.clampedGapSeconds(.nan), 0)
        XCTAssertTrue(SoundEditorEditing.gapRangeSeconds.contains(SoundEditorEditing.defaultGapSeconds))
        XCTAssertLessThanOrEqual(SampleBuffer.frames(seconds: SoundEditorEditing.gapRangeSeconds.upperBound),
                                 SoundRecipe.maximumFrames, "a gap the edit would not refuse for its own length")
    }

    // MARK: - Where the playhead and the selection go after an edit

    func testAfterATrimTheSoundIsWhatWasKeptAndTheHeadIsAtItsStart() {
        XCTAssertEqual(SoundEditPlacement.after(.trim(2000..<3000)), .playhead(0))
    }

    func testAfterADeleteOrACutTheHeadIsWhereTheCutWasMadeAndNothingIsSelected() {
        XCTAssertEqual(SoundEditPlacement.after(.delete(2000..<3000)), .playhead(2000))
        XCTAssertEqual(SoundEditPlacement.after(.cut(2000..<3000)), .playhead(2000))
    }

    func testAfterAPasteWhatWasPastedIsSelected() throws {
        let clip = try excerpt()
        XCTAssertEqual(SoundEditPlacement.after(.paste(clip, replacing: 500..<700)), .select(500..<600))
        XCTAssertEqual(SoundEditPlacement.after(.paste(clip, replacing: 500..<500)), .select(500..<600))
    }

    func testAfterADuplicateTheCopyIsSelectedSoThatDoingItAgainMakesAnother() {
        XCTAssertEqual(SoundEditPlacement.after(.duplicate(2000..<3000)), .select(3000..<4000))
    }

    func testAfterAFadeOrAGainTheSelectionStaysSoThatItCanBeHeard() {
        XCTAssertEqual(SoundEditPlacement.after(.fadeIn(2000..<3000)), .keep)
        XCTAssertEqual(SoundEditPlacement.after(.fadeOut(2000..<3000)), .keep)
        XCTAssertEqual(SoundEditPlacement.after(.gain(2000..<3000, dB: 3)), .keep)
    }

    func testAfterARepeatTheWholeOfWhatItMadeIsSelected() {
        XCTAssertEqual(SoundEditPlacement.after(.repeatSelection(2000..<3000, times: 3, gapFrames: 500)), .select(2000..<6000))
        XCTAssertEqual(SoundEditPlacement.after(.repeatSelection(2000..<3000, times: 2, gapFrames: 0)), .select(2000..<4000))
    }

    func testAPlacementOfAnEditThatWouldNotHaveBeenMadeCannotOverflow() {
        let made = SoundEditPlacement.after(.repeatSelection(0..<Int.max, times: Int.max, gapFrames: Int.max))
        guard case .select(let range) = made else { return XCTFail("\(made)") }
        XCTAssertLessThanOrEqual(range.lowerBound, range.upperBound)
    }

    func testAPlacementIsAppliedToTheTimeline() {
        var timeline = SoundTimeline(length: 8000)
        timeline.select(100..<200)
        timeline.apply(.keep)
        XCTAssertEqual(timeline.selection, 100..<200)
        XCTAssertEqual(timeline.playhead, 100)

        timeline.apply(.playhead(4000))
        XCTAssertNil(timeline.selection)
        XCTAssertEqual(timeline.playhead, 4000)

        timeline.apply(.select(500..<900))
        XCTAssertEqual(timeline.selection, 500..<900)
        XCTAssertEqual(timeline.playhead, 500)

        timeline.apply(.select(7000..<9000))
        XCTAssertEqual(timeline.selection, 7000..<8000, "held to the sound, as a selection always is")
        timeline.apply(.playhead(99_999))
        XCTAssertEqual(timeline.playhead, 8000)
    }
}
