import XCTest
@testable import NotificationCore

/// What is on and what is off among the sound editor's editing controls, and for the press of a check (sound editor
/// plan, Ruling 16 and Task 8). A control that would do nothing is off, and an edit that reads a position waits until
/// the render of the last one has come back, so that a selection is never read against a sound that has moved on.
final class SoundEditorEditControlsTests: XCTestCase {
    private func controls(isReady: Bool = true, length: Int = 48_000, selection: Range<Int>? = nil, canUndo: Bool = false,
                          canRedo: Bool = false, canReset: Bool = false, hasClipboard: Bool = false, isCatchingUp: Bool = false,
                          gainDB: Double = 0) -> SoundEditorControls {
        SoundEditorControls(isReady: isReady, length: length, canBeHeard: true, isPreviewing: false, selection: selection,
                            viewport: WaveformViewport(length: length), loops: false, canUndo: canUndo, canRedo: canRedo,
                            canReset: canReset, hasClipboard: hasClipboard, isCatchingUp: isCatchingUp, gainDB: gainDB)
    }

    /// The commands that edit what is selected, apart from Gain and Trim, which are held to more.
    private let onASelection: [SoundEditorText.Command] = [.delete, .cut, .copy, .duplicate, .fadeIn, .fadeOut,
                                                           .repeatSelection]

    func testWithNothingSelectedNoCommandThatWorksOnASelectionIsOn() {
        let c = controls()
        for command in onASelection + [.trim, .gain] { XCTAssertFalse(c.canPerform(command), "\(command)") }
        XCTAssertFalse(controls(selection: 100..<100).canPerform(.cut), "an empty selection is none")
    }

    func testWithPartSelectedEachOfThemIsOn() {
        let c = controls(selection: 1000..<2000, gainDB: 6)
        for command in onASelection + [.trim, .gain] { XCTAssertTrue(c.canPerform(command), "\(command)") }
    }

    func testTrimOfAllThatIsSelectedWouldChangeNothingAndIsOffWhileTheOthersAreOnToSayWhyTheyDoNothing() {
        let c = controls(selection: 0..<48_000, gainDB: 6)
        XCTAssertFalse(c.canPerform(.trim))
        // Deleting or cutting the whole of a sound is refused with a sentence that says why (Ruling 18), which a
        // button that was off would not.
        for command in onASelection { XCTAssertTrue(c.canPerform(command), "\(command)") }
    }

    func testGainIsOfferedOnlyForASelectionThatIsNotTheWhole() {
        XCTAssertFalse(controls().offersGain)
        XCTAssertFalse(controls(selection: 0..<48_000).offersGain, "against what, when it is all of it (Ruling 16)")
        XCTAssertTrue(controls(selection: 0..<47_999).offersGain)
        XCTAssertTrue(controls(selection: 100..<200).offersGain)
        XCTAssertFalse(controls(isReady: false, selection: 100..<200).offersGain)
    }

    func testGainIsOnOnlyWhereItIsOfferedAndForAGainThatIsNotZero() {
        XCTAssertFalse(controls(selection: 100..<200, gainDB: 0).canPerform(.gain), "a gain of nothing changes nothing")
        XCTAssertTrue(controls(selection: 100..<200, gainDB: -3).canPerform(.gain))
        XCTAssertFalse(controls(selection: 0..<48_000, gainDB: 6).canPerform(.gain))
    }

    func testPasteNeedsOnlyThingsToPaste() {
        XCTAssertFalse(controls().canPerform(.paste))
        XCTAssertTrue(controls(hasClipboard: true).canPerform(.paste), "it goes in at the playhead")
        XCTAssertTrue(controls(selection: 100..<200, hasClipboard: true).canPerform(.paste))
        XCTAssertFalse(controls(length: 0, hasClipboard: true).canPerform(.paste))
        XCTAssertFalse(controls(isReady: false, hasClipboard: true).canPerform(.paste))
    }

    func testWhileTheLastEditIsStillBeingRenderedNothingThatReadsAPositionIsOn() {
        let c = controls(selection: 1000..<2000, hasClipboard: true, isCatchingUp: true, gainDB: 6)
        for command in onASelection + [.trim, .gain, .paste] { XCTAssertFalse(c.canPerform(command), "\(command)") }
        XCTAssertTrue(c.offersGain, "the gain does not come and go with each render")
    }

    func testUndoRedoAndResetFollowTheHistoryAndDoNotWaitForARender() {
        let none = controls()
        XCTAssertFalse(none.canPerform(.undo))
        XCTAssertFalse(none.canPerform(.redo))
        XCTAssertFalse(none.canPerform(.resetToOriginal))
        let all = controls(canUndo: true, canRedo: true, canReset: true, isCatchingUp: true)
        XCTAssertTrue(all.canPerform(.undo))
        XCTAssertTrue(all.canPerform(.redo))
        XCTAssertTrue(all.canPerform(.resetToOriginal))
        XCTAssertFalse(controls(isReady: false, canUndo: true, canRedo: true, canReset: true).canPerform(.undo))
        XCTAssertFalse(controls(isReady: false, canUndo: true, canRedo: true, canReset: true).canPerform(.resetToOriginal))
    }

    func testNothingIsOnBeforeTheSoundIsOpen() {
        let c = controls(isReady: false, selection: 100..<200, canUndo: true, canRedo: true, canReset: true,
                         hasClipboard: true, gainDB: 6)
        for command in onASelection + [.trim, .gain, .paste, .undo, .redo, .resetToOriginal, .selectAll, .clearSelection] {
            XCTAssertFalse(c.canPerform(command), "\(command)")
        }
    }

    func testTheCommandsThatAreNotEditsAreOnAsTheirOwnControlsSay() {
        let c = controls(selection: 100..<200)
        XCTAssertEqual(c.canPerform(.play), c.canPlayOrStop)
        XCTAssertEqual(c.canPerform(.stop), c.canPlayOrStop)
        XCTAssertEqual(c.canPerform(.loopSelection), c.canLoop)
        XCTAssertEqual(c.canPerform(.selectAll), c.canSelectAll)
        XCTAssertEqual(c.canPerform(.clearSelection), c.canClearSelection)
        XCTAssertEqual(c.canPerform(.zoomIn), c.canZoomIn)
        XCTAssertEqual(c.canPerform(.zoomOut), c.canZoomOut)
    }

    func testEveryCommandIsOffForASoundWithNothingInIt() {
        let c = controls(length: 0, canUndo: false, hasClipboard: true)
        for command in SoundEditorText.Command.allCases {
            XCTAssertFalse(c.canPerform(command), "\(command)")
        }
    }

    // MARK: - The press of a check

    func testAnEditPressIsOnWhenEditsAreAndWaitsForARenderLikeAnyOther() {
        let fix = SoundFix.edit(.trim(0..<100))
        XCTAssertTrue(controls().canPress(fix))
        XCTAssertFalse(controls(isCatchingUp: true).canPress(fix), "its frames are those of the render that is under way")
        XCTAssertFalse(controls(isReady: false).canPress(fix))
    }

    func testAnUndoPressIsOnOnlyWhereThereIsSomethingToUndo() {
        XCTAssertFalse(controls().canPress(.undo))
        XCTAssertTrue(controls(canUndo: true).canPress(.undo))
        XCTAssertTrue(controls(canUndo: true, isCatchingUp: true).canPress(.undo), "going back reads no position")
    }
}
