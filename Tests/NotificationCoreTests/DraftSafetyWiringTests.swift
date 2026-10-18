import XCTest
@testable import NotificationCore

/// How the rule editor asks before Revert and before deleting a rule. The views no longer
/// call the model's `revert` and `delete` themselves: they hand both to the window
/// controller, which runs every flow that asks the user something, and which asks in a
/// sheet with the core's words (`EditorText.revertConfirmation`, `deleteConfirmation`) and
/// acts only on the button that goes ahead. The app target has no tests, so this reads its
/// sources, as `SetupWiringTests` does.
final class DraftSafetyWiringTests: XCTestCase {
    func testTheViewsHandRevertAndDeleteToTheController() throws {
        let view = try code("RuleEditorView.swift")
        XCTAssertEqual(count("model.revert", in: view), 0, "Revert goes through the controller, which asks")
        XCTAssertEqual(count("model.delete(", in: view), 0, "a delete goes through the controller, which may ask")
        XCTAssertEqual(count("SaveBar(model: model, save: actions.save, revert: actions.revert)", in: view), 1)
        XCTAssertEqual(count("RuleListView(model: model, delete: actions.delete)", in: view), 1)
        XCTAssertEqual(count("Button(EditorText.revert, action: revert)", in: view), 1)
        XCTAssertEqual(count("delete(rule.id)", in: view), 1, "the row's context menu")
        XCTAssertEqual(count("if let id = model.selection { delete(id) }", in: view), 2, "the Delete key and the − button")
    }

    func testTheControllerAsksWithTheCoresWordsAndActsOnlyOnTheButtonThatGoesAhead() throws {
        let controller = try code("RuleEditorWindowController.swift")
        XCTAssertEqual(count("let revert: () -> Void", in: controller), 1)
        XCTAssertEqual(count("let delete: (Rule.ID) -> Void", in: controller), 1)

        let revert = try body(of: "func revert() {", in: controller)
        XCTAssertEqual(revert.trimmingCharacters(in: .whitespacesAndNewlines), [
            "guard model.hasUnsavedChanges else { return }",
            "ask(EditorText.revertConfirmation) { [weak self] in self?.model.revert() }",
        ].joined(separator: "\n"))

        let delete = try body(of: "func delete(_ id: Rule.ID) {", in: controller)
        XCTAssertEqual(delete.trimmingCharacters(in: .whitespacesAndNewlines), [
            "guard let rule = model.rules.first(where: { $0.id == id }) else { return }",
            "guard let confirmation = EditorText.deleteConfirmation(for: rule, saved: model.loadedRules) else {",
            "return model.delete(id)",
            "}",
            "ask(confirmation) { [weak self] in self?.model.delete(id) }",
        ].joined(separator: "\n"))

        let ask = try body(of: "private func ask(_ confirmation: EditorText.Confirmation, then proceed: @escaping () -> Void) {",
                           in: controller)
        XCTAssertEqual(count("for (index, title) in confirmation.buttons.enumerated() {", in: ask), 1)
        XCTAssertEqual(count("alert.addButton(withTitle: title).hasDestructiveAction = confirmation.proceeds(atButton: index)", in: ask), 1)
        XCTAssertEqual(count("if confirmation.proceeds(atButton: response.rawValue - first) { proceed() }", in: ask), 1)
        XCTAssertEqual(count("proceed()", in: ask), 1, "the work is lost on one button and no other")
    }
}
