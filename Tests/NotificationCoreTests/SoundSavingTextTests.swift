import XCTest
@testable import NotificationCore

/// The words the way in to the sound editor and its saving add (sound editor plan, Task 9), held where they are made.
final class SoundSavingTextTests: XCTestCase {
    private typealias Text = SoundEditorText

    func testTheWayInIsOneButtonBesideAddSound() {
        XCTAssertEqual(EditorText.editSound, "Edit Sound…")
        XCTAssertNotEqual(EditorText.editSound, EditorText.addSound)
    }

    func testANameThatIsTakenSaysSoAndOnlyPointsToSaveWhenSaveWouldReplaceIt() {
        XCTAssertEqual(Text.nameInUse("Klaxon", replaceable: false),
                       "You already have a sound called “Klaxon”. Choose another name.")
        XCTAssertEqual(Text.nameInUse("Alarm", replaceable: true),
                       "You already have a sound called “Alarm”. Choose another name, or use Save to replace it.")
        XCTAssertTrue(Text.nameInUse("Alarm", replaceable: true).contains("use \(Text.save) to"), "the button is named as it is spelt")
    }

    func testSavingOverIsAskedAsAConfirmationWhoseFirstButtonKeepsTheSound() {
        let confirmation = Text.saveOverConfirmation("Alarm", ruleCount: 3)
        XCTAssertEqual(confirmation.title, Text.saveOverQuestion("Alarm"))
        XCTAssertEqual(confirmation.detail, Text.saveOverDetail(ruleCount: 3))
        XCTAssertEqual(confirmation.proceed, Text.saveOver)
        XCTAssertEqual(confirmation.buttons, [EditorText.cancel, Text.saveOver])
        XCTAssertFalse(confirmation.proceeds(atButton: 0))
        XCTAssertTrue(confirmation.proceeds(atButton: 1))
    }

    func testTheButtonSaysWhenASaveIsUnderWay() {
        XCTAssertEqual(Text.saving, "Saving…")
    }

    func testNoneOfItIsEmptyOrUsesTheCodesOwnTerms() {
        let jargon = ["recipe", "frame", "segment", "sidecar", "digest", "render", "excerpt", "buffer", "dBFS", "SoundEdit"]
        let words = [EditorText.editSound, Text.nameInUse("Alarm", replaceable: true), Text.nameInUse("Alarm", replaceable: false),
                     Text.saveOverConfirmation("Alarm", ruleCount: 1).title, Text.saving]
        for word in words {
            XCTAssertEqual(word, word.trimmingCharacters(in: .whitespacesAndNewlines), word)
            XCTAssertFalse(word.isEmpty)
            for term in jargon { XCTAssertFalse(word.lowercased().contains(term.lowercased()), "“\(word)” says “\(term)”") }
        }
    }
}
