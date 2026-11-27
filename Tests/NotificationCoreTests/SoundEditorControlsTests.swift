import XCTest
@testable import NotificationCore

/// What is on and what is off in the sound editor's window, and what its one play button is called (sound editor
/// plan, Task 7). A control that does nothing is off, and never left on to be pressed for no reason.
final class SoundEditorControlsTests: XCTestCase {
    private func controls(isReady: Bool = true, length: Int = 48_000, canBeHeard: Bool = true, isPreviewing: Bool = false,
                          selection: Range<Int>? = nil, visible: Range<Int>? = nil, loops: Bool = false) -> SoundEditorControls {
        var viewport = WaveformViewport(length: length)
        if let visible { viewport = WaveformViewport(length: length, visible: visible) }
        return SoundEditorControls(isReady: isReady, length: length, canBeHeard: canBeHeard, isPreviewing: isPreviewing,
                                   selection: selection, viewport: viewport, loops: loops)
    }

    func testAReadySoundThatCanBeHeardCanBePlayed() {
        let c = controls()
        XCTAssertTrue(c.canPlayOrStop)
        XCTAssertEqual(c.playCommand, .play)
    }

    func testWhileItPlaysTheOneButtonStopsAndStaysOn() {
        let c = controls(isPreviewing: true)
        XCTAssertEqual(c.playCommand, .stop)
        XCTAssertTrue(c.canPlayOrStop)
        XCTAssertTrue(controls(canBeHeard: false, isPreviewing: true).canPlayOrStop, "whatever it is playing can be stopped")
    }

    func testAnythingThatIsNotThereToBePlayedCannotBePlayed() {
        XCTAssertFalse(controls(isReady: false).canPlayOrStop, "not yet opened, or not opened at all")
        XCTAssertFalse(controls(length: 0).canPlayOrStop)
        XCTAssertFalse(controls(canBeHeard: false).canPlayOrStop, "below the silence floor, as an alert would be refused")
    }

    func testLoopIsOfferedOnlyForASelection() {
        XCTAssertFalse(controls().canLoop)
        XCTAssertTrue(controls(selection: 100..<200).canLoop)
        XCTAssertFalse(controls(isReady: false, selection: 100..<200).canLoop)
        XCTAssertFalse(controls(selection: 100..<100).canLoop, "an empty selection is none")
    }

    func testLoopIsOnOnlyWhenItWasTurnedOnAndThereIsASelectionToGoRound() {
        XCTAssertFalse(controls(loops: true).loopIsOn)
        XCTAssertTrue(controls(selection: 100..<200, loops: true).loopIsOn)
        XCTAssertFalse(controls(selection: 100..<200, loops: false).loopIsOn)
    }

    func testSelectAllIsOffForASoundWhollySelectedAndClearIsOffForNothingSelected() {
        XCTAssertTrue(controls().canSelectAll)
        XCTAssertFalse(controls().canClearSelection)
        XCTAssertTrue(controls(selection: 0..<100).canSelectAll)
        XCTAssertTrue(controls(selection: 0..<100).canClearSelection)
        XCTAssertFalse(controls(selection: 0..<48_000).canSelectAll)
        XCTAssertTrue(controls(selection: 0..<48_000).canClearSelection)
        XCTAssertFalse(controls(length: 0).canSelectAll)
        XCTAssertFalse(controls(isReady: false).canSelectAll)
    }

    func testZoomIsOffAtItsLimitsAndOnBetweenThem() {
        XCTAssertTrue(controls().canZoomIn)
        XCTAssertFalse(controls().canZoomOut, "all of it is shown")
        XCTAssertTrue(controls(visible: 0..<24_000).canZoomOut)
        XCTAssertFalse(controls(visible: 0..<480).canZoomIn, "ten milliseconds is as close as it goes")
        XCTAssertFalse(controls(isReady: false).canZoomIn)
        XCTAssertFalse(controls(isReady: false, visible: 0..<24_000).canZoomOut)
    }

    func testTheCommandsItNamesAreTheTextsOwn() {
        XCTAssertEqual(controls().playCommand.title, SoundEditorText.Command.play.title)
        XCTAssertEqual(controls(isPreviewing: true).playCommand.title, SoundEditorText.Command.stop.title)
    }
}
