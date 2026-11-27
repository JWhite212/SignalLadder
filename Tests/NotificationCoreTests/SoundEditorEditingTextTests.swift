import XCTest
@testable import NotificationCore

/// The words and the shortcuts the sound editor's editing adds (sound editor plan, Rulings 12, 13 and 16 and Task 8).
final class SoundEditorEditingTextTests: XCTestCase {
    typealias Command = SoundEditorText.Command

    // MARK: - Shortcuts

    func testExactlyTheSevenEditsOfThePlanHaveAShortcutAndEachIsAsTheMacHasIt() {
        let expected: [Command: (Character, Bool)] = [
            .cut: ("x", false), .copy: ("c", false), .paste: ("v", false), .duplicate: ("d", false),
            .undo: ("z", false), .redo: ("z", true), .selectAll: ("a", false),
        ]
        for command in Command.allCases {
            if let (key, shift) = expected[command] {
                XCTAssertEqual(command.shortcut, Command.Shortcut(key: key, shift: shift), "\(command)")
            } else {
                XCTAssertNil(command.shortcut, "\(command) has none: Space and the arrows are the waveform's, not shortcuts")
            }
        }
    }

    func testNoTwoCommandsShareAShortcut() {
        let shortcuts = Command.allCases.compactMap { $0.shortcut }.map { "\($0.key)\($0.shift)" }
        XCTAssertEqual(Set(shortcuts).count, shortcuts.count)
    }

    func testAShortcutIsAlwaysALowerCaseLetter() {
        for shortcut in Command.allCases.compactMap({ $0.shortcut }) {
            XCTAssertTrue(shortcut.key.isLetter && shortcut.key.isLowercase, "\(shortcut.key)")
        }
    }

    // MARK: - The press beside a check

    private func finding(_ kind: SoundFinding.Kind, fix: SoundFix?) -> SoundFinding {
        SoundFinding(kind: kind, frames: nil, fix: fix)
    }

    func testAPressIsLabelledOnlyForAFindingWhoseOwnFixIsThere() {
        // What each kind's button says, written out so that a button cannot come to say another's, or to be on for a kind
        // that has no press at all.
        let labels: [SoundFinding.Kind: String?] = [
            .nothingToHear: "Undo", .tooLong: "Keep the First 30 Seconds", .startsAbruptly: "Fade In the Start",
            .tooShort: "Repeat It 3 Times", .silenceAtStart: "Trim the Silence at the Start",
            .silenceAtEnd: "Trim the Silence at the End", .clipping: nil,
        ]
        XCTAssertEqual(labels.count, SoundFinding.Kind.allCases.count, "every kind is named here")
        for kind in SoundFinding.Kind.allCases {
            XCTAssertNil(SoundEditorText.press(for: finding(kind, fix: nil)), "\(kind): no fix, no press")
            XCTAssertEqual(SoundEditorText.press(for: finding(kind, fix: .undo)), labels[kind] ?? nil, "\(kind)")
        }
    }

    func testTheClippingCheckHasNoFixAndSoNoPress() throws {
        let clipped = SoundChecks.findings(in: SoundSignals.constant(1, frames: 48_000))
        let clipping = try XCTUnwrap(clipped.first { $0.kind == .clipping })
        XCTAssertNil(clipping.fix)
        XCTAssertNil(SoundEditorText.press(for: clipping), "advice only: the damage is in the sound")
    }

    // MARK: - Beside the sliders and steppers

    func testAGainIsWrittenInDecibelsWithItsSignAndZeroWithNone() {
        XCTAssertEqual(SoundEditorText.gainValue(6), "+6 dB")
        XCTAssertEqual(SoundEditorText.gainValue(-3), "−3 dB")
        XCTAssertEqual(SoundEditorText.gainValue(-2.5), "−2.5 dB")
        XCTAssertEqual(SoundEditorText.gainValue(0), "0 dB")
    }

    func testThePlaysOfARepeatAreCounted() {
        XCTAssertEqual(SoundEditorText.playsValue(3), "3 plays")
        XCTAssertEqual(SoundEditorText.playsValue(2), "2 plays")
        XCTAssertEqual(SoundEditorText.playsValue(1), "1 play")
    }

    func testTheGapOfARepeatIsWrittenInSecondsOrAsNoneAtAll() {
        XCTAssertEqual(SoundEditorText.gapValue(0), "no gap")
        XCTAssertEqual(SoundEditorText.gapValue(0.3), "0.3 seconds")
        XCTAssertEqual(SoundEditorText.gapValue(0.05), "0.05 seconds")
        XCTAssertEqual(SoundEditorText.gapValue(1), "1 second")
        XCTAssertEqual(SoundEditorText.gapValue(2.5), "2.5 seconds")
    }

    func testAPreviewThatCannotBePlayedBecauseThereIsNothingToHearSaysSoAndIsNotTheOtherTwo() {
        let sentence = SoundEditorText.previewSilent
        XCTAssertTrue(sentence.hasSuffix("."))
        XCTAssertTrue(sentence.localizedCaseInsensitiveContains("nothing to hear"))
        XCTAssertEqual(Set([sentence, SoundEditorText.previewRefused, SoundEditorText.previewFailed]).count, 3)
    }

    func testAnEditThatCouldNotBeMadeIsToldInPlainWordsAndNeverInTheCodes() {
        let sentence = SoundEditorText.editFailed
        XCTAssertFalse(sentence.isEmpty)
        XCTAssertTrue(sentence.hasSuffix("."))
        for word in ["recipe", "frame", "history", "error", "SoundEdit"] {
            XCTAssertFalse(sentence.localizedCaseInsensitiveContains(word), word)
        }
    }

    func testTheSentencesBesideTheGainSayWhatRulingSixteenSaysOfIt() {
        // That a gain is of the selection against the rest, that how loud the whole plays is not the gain's to set, and that
        // a selection of part of the sound is what it needs.
        let note = SoundEditorText.gainNote
        XCTAssertTrue(note.contains("changes the selection against the rest of the sound"))
        XCTAssertTrue(note.contains("raising all of it would change nothing you can hear"))
        XCTAssertTrue(SoundEditorText.gainNeedsASelection.contains("not all of it"))
        XCTAssertNotEqual(note, SoundEditorText.gainNeedsASelection)
    }
}
