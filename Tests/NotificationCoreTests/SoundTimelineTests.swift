import XCTest
@testable import NotificationCore

/// Where the playhead is and what is selected, as the keyboard, the pointer and a preview move them (sound editor
/// plan, Ruling 13 and Task 7). Every position is a frame of the result, and none is outside it.
final class SoundTimelineTests: XCTestCase {
    private func timeline(_ length: Int = 1_000) -> SoundTimeline { SoundTimeline(length: length) }

    func testItBeginsAtTheStartWithNothingSelected() {
        let t = timeline()
        XCTAssertEqual(t.playhead, 0)
        XCTAssertNil(t.selection)
        XCTAssertFalse(t.hasSelection)
        XCTAssertFalse(t.selectionIsWhole)
        XCTAssertEqual(t.length, 1_000)
    }

    // MARK: - Placing the playhead

    func testPlacingThePlayheadMovesItAndClearsTheSelection() {
        var t = timeline()
        t.select(200..<400)
        t.place(700)
        XCTAssertEqual(t.playhead, 700)
        XCTAssertNil(t.selection)
    }

    func testThePlayheadIsHeldToTheSoundAndItsEndIsAPlace() {
        var t = timeline()
        t.place(5_000)
        XCTAssertEqual(t.playhead, 1_000)
        t.place(-4)
        XCTAssertEqual(t.playhead, 0)
    }

    // MARK: - The keyboard

    func testMovingWithoutShiftMovesThePlayheadAndLeavesNoSelection() {
        var t = timeline()
        t.select(200..<400)
        t.moveHead(to: 450, extending: false)
        XCTAssertEqual(t.playhead, 450)
        XCTAssertNil(t.selection)
    }

    func testMovingWithShiftSelectsFromWhereThePlayheadWas() {
        var t = timeline()
        t.place(300)
        t.moveHead(to: 340, extending: true)
        XCTAssertEqual(t.selection, 300..<340)
        XCTAssertEqual(t.playhead, 340)
        t.moveHead(to: 380, extending: true)
        XCTAssertEqual(t.selection, 300..<380, "the fixed end stays where it was first")
    }

    func testExtendingBackThroughTheStartingPlaceSelectsTheOtherWayAndOnToItClearsTheSelection() {
        var t = timeline()
        t.place(300)
        t.moveHead(to: 340, extending: true)
        t.moveHead(to: 280, extending: true)
        XCTAssertEqual(t.selection, 280..<300)
        XCTAssertEqual(t.playhead, 280)
        t.moveHead(to: 300, extending: true)
        XCTAssertNil(t.selection, "nothing between the ends is nothing selected")
        XCTAssertEqual(t.playhead, 300)
        t.moveHead(to: 310, extending: true)
        XCTAssertEqual(t.selection, 300..<310, "and the fixed end is still where it was")
    }

    func testAMoveWithoutShiftForgetsTheFixedEnd() {
        var t = timeline()
        t.place(300)
        t.moveHead(to: 340, extending: true)
        t.moveHead(to: 500, extending: false)
        t.moveHead(to: 520, extending: true)
        XCTAssertEqual(t.selection, 500..<520)
    }

    func testTheKeyboardCannotMovePastTheEnds() {
        var t = timeline()
        t.moveHead(to: -50, extending: true)
        XCTAssertEqual(t.playhead, 0)
        XCTAssertNil(t.selection)
        t.moveHead(to: 5_000, extending: true)
        XCTAssertEqual(t.playhead, 1_000)
        XCTAssertEqual(t.selection, 0..<1_000)
        XCTAssertTrue(t.selectionIsWhole)
    }

    // MARK: - Selecting

    func testSelectingARangeHoldsItToTheSoundAndAnEmptyOneSelectsNothing() {
        var t = timeline()
        t.select(900..<2_000)
        XCTAssertEqual(t.selection, 900..<1_000)
        t.select(-5..<10)
        XCTAssertEqual(t.selection, 0..<10)
        t.select(500..<500)
        XCTAssertNil(t.selection)
        t.select(2_000..<3_000)
        XCTAssertNil(t.selection, "a range wholly past the end has nothing of the sound in it")
    }

    func testSelectAllSelectsTheWholeSoundFromTheStart() {
        var t = timeline()
        t.place(400)
        t.selectAll()
        XCTAssertEqual(t.selection, 0..<1_000)
        XCTAssertTrue(t.selectionIsWhole)
        XCTAssertEqual(t.playhead, 0)
    }

    func testSelectAllOfNothingSelectsNothing() {
        var t = SoundTimeline(length: 0)
        t.selectAll()
        XCTAssertNil(t.selection)
    }

