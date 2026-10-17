import XCTest
@testable import NotificationCore

/// The delete confirmation tests a blank name as the loader does (`String.isBlank`): a
/// name or a Shortcut's name that is only spaces and line breaks is no name.
final class DeleteConfirmationBlankTests: XCTestCase {
    private let teams = RuleCondition.field(.app, .equals, "Microsoft Teams")

    func testARuleNamedWithOnlyALineBreakIsAskedAboutWithoutAName() throws {
        let fresh = Rule(name: " \n", condition: teams)
        let asked = try XCTUnwrap(EditorText.deleteConfirmation(for: fresh, saved: []))
        XCTAssertEqual(asked.title, "Delete this rule?")
    }

    func testAShortcutNamedWithOnlyALineBreakIsNotSaidToRun() {
        let saved = Rule(name: "On call", condition: teams,
                         escalation: Escalation(tier4: FinalAlert(afterSeconds: 120, action: .shortcut(name: "\n"))))
        XCTAssertNil(EditorText.deleteConfirmation(for: saved, saved: [saved]), "a saved, unchanged rule with no Shortcut is deleted at once")
    }

    func testANameIsShownWithoutTheLineBreaksAroundIt() throws {
        let fresh = Rule(name: "\nOn call\n", condition: teams)
        let asked = try XCTUnwrap(EditorText.deleteConfirmation(for: fresh, saved: []))
        XCTAssertEqual(asked.title, "Delete “On call”?")
    }
}
