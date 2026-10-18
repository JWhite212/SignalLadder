import XCTest
@testable import NotificationCore

/// The sheet a save refused because rules.json changed under the editor. Return
/// presses its first button, and the save that led here was most likely a Return
/// on the close prompt's Save, so a second Return must leave the draft as it was.
/// Reload from Disk throws the draft away, so it is never first, and the sheet
/// says what it does.
final class ConflictSheetTests: XCTestCase {
    func testCancelIsFirstSoReturnLeavesTheDraftAsItWas() {
        XCTAssertEqual(EditorText.conflictChoices.first, .cancel)
    }

    func testTheButtonsReadCancelSaveAnywayAndReloadFromDisk() {
        XCTAssertEqual(EditorText.conflictChoices.map(\.title), ["Cancel", "Save Anyway", "Reload from Disk"])
    }

    /// The one that loses the draft is drawn as destructive, and it is the one the
    /// sheet's words say loses it.
    func testOnlyReloadFromDiskDiscardsTheDraft() {
        XCTAssertEqual(EditorText.conflictChoices.filter(\.discardsTheDraft), [.reloadFromDisk])
    }

    /// The app finds the choice from the button's place, so a reordering cannot
    /// leave a button doing what another one says.
    func testEachButtonsPlaceGivesBackItsChoice() {
        for (index, choice) in EditorText.conflictChoices.enumerated() {
            XCTAssertEqual(EditorText.conflictChoice(at: index), choice, "button \(index)")
        }
        XCTAssertNil(EditorText.conflictChoice(at: -1))
        XCTAssertNil(EditorText.conflictChoice(at: EditorText.conflictChoices.count))
    }

    func testTheSheetSaysWhatHappenedWhatSaveAnywayKeepsAndWhatReloadDiscards() {
        let text = EditorText.conflictInformative(RulesChange.between(nil, nil))
        XCTAssertEqual(text, "Nothing has changed.\n\n"
                       + "Save Anyway keeps the version on disk as a dated copy beside rules.json. "
                       + "Reload from Disk discards your unsaved changes and shows rules.json as it is now.")
    }
}

/// How the editor's window controller builds that sheet. The app target has no
/// tests, so this reads its source, as `SetupWiringTests` does: the buttons are
/// added from `EditorText.conflictChoices`, in that order, and the answer is read
/// back through `EditorText.conflictChoice(at:)`, so the button pressed is the
/// choice acted on, whatever the order.
final class ConflictSheetWiringTests: XCTestCase {
    private let signature = "private func askAboutConflict(_ change: RulesChange, then done: @escaping (Bool) -> Void) {"

    private func sheet() throws -> String {
        let source = try XCTUnwrap(AppSources.read("RuleEditorWindowController.swift"),
                                   "RuleEditorWindowController.swift cannot be read at \(AppSources.directory.path)")
        let code = SourceCode.code(of: source)
        return try XCTUnwrap(SourceCode.body(of: signature, in: code), "\(signature) is not in the source exactly once")
    }

    private func run(_ lines: [String], in text: String) -> Int {
        count("\n" + lines.joined(separator: "\n") + "\n", in: "\n" + text + "\n")
    }

    func testTheButtonsAreAddedFromTheCoresChoicesInTheirOrder() throws {
        let body = try sheet()
        XCTAssertEqual(run([
            "alert.informativeText = EditorText.conflictInformative(change)",
            "for choice in EditorText.conflictChoices {",
            "alert.addButton(withTitle: choice.title).hasDestructiveAction = choice.discardsTheDraft",
            "}",
        ], in: body), 1)
        XCTAssertEqual(count("addButton(", in: body), 1, "no button of the sheet's own")
    }

    func testTheAnswerIsReadBackByThePlaceOfTheButtonPressed() throws {
        let body = try sheet()
        XCTAssertEqual(run([
            "let first = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue",
            "switch EditorText.conflictChoice(at: response.rawValue - first) {",
            "case .reloadFromDisk:",
            "self.model.reloadFromDisk()",
            "done(false)",
            "case .saveAnyway:",
        ], in: body), 1)
        XCTAssertEqual(count("self.model.reloadFromDisk()", in: body), 1, "the draft is discarded in one place")
        XCTAssertEqual(count("case .cancel, nil:", in: body), 1)
        XCTAssertEqual(count("case .alert", in: body), 0, "no answer is read by a fixed button number")
    }
}