    func testClearingTheSelectionLeavesThePlayheadWhereItIs() {
        var t = timeline()
        t.select(200..<400)
        t.clearSelection()
        XCTAssertNil(t.selection)
        XCTAssertEqual(t.playhead, 200)
    }

    func testAfterSelectingTheKeyboardExtendsFromTheEndTheSelectionDidNotStartAt() {
        var t = timeline()
        t.select(200..<400)
        XCTAssertEqual(t.playhead, 200, "the playhead is at the start of what is selected")
        t.moveHead(to: 150, extending: true)
        XCTAssertEqual(t.selection, 150..<400, "so Shift with Left makes it longer at the start")
        t.moveHead(to: 250, extending: true)
        XCTAssertEqual(t.selection, 250..<400)
    }

    // MARK: - A preview

    func testAPreviewMovesThePlayheadAndLeavesWhatIsSelected() {
        var t = timeline()
        t.select(200..<400)
        t.followPreview(333)
        XCTAssertEqual(t.playhead, 333)
        XCTAssertEqual(t.selection, 200..<400)
        t.followPreview(9_999)
        XCTAssertEqual(t.playhead, 1_000, "held to the sound")
    }

    func testAPreviewThatEndsPutsThePlayheadBackWhereItBegan() {
        var t = timeline()
        t.place(120)
        t.followPreview(777)
        t.previewEnded(returningTo: 120)
        XCTAssertEqual(t.playhead, 120)
        t.previewEnded(returningTo: 4_000)
        XCTAssertEqual(t.playhead, 1_000)
    }

    // MARK: - A new length

    func testANewLengthHoldsEverythingToTheNewSoundAndDropsASelectionThatIsGone() {
        var t = timeline()
        t.select(600..<900)
        t.setLength(800)
        XCTAssertEqual(t.length, 800)
        XCTAssertEqual(t.selection, 600..<800)
        XCTAssertEqual(t.playhead, 600)
        t.setLength(500)
        XCTAssertNil(t.selection, "nothing of it is left")
        XCTAssertEqual(t.playhead, 500)
        t.setLength(2_000)
        XCTAssertEqual(t.playhead, 500, "a longer sound moves nothing")
    }

    // MARK: - The pointer

    func testAClickPlacesThePlayheadAndClearsTheSelection() {
        var t = timeline()
        t.select(200..<400)
        t.pointerDown(at: 700, edgeReach: 5)
        XCTAssertTrue(t.isDragging)
        t.pointerUp(at: 700)
        XCTAssertFalse(t.isDragging)
        XCTAssertEqual(t.playhead, 700)
        XCTAssertNil(t.selection)
    }

    func testDraggingSelectsFromWhereItBeganToWhereItIsInEitherDirection() {
        var t = timeline()
        t.pointerDown(at: 500, edgeReach: 5)
        t.pointerMoved(to: 560, slop: 3)
        XCTAssertEqual(t.selection, 500..<560)
        t.pointerMoved(to: 420, slop: 3)
        XCTAssertEqual(t.selection, 420..<500)
        t.pointerUp(at: 420)
        XCTAssertEqual(t.selection, 420..<500)
        XCTAssertEqual(t.playhead, 420, "the playhead goes to the start of what was selected")
    }

    func testAMovementWithinTheSlopIsStillAClick() {
        var t = timeline()
        t.pointerDown(at: 500, edgeReach: 5)
        t.pointerMoved(to: 503, slop: 3)
        XCTAssertNil(t.selection)
        t.pointerUp(at: 503)
        XCTAssertNil(t.selection)
        XCTAssertEqual(t.playhead, 503, "a click is where the pointer was let go")
    }

    func testOnceItHasMovedPastTheSlopTheSlopIsNotAskedAgain() {
        var t = timeline()
        t.pointerDown(at: 500, edgeReach: 5)
        t.pointerMoved(to: 520, slop: 3)
        t.pointerMoved(to: 502, slop: 3)
        XCTAssertEqual(t.selection, 500..<502)
        t.pointerMoved(to: 500, slop: 3)
        XCTAssertNil(t.selection, "back where it began is nothing selected")
        t.pointerUp(at: 500)
        XCTAssertNil(t.selection)
        XCTAssertEqual(t.playhead, 500)
    }

    func testTheSelectionAPointerMakesIsHeldToTheSound() {
        var t = timeline()
        t.pointerDown(at: 900, edgeReach: 5)
        t.pointerMoved(to: 40_000, slop: 3)
        XCTAssertEqual(t.selection, 900..<1_000)
        t.pointerMoved(to: -40_000, slop: 3)
        XCTAssertEqual(t.selection, 0..<900)
    }

