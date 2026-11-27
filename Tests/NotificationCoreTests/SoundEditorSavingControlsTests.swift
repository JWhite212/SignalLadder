import XCTest
@testable import NotificationCore

/// What the editing controls do while a save is under way (sound editor plan, Task 9): the sound that is being written is the
/// recipe as it was when Save was pressed, so nothing is changed under it, and what is shown stays what is written.
final class SoundEditorSavingControlsTests: XCTestCase {
    private func controls(isSaving: Bool, selection: Range<Int>? = 1000..<2000) -> SoundEditorControls {
        SoundEditorControls(isReady: true, length: 48_000, canBeHeard: true, isPreviewing: false, selection: selection,
                            viewport: WaveformViewport(length: 48_000), loops: false, canUndo: true, canRedo: true,
                            canReset: true, hasClipboard: true, isCatchingUp: false, gainDB: 6, isSaving: isSaving)
    }

    func testEveryCommandThatChangesTheSoundIsOffWhileItIsBeingSaved() {
        let saving = controls(isSaving: true)
        for command: SoundEditorText.Command in [.trim, .delete, .cut, .paste, .duplicate, .fadeIn, .fadeOut, .gain,
                                                 .repeatSelection, .undo, .redo, .resetToOriginal] {
            XCTAssertFalse(saving.canPerform(command), "\(command)")
        }
    }

    func testTheSameCommandsAreOnWhenNoSaveIsUnderWay() {
        let idle = controls(isSaving: false)
        for command: SoundEditorText.Command in [.trim, .delete, .cut, .paste, .duplicate, .fadeIn, .fadeOut, .gain,
                                                 .repeatSelection, .undo, .redo, .resetToOriginal] {
            XCTAssertTrue(idle.canPerform(command), "\(command)")
        }
    }

    func testHearingAndSelectingAreStillOnBecauseTheyChangeNothingThatIsWritten() {
        let saving = controls(isSaving: true)
        XCTAssertTrue(saving.canPerform(.play))
        XCTAssertTrue(saving.canPerform(.selectAll))
        XCTAssertTrue(saving.canPerform(.clearSelection))
        XCTAssertTrue(saving.canPerform(.loopSelection))
    }

    func testThePressOfACheckIsOffWhileItIsBeingSaved() {
        XCTAssertFalse(controls(isSaving: true).canPress(.undo))
        XCTAssertFalse(controls(isSaving: true).canPress(.edit(.trim(0..<10))))
        XCTAssertTrue(controls(isSaving: false).canPress(.undo))
        XCTAssertTrue(controls(isSaving: false).canPress(.edit(.trim(0..<10))))
    }

    func testAControlsMadeWithoutSayingIsNotSaving() {
        let plain = SoundEditorControls(isReady: true, length: 100, canBeHeard: true, isPreviewing: false, selection: nil,
                                        viewport: WaveformViewport(length: 100), loops: false)
        XCTAssertFalse(plain.isSaving)
    }
}
