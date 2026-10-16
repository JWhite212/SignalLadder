import XCTest
@testable import NotificationCore

/// A rule editor that opened read-only, on a file it cannot read, one from a newer
/// SignalLadder or one with a rule it cannot decode, offered only to open the file in a
/// text editor. Once the file was fixed the window stayed read-only, and the way on was
/// the status menu's Reload Rules, which the window did not mention (workflow audit,
/// 2026-10-16, finding 6). It now says what to do and has the button: Reload Rules, in
/// the menu item's own words, doing what Put into Effect does, which reloads the rules
/// and with them an editor that holds no draft. A read-only editor never holds one.
final class ReadOnlyReloadTests: XCTestCase {
    func testTheReadOnlyEditorSaysToReloadInTheMenuItemsOwnWords() {
        XCTAssertEqual(EditorText.readOnlyNextStep,
                       "When you have changed the file in a text editor, choose Reload Rules to read it again.")
        XCTAssertTrue(EditorText.readOnlyNextStep.contains(StatusMenuText.reloadRulesTitle))
    }
}

/// How the editor's view wires that button. The app target has no tests, so this reads
/// its source, as `SetupWiringTests` does.
final class ReadOnlyReloadWiringTests: XCTestCase {
    private func code(_ file: String) throws -> String {
        PowerHoldWiringTests.code(of: try XCTUnwrap(AppSources.read(file), "\(file) cannot be read at \(AppSources.directory.path)"))
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    func testTheReadOnlyViewHasTheSentenceAndAReloadRulesButton() throws {
        let view = try code("RuleEditorView.swift")
        let readOnly = try XCTUnwrap(OnCallWiringTests.body(of: "private struct ReadOnlyView: View {", in: view))
        XCTAssertEqual(count("let reload: () -> Void", in: readOnly), 1)
        XCTAssertEqual(count("Text(EditorText.readOnlyNextStep)", in: readOnly), 1)
        XCTAssertEqual(count("Button(StatusMenuText.reloadRulesTitle, action: reload)", in: readOnly), 1)
    }

    /// The button does what Put into Effect does: the app delegate's reload of the rules,
    /// which reloads an open editor that holds no draft.
    func testTheButtonReloadsTheRulesAsPutIntoEffectDoes() throws {
        let view = try code("RuleEditorView.swift")
        XCTAssertEqual(count("ReadOnlyView(reason: reason, openInTextEditor: actions.openInTextEditor, reload: model.putIntoEffect)",
                             in: view), 1)
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("model.onApply = { [weak self] in self?.reloadRules() }", in: app), 1)
        let reload = try XCTUnwrap(OnCallWiringTests.body(of: "private func reloadRules() {", in: app))
        XCTAssertEqual(count("if ruleEditor.isOpen, !ruleEditor.model.hasUnsavedChanges {", in: reload), 1)
        XCTAssertEqual(count("ruleEditor.model.reloadFromDisk()", in: reload), 1)
    }
}
