import XCTest
@testable import NotificationCore

/// What a press of Play asks the player for: where to start and whether to go round a range (sound editor plan,
/// Task 7). The player's own arguments, worked out here so that every case is a test and the window only passes
/// them on.
final class SoundPreviewPlanTests: XCTestCase {
    private func plan(playhead: Int = 0, selection: Range<Int>? = nil, loops: Bool = false, length: Int = 1_000,
                      resumingAt: Int? = nil) -> SoundPreviewPlan? {
        SoundPreviewPlan.make(length: length, playhead: playhead, selection: selection, loops: loops, resumingAt: resumingAt)
    }

    func testWithNothingSelectedItPlaysOnceFromThePlayhead() {
        XCTAssertEqual(plan(playhead: 300), SoundPreviewPlan(start: 300, loop: nil))
        XCTAssertEqual(plan(playhead: 300, loops: true), SoundPreviewPlan(start: 300, loop: nil),
                       "there is nothing to go round")
    }

    func testAPlayheadAtTheEndPlaysFromTheStartAgain() {
        XCTAssertEqual(plan(playhead: 1_000), SoundPreviewPlan(start: 0, loop: nil))
        XCTAssertEqual(plan(playhead: 5_000), SoundPreviewPlan(start: 0, loop: nil))
    }

    func testWithASelectionAndNoLoopItPlaysOnceFromTheStartOfTheSelection() {
        XCTAssertEqual(plan(playhead: 700, selection: 200..<400), SoundPreviewPlan(start: 200, loop: nil))
    }

    func testWithALoopOnItGoesRoundTheSelectionFromItsStart() {
        XCTAssertEqual(plan(playhead: 700, selection: 200..<400, loops: true), SoundPreviewPlan(start: 200, loop: 200..<400))
    }

    func testAResumeBeginsWhereItIsAskedWhenThatIsInTheRangeItGoesRound() {
        XCTAssertEqual(plan(selection: 200..<400, loops: true, resumingAt: 350), SoundPreviewPlan(start: 350, loop: 200..<400))
        XCTAssertEqual(plan(selection: 200..<400, loops: true, resumingAt: 900), SoundPreviewPlan(start: 200, loop: 200..<400),
                       "outside the loop it begins at the loop's start")
    }

    func testAResumeWithNoLoopBeginsWhereItIsAskedWhateverIsSelected() {
        XCTAssertEqual(plan(selection: 200..<400, resumingAt: 350), SoundPreviewPlan(start: 350, loop: nil))
        XCTAssertEqual(plan(playhead: 10, resumingAt: 600), SoundPreviewPlan(start: 600, loop: nil))
        XCTAssertEqual(plan(resumingAt: 1_000), SoundPreviewPlan(start: 0, loop: nil), "from the end is from the start")
    }

    func testASelectionIsHeldToTheSoundAndAnEmptyOneIsNoSelection() {
        XCTAssertEqual(plan(selection: 900..<2_000, loops: true), SoundPreviewPlan(start: 900, loop: 900..<1_000))
        XCTAssertEqual(plan(playhead: 40, selection: 500..<500, loops: true), SoundPreviewPlan(start: 40, loop: nil))
        XCTAssertEqual(plan(playhead: 40, selection: 2_000..<3_000, loops: true), SoundPreviewPlan(start: 40, loop: nil),
                       "a selection wholly outside the sound has nothing in it to go round")
    }

    func testASoundOfNoLengthHasNothingToPlay() {
        XCTAssertNil(plan(length: 0))
    }

    func testWhereAPreviewGoesBackToWhenItEndsIsWhereItBegan() {
        XCTAssertEqual(SoundPreviewPlan(start: 350, loop: nil).returnsTo, 350)
    }

    private func ends(seekingTo frame: Int, selection: Range<Int>? = nil, loops: Bool = false, length: Int = 1_000) -> Bool {
        SoundPreviewPlan.endsPreview(seekingTo: frame, length: length, selection: selection, loops: loops)
    }

    func testAMoveToTheEndOfAPlayingPreviewEndsItAndAMoveAnywhereElseDoesNot() {
        XCTAssertTrue(ends(seekingTo: 1_000))
        XCTAssertTrue(ends(seekingTo: 5_000))
        XCTAssertFalse(ends(seekingTo: 999))
        XCTAssertFalse(ends(seekingTo: 0))
    }

    func testAMoveToTheEndDoesNotEndAPreviewThatIsGoingRoundASelection() {
        XCTAssertFalse(ends(seekingTo: 1_000, selection: 600..<1_000, loops: true), "it goes on round from the start of the loop")
        XCTAssertFalse(ends(seekingTo: 1_000, selection: 200..<400, loops: true))
    }

    func testAMoveToTheEndEndsAPreviewWhenThereIsASelectionButNoLoopOrALoopWithNoSelection() {
        XCTAssertTrue(ends(seekingTo: 1_000, selection: 200..<400, loops: false))
        XCTAssertTrue(ends(seekingTo: 1_000, selection: nil, loops: true), "there is nothing to go round")
    }

    func testASoundOfNoLengthHasNoPreviewToEnd() {
        XCTAssertFalse(ends(seekingTo: 0, length: 0))
    }
}
