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
        for kind in SoundFinding.Kind.allCases {
            XCTAssertNil(SoundEditorText.press(for: finding(kind, fix: nil)), "\(kind): no fix, no press")
            let withFix = SoundEditorText.press(for: finding(kind, fix: .undo))
            XCTAssertEqual(withFix, SoundEditorText.pressLabel(for: kind), "\(kind)")
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

    func testAnEditThatCouldNotBeMadeIsToldInPlainWordsAndNeverInTheCodes() {
        let sentence = SoundEditorText.editFailed
        XCTAssertFalse(sentence.isEmpty)
        XCTAssertTrue(sentence.hasSuffix("."))
        for word in ["recipe", "frame", "history", "error", "SoundEdit"] {
            XCTAssertFalse(sentence.localizedCaseInsensitiveContains(word), word)
        }
    }

    func testTheSentenceBesideTheGainIsRulingSixteensAndIsOffered() {
        XCTAssertTrue(SoundEditorText.gainNote.contains("against the rest of the sound"))
        XCTAssertTrue(SoundEditorText.gainNeedsASelection.contains("not all of it"))
    }
}
