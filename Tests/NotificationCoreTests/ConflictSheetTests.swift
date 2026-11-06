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

/// A file on disk that differs from the editor's copy only in the order of its
/// rules, or only in its version, is not "only formatting": order is priority, so
/// a rule moved above a paging rule changes which rule claims a notification, and
/// the version decides which rules the loader accepts.
final class ConflictSheetOrderTests: XCTestCase {
    private let teams = #""condition": {"field": "app", "op": "equals", "value": "Microsoft Teams"}"#

    private func rule(_ name: String, extra: String = "", id: String? = nil) -> String {
        let idPart = id.map { "\"id\": \"\($0)\", " } ?? ""
        return "{\(idPart)\"name\": \"\(name)\", \(teams)\(extra)}"
    }

    func testTwoRulesSwappedOnDiskAreReportedAsReordered() {
        let before = rulesFile(version: 2, rule("Page"), rule("Catch all"))
        let after = rulesFile(version: 2, rule("Catch all"), rule("Page"))
        let change = RulesChange.between(before, after)
        XCTAssertEqual(change.file, .edited)
        XCTAssertTrue(change.reordered)
        XCTAssertEqual(change.added, [])
        XCTAssertEqual(change.removed, [])
        XCTAssertEqual(change.changed, [])
        XCTAssertFalse(change.versionChanged)
    }

    func testTheSheetSaysTheRulesWereReorderedAndNotThatOnlyFormattingChanged() {
        let before = rulesFile(version: 2, rule("Page"), rule("Catch all"))
        let after = rulesFile(version: 2, rule("Catch all"), rule("Page"))
        XCTAssertEqual(EditorText.conflictDetail(RulesChange.between(before, after)),
                       "Its rules were put in a different order.")
    }

    func testSameNamedRulesSwappedAreStillReordered() {
        let a = rule("Alert", extra: #", "enabled": false"#)
        let b = rule("Alert")
        XCTAssertTrue(RulesChange.between(rulesFile(version: 2, a, b), rulesFile(version: 2, b, a)).reordered)
    }

    func testAReorderAlongsideARenameIsStillSeen() {
        let before = rulesFile(version: 2, rule("One", id: "1"), rule("Two", id: "2"))
        let after = rulesFile(version: 2, rule("Two", id: "2"), rule("One renamed", id: "1"))
        let change = RulesChange.between(before, after)
        XCTAssertTrue(change.reordered)
        XCTAssertEqual(change.renamed, [RulesChange.Rename(from: "One", to: "One renamed")])
    }

    func testARuleCopiedByHandWithItsIdKeptIsAddedAndNotARenameOfTheOriginal() {
        let before = rulesFile(version: 2, rule("A", id: "1"))
        let after = rulesFile(version: 2, rule("A", id: "1"), rule("B", id: "1"))
        let change = RulesChange.between(before, after)
        XCTAssertEqual(change.added, ["B"])
        XCTAssertEqual(change.renamed, [])
        XCTAssertEqual(change.changed, [])
    }

    func testTheCopyIsAddedWhicheverSideOfTheOriginalItStands() {
        let before = rulesFile(version: 2, rule("A", id: "1"))
        let after = rulesFile(version: 2, rule("B", id: "1"), rule("A", id: "1"))
        let change = RulesChange.between(before, after)
        XCTAssertEqual(change.added, ["B"])
        XCTAssertEqual(change.renamed, [])
    }

    func testAnEditedRuleThatMovedIsReportedAsBothChangedAndReordered() {
        let before = rulesFile(version: 2, rule("A"), rule("B"))
        let after = rulesFile(version: 2, rule("B", extra: #", "enabled": false"#), rule("A"))
        let change = RulesChange.between(before, after)
        XCTAssertEqual(change.changed, ["B"])
        XCTAssertTrue(change.reordered)
        XCTAssertEqual(EditorText.conflictDetail(change),
                       "Its rules were put in a different order. Changed: “B”.")
    }

    func testARuleAddedOrRemovedWithoutMovingTheOthersIsNotAReorder() {
        let base = rulesFile(version: 2, rule("A"), rule("B"))
        XCTAssertFalse(RulesChange.between(base, rulesFile(version: 2, rule("A"), rule("B"), rule("C"))).reordered)
        XCTAssertFalse(RulesChange.between(base, rulesFile(version: 2, rule("B"))).reordered)
        XCTAssertFalse(RulesChange.between(base, rulesFile(version: 2, rule("A"), rule("New"), rule("B"))).reordered)
    }

    func testAFileWhoseOnlyDifferenceIsItsVersionSaysSo() {
        let before = rulesFile(version: 2, rule("A"))
        let after = rulesFile(version: 3, rule("A"))
        let change = RulesChange.between(before, after)
        XCTAssertEqual(change.file, .edited)
        XCTAssertTrue(change.versionChanged)
        XCTAssertFalse(change.reordered)
        XCTAssertEqual(EditorText.conflictDetail(change), "Its format version changed.")
    }

    func testAReorderAndAVersionChangeAreBothSaid() {
        let before = rulesFile(version: 2, rule("A"), rule("B"))
        let after = rulesFile(version: 3, rule("B"), rule("A"))
        XCTAssertEqual(EditorText.conflictDetail(RulesChange.between(before, after)),
                       "Its rules were put in a different order. Its format version changed.")
    }

    func testReformattingAloneIsStillOnlyFormatting() {
        let before = Data("{\"version\": 2, \"rules\": [{\"name\": \"A\", \(teams)}, {\"name\": \"B\", \(teams)}]}".utf8)
        let after = Data("{\n  \"rules\": [ { \(teams), \"name\": \"A\" }, { \(teams), \"name\": \"B\" } ],\n  \"version\": 2\n}".utf8)
        let change = RulesChange.between(before, after)
        XCTAssertFalse(change.reordered)
        XCTAssertFalse(change.versionChanged)
        XCTAssertEqual(EditorText.conflictDetail(change), "Only its formatting changed.")
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
