import XCTest
@testable import NotificationCore

/// What the rule editor asks before it loses work in the draft (workflow audit, 2026-10-16,
/// finding 9). Closing with a draft already asked; Revert and deleting a rule acted at once,
/// and the draft has no undo. Revert now always asks, since it is offered only while there is
/// something to lose. Deleting a rule asks when it would lose what Revert cannot bring back,
/// or a Shortcut's name: a rule never saved that is more than a blank new one, a saved rule
/// changed since the last save, or a rule whose last step runs a Shortcut. An untouched new
/// rule, and a saved rule with no changes and no Shortcut, are deleted at once.
final class DraftSafetyTests: XCTestCase {
    private let teams = RuleCondition.field(.app, .equals, "Microsoft Teams")
    private let page = Escalation(tier4: FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me")))

    private func rule(_ name: String = "On call", condition: RuleCondition? = nil, escalation: Escalation? = nil) -> Rule {
        Rule(name: name, condition: condition ?? teams, isEnabled: true, alert: .sound(name: "Glass", gainDB: 0),
             escalation: escalation)
    }

    // MARK: - The confirmation

    /// Cancel is the first button, so Return keeps the work, as on the sheet a refused
    /// save shows; the second goes ahead and is drawn as destructive.
    func testCancelIsFirstAndOnlyTheSecondButtonGoesAhead() {
        let confirmation = EditorText.revertConfirmation
        XCTAssertEqual(confirmation.buttons, ["Cancel", "Revert"])
        XCTAssertEqual([-1, 0, 1, 2].map(confirmation.proceeds(atButton:)), [false, false, true, false])
    }

    func testRevertSaysEveryUnsavedChangeIsDiscarded() {
        XCTAssertEqual(EditorText.revertConfirmation.title, "Revert to the saved rules?")
        XCTAssertEqual(EditorText.revertConfirmation.detail, "Every change since you last saved is discarded, and cannot be brought back.")
        XCTAssertEqual(EditorText.revertConfirmation.proceed, "Revert")
    }

    // MARK: - Deleting a rule

    func testASavedRuleWithNoChangesAndNoShortcutIsDeletedAtOnce() {
        let saved = rule()
        XCTAssertNil(EditorText.deleteConfirmation(for: saved, saved: [saved]))
    }

    func testAnUntouchedNewRuleIsDeletedAtOnce() {
        let blank = Rule(name: "New rule", condition: .blank, isEnabled: false)
        XCTAssertNil(EditorText.deleteConfirmation(for: blank, saved: [rule()]))
    }

    func testASavedRuleChangedSinceTheLastSaveAsks() throws {
        let saved = rule()
        var changed = saved
        changed.name = "On call, renamed"
        let asked = try XCTUnwrap(EditorText.deleteConfirmation(for: changed, saved: [saved]))
        XCTAssertEqual(asked.title, "Delete “On call, renamed”?")
        XCTAssertEqual(asked.detail, "Its changes since you last saved would be lost: Revert brings back only the saved version.")
        XCTAssertEqual(asked.buttons, ["Cancel", "Delete"])
    }

    func testANewRuleWithAnythingInItAsks() throws {
        let asked = try XCTUnwrap(EditorText.deleteConfirmation(for: rule("Fresh"), saved: []))
        XCTAssertEqual(asked.detail, "It has never been saved, so nothing can bring it back.")
    }

    func testASavedRuleThatRunsAShortcutAsksAndNamesIt() throws {
        let saved = rule(escalation: page)
        let asked = try XCTUnwrap(EditorText.deleteConfirmation(for: saved, saved: [saved]))
        XCTAssertEqual(asked.detail, "Its final step runs the Shortcut “Page me”. "
                       + "Until you save, Revert brings it back, but it also undoes every other change since you last saved.")
    }

    func testAShortcutAndUnsavedChangesAreBothSaid() throws {
        let saved = rule(escalation: page)
        var changed = saved
        changed.isEnabled = false
        let asked = try XCTUnwrap(EditorText.deleteConfirmation(for: changed, saved: [saved]))
        XCTAssertEqual(asked.detail, "Its final step runs the Shortcut “Page me”. "
                       + "Its changes since you last saved would be lost: Revert brings back only the saved version.")
    }

    /// A blank Shortcut name is a refusal of its own, and names nothing to lose.
    func testABlankShortcutNameIsNoShortcut() {
        let blankName = rule(escalation: Escalation(tier4: FinalAlert(action: .shortcut(name: "  "))))
        XCTAssertNil(EditorText.deleteConfirmation(for: blankName, saved: [blankName]))
    }

    func testARuleWithNoNameIsCalledThisRule() throws {
        let unnamed = rule("  ")
        XCTAssertEqual(try XCTUnwrap(EditorText.deleteConfirmation(for: unnamed, saved: [])).title, "Delete this rule?")
    }
}