    func testPressingNearTheStartOfASelectionMovesThatEdgeAndLeavesTheOther() {
        var t = timeline()
        t.select(400..<600)
        t.pointerDown(at: 397, edgeReach: 5)
        t.pointerMoved(to: 350, slop: 3)
        XCTAssertEqual(t.selection, 350..<600)
        t.pointerMoved(to: 450, slop: 3)
        XCTAssertEqual(t.selection, 450..<600)
        t.pointerUp(at: 450)
        XCTAssertEqual(t.selection, 450..<600)
        XCTAssertEqual(t.playhead, 450)
    }

    func testPressingNearTheEndOfASelectionMovesThatEdgeAndLeavesTheOther() {
        var t = timeline()
        t.select(400..<600)
        t.pointerDown(at: 604, edgeReach: 5)
        t.pointerMoved(to: 700, slop: 3)
        XCTAssertEqual(t.selection, 400..<700)
        t.pointerUp(at: 700)
        XCTAssertEqual(t.playhead, 400)
    }

    func testAnEdgeDraggedPastTheOtherBecomesTheOtherSidesSelection() {
        var t = timeline()
        t.select(400..<600)
        t.pointerDown(at: 603, edgeReach: 5)
        t.pointerMoved(to: 300, slop: 3)
        XCTAssertEqual(t.selection, 300..<400, "the start stayed where it was, and the end is now before it")
        t.pointerMoved(to: 400, slop: 3)
        XCTAssertNil(t.selection)
        t.pointerMoved(to: 450, slop: 3)
        XCTAssertEqual(t.selection, 400..<450)
    }

    func testWhenBothEdgesAreInReachTheNearerIsTaken() {
        var t = timeline()
        t.select(400..<406)
        t.pointerDown(at: 405, edgeReach: 10)
        t.pointerMoved(to: 450, slop: 3)
        XCTAssertEqual(t.selection, 400..<450, "405 is one frame from the end and five from the start")
        var u = timeline()
        u.select(400..<406)
        u.pointerDown(at: 401, edgeReach: 10)
        u.pointerMoved(to: 350, slop: 3)
        XCTAssertEqual(u.selection, 350..<406)
    }

    func testAPressOutsideReachOfBothEdgesStartsANewSelection() {
        var t = timeline()
        t.select(400..<600)
        t.pointerDown(at: 700, edgeReach: 5)
        t.pointerMoved(to: 800, slop: 3)
        XCTAssertEqual(t.selection, 700..<800)
        var u = timeline()
        u.select(400..<600)
        u.pointerDown(at: 394, edgeReach: 5)
        u.pointerMoved(to: 300, slop: 3)
        XCTAssertEqual(u.selection, 300..<394, "394 is six from the start, past a reach of five")
    }

    func testAPressOnAnEdgeThatDoesNotMoveLeavesTheSelectionAlone() {
        var t = timeline()
        t.select(400..<600)
        t.pointerDown(at: 600, edgeReach: 5)
        t.pointerUp(at: 600)
        XCTAssertEqual(t.selection, 400..<600)
        XCTAssertEqual(t.playhead, 400)
    }

    func testAfterADragTheKeyboardExtendsFromTheEndThatDidNotMove() {
        var t = timeline()
        t.pointerDown(at: 400, edgeReach: 5)
        t.pointerMoved(to: 500, slop: 3)
        t.pointerUp(at: 500)
        t.moveHead(to: 390, extending: true)
        XCTAssertEqual(t.selection, 390..<500)
    }

    func testMovementWithNoPressIsIgnored() {
        var t = timeline()
        t.select(400..<600)
        t.pointerMoved(to: 10, slop: 3)
        t.pointerUp(at: 10)
        XCTAssertEqual(t.selection, 400..<600)
        XCTAssertEqual(t.playhead, 400)
    }

    func testANewLengthEndsADragThatWasUnderWay() {
        var t = timeline()
        t.pointerDown(at: 400, edgeReach: 5)
        t.setLength(900)
        XCTAssertFalse(t.isDragging)
    }

    // MARK: - Where zooming is aimed

    func testZoomingIsAimedAtTheMiddleOfTheSelectionOrElseAtThePlayhead() {
        var t = timeline()
        t.place(250)
        XCTAssertEqual(t.focus, 250)
        t.select(400..<600)
        XCTAssertEqual(t.focus, 500)
        t.select(401..<404)
        XCTAssertEqual(t.focus, 402)
    }
}
