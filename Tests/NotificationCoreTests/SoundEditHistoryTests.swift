import XCTest
@testable import NotificationCore

/// Past, present and future recipes (sound editor plan, Task 2, Ruling 2).
final class SoundEditHistoryTests: XCTestCase {
    private typealias F = SoundFixtures

    func testAHistoryBeginsAtTheRecipeItWasOpenedWithAndHasNothingToUndoOrRedo() {
        let history = SoundEditHistory(F.whole())
        XCTAssertEqual(history.present, F.whole())
        XCTAssertEqual(history.opened, F.whole())
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(history.canRedo)
        XCTAssertFalse(history.isChanged)
    }

    func testUndoAndRedoWithNothingToDoReportSoAndChangeNothing() {
        var history = SoundEditHistory(F.whole())
        XCTAssertFalse(history.undo())
        XCTAssertFalse(history.redo())
        XCTAssertEqual(history, SoundEditHistory(F.whole()))
    }

    func testACommitMovesThePresentAndUndoAndRedoWalkBackAndForth() throws {
        var history = SoundEditHistory(F.whole())
        XCTAssertTrue(try history.commit(.trim(100..<900)))
        XCTAssertTrue(try history.commit(.delete(0..<100)))
        let afterTwo = history.present
        XCTAssertEqual(afterTwo.frameCount, 700)
        XCTAssertTrue(history.isChanged)

        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.present.frameCount, 800)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.present, F.whole())
        XCTAssertFalse(history.isChanged)
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.canRedo)

        XCTAssertTrue(history.redo())
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.present, afterTwo)
        XCTAssertFalse(history.canRedo)
        XCTAssertTrue(history.canUndo, "what was redone can be undone again")
        history.undo()
        XCTAssertEqual(history.present.frameCount, 800)
    }

    func testACommitAfterAnUndoTakesTheFutureAway() throws {
        var history = SoundEditHistory(F.whole())
        try history.commit(.trim(100..<900))
        history.undo()
        XCTAssertTrue(history.canRedo)
        try history.commit(.trim(0..<10))
        XCTAssertFalse(history.canRedo)
        XCTAssertEqual(history.present.frameCount, 10)
    }

    func testARefusedEditChangesNothingAndLeavesTheFutureAlone() throws {
        var history = SoundEditHistory(F.whole())
        try history.commit(.trim(100..<900))
        history.undo()
        let before = history
        XCTAssertThrowsError(try history.commit(.delete(0..<1000))) { error in
            XCTAssertEqual(error as? SoundEditRefusal, .wouldLeaveNothing)
        }
        XCTAssertEqual(history, before)
        XCTAssertTrue(history.canRedo)
    }

    func testAnEditThatLeavesTheRecipeAsItWasAddsNothingToThePast() throws {
        var history = SoundEditHistory(F.whole())
        XCTAssertFalse(try history.commit(.gain(0..<10, dB: 0)))
        XCTAssertFalse(history.canUndo)
        XCTAssertFalse(try history.commit(.trim(0..<1000)))
        XCTAssertFalse(history.canUndo)
    }

    func testAnEditThatLeavesTheRecipeAsItWasKeepsTheFuture() throws {
        var history = SoundEditHistory(F.whole())
        try history.commit(.trim(100..<900))
        history.undo()
        try history.commit(.gain(0..<10, dB: 0))
        XCTAssertTrue(history.canRedo)
    }

    func testResetPutsTheWholeSourceBackAndCanBeUndone() throws {
        var history = SoundEditHistory(F.whole())
        try history.commit(.trim(100..<900))
        try history.commit(.gain(0..<100, dB: 6))
        let edited = history.present
        XCTAssertTrue(history.reset())
        XCTAssertEqual(history.present, F.whole())
        XCTAssertTrue(history.present.isOriginal)
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.present, edited)
    }

    func testResetOfAnUntouchedSoundDoesNothing() {
        var history = SoundEditHistory(F.whole())
        XCTAssertFalse(history.reset())
        XCTAssertFalse(history.canUndo)
    }

    func testResetGoesBackToTheWholeSourceEvenWhenTheWindowOpenedWithAnEditedRecipe() {
        var history = SoundEditHistory(F.recipe([F.clip(0, 100), F.clip(500, 700)]))
        XCTAssertTrue(history.reset())
        XCTAssertEqual(history.present.segments, [F.clip(0, 10_000)])
        XCTAssertTrue(history.isChanged, "the recipe it was opened with is still the one it is compared to")
    }

    func testEditsThatAreUndoneByHandLeaveTheWindowUnchanged() throws {
        var history = SoundEditHistory(F.whole())
        try history.commit(.gain(100..<200, dB: 6))
        XCTAssertTrue(history.isChanged)
        try history.commit(.gain(100..<200, dB: -6))
        XCTAssertFalse(history.isChanged)
    }

    // MARK: - What has been saved

    func testAnUntouchedSoundHasNothingUnsaved() {
        let history = SoundEditHistory(F.whole())
        XCTAssertEqual(history.saved, F.whole())
        XCTAssertFalse(history.hasUnsavedEdits)
    }

    func testAnEditIsUnsavedUntilThatRecipeIsMarkedSaved() throws {
        var history = SoundEditHistory(F.whole())
        try history.commit(.trim(100..<900))
        XCTAssertTrue(history.hasUnsavedEdits)
        history.markSaved(history.present)
        XCTAssertFalse(history.hasUnsavedEdits)
        XCTAssertTrue(history.isChanged, "it is still not the recipe the window opened with")
        XCTAssertEqual(history.opened, F.whole())
    }

    func testAnUndoPastWhatWasSavedIsUnsavedAndRedoingItIsSavedAgain() throws {
        var history = SoundEditHistory(F.whole())
        try history.commit(.trim(100..<900))
        history.markSaved(history.present)
        history.undo()
        XCTAssertTrue(history.hasUnsavedEdits, "the saved sound is no longer what the window shows")
        history.redo()
        XCTAssertFalse(history.hasUnsavedEdits)
    }

    func testEditsMadeAfterASaveAreUnsavedAndMakingThemBackIsNot() throws {
        var history = SoundEditHistory(F.whole())
        try history.commit(.gain(100..<200, dB: 6))
        history.markSaved(history.present)
        try history.commit(.fadeIn(0..<50))
        XCTAssertTrue(history.hasUnsavedEdits)
        history.undo()
        XCTAssertFalse(history.hasUnsavedEdits)
    }

    func testWhatWasSavedIsTheRecipeThatWasWrittenAndNotTheOneThatIsPresentWhenTheSaveEnds() throws {
        var history = SoundEditHistory(F.whole())
        try history.commit(.trim(100..<900))
        let written = history.present
        try history.commit(.trim(0..<500))
        history.markSaved(written)
        XCTAssertTrue(history.hasUnsavedEdits, "an edit made while the save ran is not in the saved sound")
        XCTAssertEqual(history.saved, written)
    }

    func testResetAfterASaveIsAnUnsavedChange() throws {
        var history = SoundEditHistory(F.whole())
        try history.commit(.trim(100..<900))
        history.markSaved(history.present)
        history.reset()
        XCTAssertTrue(history.hasUnsavedEdits)
    }

    func testASoundOpenedWithEditsAndNotChangedHasNothingUnsaved() {
        let history = SoundEditHistory(F.recipe([F.clip(0, 100), F.clip(500, 700)]))
        XCTAssertFalse(history.hasUnsavedEdits, "the edits it was saved with are saved")
    }
}
