import XCTest
@testable import NotificationCore

/// The words the read-only window adds to the sound editor's text (sound editor plan, Task 7): what is said while a
/// sound is being opened, when a preview could not be played for a reason that is not an alert, and what the
/// scroller of a zoomed waveform is called.
final class SoundEditorWindowTextTests: XCTestCase {
    private typealias Text = SoundEditorText

    private var words: [String] {
        [Text.opening("Night Alarm"), Text.previewFailed, Text.visiblePartLabel]
    }

    func testNoWordIsEmptyOrHasSpacesAtItsEndsOrUsesTheCodesOwnTerms() {
        let jargon = ["recipe", "frame", "segment", "sidecar", "digest", "render", "excerpt", "buffer", "dBFS", "SoundEdit"]
        for word in words {
            XCTAssertFalse(word.isEmpty)
            XCTAssertEqual(word, word.trimmingCharacters(in: .whitespacesAndNewlines), word)
            for term in jargon {
                XCTAssertFalse(word.lowercased().contains(term.lowercased()), "“\(word)” says “\(term)”")
            }
        }
    }

    func testWhileASoundIsOpenedTheWindowSaysWhichIsBeingOpened() {
        XCTAssertEqual(Text.opening("Night Alarm"), "Opening “Night Alarm”…")
    }

    func testAPreviewThatCouldNotBePlayedForAnotherReasonSaysSoAndIsNotTheAlertSentence() {
        XCTAssertTrue(Text.previewFailed.hasSuffix("."), Text.previewFailed)
        XCTAssertNotEqual(Text.previewFailed, Text.previewRefused, "an alert sounding is told apart from the rest")
        XCTAssertFalse(Text.previewFailed.contains("alert"), "it must not say an alert is sounding when none is")
        XCTAssertFalse(Text.previewFailed.lowercased().contains("engine"), "the player's own terms are not the person's")
    }

    func testTheScrollerIsNamedForWhatItMoves() {
        XCTAssertEqual(Text.visiblePartLabel, "Visible part of the sound")
    }
}
