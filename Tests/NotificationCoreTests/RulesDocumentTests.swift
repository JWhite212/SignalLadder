import XCTest
@testable import NotificationCore

/// What the editor may edit, and what it must not.
final class RulesDocumentTests: XCTestCase {
    private func data(_ s: String) -> Data { Data(s.utf8) }
    private func file(version: Int = 2, _ rules: String) -> Data { data("{\"version\": \(version), \"rules\": [\(rules)]}") }
    private let teams = #""condition": {"field": "app", "op": "equals", "value": "Microsoft Teams"}"#

    private func editable(_ document: RulesDocument, file: StaticString = #filePath, line: UInt = #line) -> [Rule] {
        guard case .editable(let rules) = document else {
            XCTFail("expected an editable document, got \(document)", file: file, line: line)
            return []
        }
        return rules
    }

    // MARK: - What can be edited

    func testNoFileIsAnEmptyDocument() {
        XCTAssertEqual(RulesDocument.load(nil), .editable([]))
    }

    func testRulesAreKeptInFileOrder() {
        let rules = editable(RulesDocument.load(file(#"{"name": "B", \#(teams)}, {"name": "A", \#(teams)}"#)))
        XCTAssertEqual(rules.map(\.name), ["B", "A"], "order is priority")
    }

    func testARuleWithProblemsIsKeptSoTheEditorCanFixIt() {
        // Each of these is dropped by the loader so it cannot fire. The
        // editor must still show it: that is where it gets fixed.
        let rules = editable(RulesDocument.load(file(version: 1, """
            {"name": "Loud", \(teams), "alert": {"sound": "Glass", "gainDB": 100}},
            {"name": "Missing sound", \(teams), "alert": {"sound": "Glas"}},
            {"name": "Empty group", "condition": {"and": []}}
            """)))
        XCTAssertEqual(rules.map(\.name), ["Loud", "Missing sound", "Empty group"])
    }

    // MARK: - What must not be edited

    func testAnEntryThatIsNotARuleMakesTheDocumentReadOnly() {
        // Saving would have to drop it, and only a text editor can fix it.
        let document = RulesDocument.load(file(#"{"name": "Fine", \#(teams)}, {"name": "Typo", \#(teams), "alrt": "silent"}"#))
        guard case .readOnly(.undecodable(let problems)) = document else { return XCTFail("\(document)") }
        XCTAssertEqual(problems.count, 1)
        XCTAssertEqual(problems.first?.index, 1)
        XCTAssertEqual(problems.first?.name, "Typo")
        XCTAssertTrue(problems.first?.reason.contains("unknown key \"alrt\"") ?? false, "\(problems)")
    }

    func testAFileThatIsNotJSONIsReadOnly() {
        guard case .readOnly(.unreadable(let reason)) = RulesDocument.load(data("{ nope")) else { return XCTFail() }
        XCTAssertTrue(reason.hasPrefix("not valid JSON"), reason)
    }

    func testAFileOfTheWrongShapeIsReadOnly() {
        guard case .readOnly(.unreadable) = RulesDocument.load(data(#"{"version": 2}"#)) else { return XCTFail() }
    }

    func testAFileFromANewerVersionIsReadOnly() {
        let newer = RuleSetCodec.currentVersion + 1
        XCTAssertEqual(RulesDocument.load(data("{\"version\": \(newer), \"rules\": []}")), .readOnly(.newerVersion(newer)))
    }

    // MARK: - Problems, worked out live

    private let sounds = RuleSetCodec.SoundCheck(available: ["Glass"], unplayable: nil, voices: nil)

    func testTheEditorAndTheLoaderReportTheSameProblems() {
        // One set of checks for both, so the editor never calls a rule fine
        // that the menu then refuses, or the other way round.
        let json = """
            {"name": "Loud", \(teams), "alert": {"sound": "Glas", "gainDB": 100}},
            {"name": "Empty", "condition": {"or": []}},
            {"name": "", \(teams), "alert": {"sound": " "}}
            """
        let rules = editable(RulesDocument.load(file(json)))
        let (_, status) = RuleStoreStatus.load(file(json), availableSounds: ["Glass"], unplayable: nil, availableVoices: nil)

        let fromEditor = rules.enumerated().map { index, rule in
            RuleSetCodec.Problem(index: index, name: rule.name,
                                 reason: RulesDocument.problems(in: rule, sounds: sounds).joined(separator: "; ")).description
        }
        XCTAssertEqual(fromEditor, status.detail)
    }

    func testFixingARuleClearsItsProblemAtOnce() {
        var rule = editable(RulesDocument.load(file(#"{"name": "Loud", \#(teams), "alert": {"sound": "Glass", "gainDB": 100}}"#)))[0]
        XCTAssertFalse(RulesDocument.problems(in: rule, sounds: sounds).isEmpty)
        rule.alert = .sound(name: "Glass", gainDB: 6)
        XCTAssertEqual(RulesDocument.problems(in: rule, sounds: sounds), [])
    }

    func testTheVersionGateDoesNotApplyInTheEditor() {
        // A version 1 file holding an alert is a problem on disk; the editor
        // writes whatever version the rules need, so there it is not one.
        let rule = editable(RulesDocument.load(file(version: 1, #"{"name": "a", \#(teams), "alert": "silent"}"#)))[0]
        XCTAssertEqual(RulesDocument.problems(in: rule, sounds: .none), [])
    }

    // MARK: - Writing

    private func writtenVersion(_ rules: [Rule]) throws -> Int {
        let object = try JSONSerialization.jsonObject(with: try RuleSetCodec.encode(rules)) as? [String: Any]
        return try XCTUnwrap(object?["version"] as? Int)
    }

    func testAFileIsWrittenAtTheLowestVersionThatHoldsIt() throws {
        let plain = Rule(name: "a", condition: .field(.app, .equals, "x"))
        XCTAssertEqual(try writtenVersion([plain]), 1, "an older build can read it")
        XCTAssertEqual(try writtenVersion([]), 1)

        var disabledWithAlert = plain
        disabledWithAlert.isEnabled = false
        disabledWithAlert.alert = .sound(name: "Glas", gainDB: 100)
        XCTAssertEqual(try writtenVersion([plain, disabledWithAlert]), 2,
                       "every alert counts, even on a rule that is off or has problems")
    }

    func testAnUntouchedVersion1RuleWithAnAlertIsSavedAtVersion2() throws {
        // The loader flags it; saving it untouched must clear the flag, not
        // write another version 1 file with the same problem.
        let rules = editable(RulesDocument.load(file(version: 1, #"{"name": "a", \#(teams), "alert": "silent"}"#)))
        let (_, status) = RuleStoreStatus.load(try RuleSetCodec.encode(rules), availableSounds: nil, unplayable: nil, availableVoices: nil)
        XCTAssertEqual(status, .loaded(enabled: 1, disabled: 0))
    }

    func testSavingWritesIdsSoRulesKeepThemFromThenOn() throws {
        let rules = editable(RulesDocument.load(file(#"{"name": "no id yet", \#(teams)}"#)))
        let saved = try RuleSetCodec.encode(rules)
        XCTAssertEqual(editable(RulesDocument.load(saved)), rules)
        XCTAssertEqual(editable(RulesDocument.load(saved)), editable(RulesDocument.load(saved)))
    }

    // MARK: - What changed on disk

    func testIdenticalFilesAreUnchanged() {
        let a = file(#"{"name": "A", \#(teams)}"#)
        XCTAssertEqual(RulesChange.between(a, a), RulesChange(file: .unchanged, added: [], removed: [], changed: []))
        XCTAssertEqual(RulesChange.between(nil, nil).file, .unchanged)
    }

    func testAFileThatAppearedNamesItsRules() {
        XCTAssertEqual(RulesChange.between(nil, file(#"{"name": "A", \#(teams)}"#)),
                       RulesChange(file: .created, added: ["A"], removed: [], changed: []))
    }

    func testAFileThatWasDeletedNamesWhatWentWithIt() {
        XCTAssertEqual(RulesChange.between(file(#"{"name": "A", \#(teams)}"#), nil),
                       RulesChange(file: .deleted, added: [], removed: ["A"], changed: []))
    }

    func testAnEditNamesRulesAddedRemovedAndChanged() {
        let before = file(#"{"name": "Keep", \#(teams)}, {"name": "Edit", \#(teams)}, {"name": "Drop", \#(teams)}"#)
        let after = file(#"{"name": "Keep", \#(teams)}, {"name": "Edit", \#(teams), "enabled": false}, {"name": "New", \#(teams)}"#)
        XCTAssertEqual(RulesChange.between(before, after),
                       RulesChange(file: .edited, added: ["New"], removed: ["Drop"], changed: ["Edit"]))
    }

    func testReformattingAloneChangesNoRule() {
        let before = data(#"{"version": 2, "rules": [{"name": "A", "enabled": true, \#(teams)}]}"#)
        let after = data("{\n  \"rules\": [ { \(teams), \"enabled\": true, \"name\": \"A\" } ],\n  \"version\": 2\n}")
        XCTAssertEqual(RulesChange.between(before, after), RulesChange(file: .edited, added: [], removed: [], changed: []))
    }

    func testAnEntryTheRuleDecoderWouldRejectIsStillCounted() {
        XCTAssertEqual(RulesChange.between(file(""), file(#"{"name": "Typo", "alrt": "silent"}"#)).added, ["Typo"])
    }

    func testTwoRulesSharingANameAreTwoRules() {
        let one = file(#"{"name": "Same", \#(teams)}"#)
        let two = file(#"{"name": "Same", \#(teams)}, {"name": "Same", \#(teams), "enabled": false}"#)
        XCTAssertEqual(RulesChange.between(one, two).added, ["Same"])
    }

    // A rename by hand was reported on 2026-09-25 as one rule removed and
    // another added, although the rule kept its id.

    func testARuleThatKeptItsIdUnderANewNameWasRenamed() {
        let before = file(#"{"id": "X", "name": "Old", \#(teams)}"#)
        let after = file(#"{"id": "X", "name": "New", \#(teams)}"#)
        XCTAssertEqual(RulesChange.between(before, after),
                       RulesChange(file: .edited, added: [], removed: [], changed: [],
                                   renamed: [RulesChange.Rename(from: "Old", to: "New")]))
    }

    func testARenamedRuleThatAlsoChangedSaysBoth() {
        let before = file(#"{"id": "X", "name": "Old", \#(teams)}"#)
        let after = file(#"{"id": "X", "name": "New", \#(teams), "enabled": false}"#)
        let change = RulesChange.between(before, after)
        XCTAssertEqual(change.renamed, [RulesChange.Rename(from: "Old", to: "New")])
        XCTAssertEqual(change.changed, ["New"])
        XCTAssertEqual(change.added, [])
        XCTAssertEqual(change.removed, [])
    }

    func testRulesWithoutIdsStillCompareByName() {
        // Written by hand, never saved by the editor: nothing ties the two.
        let change = RulesChange.between(file(#"{"name": "Old", \#(teams)}"#), file(#"{"name": "New", \#(teams)}"#))
        XCTAssertEqual(change, RulesChange(file: .edited, added: ["New"], removed: ["Old"], changed: []))
    }

    func testARenameSitsAlongsideOtherEdits() {
        let before = file(#"{"id": "X", "name": "Old", \#(teams)}, {"id": "Y", "name": "Drop", \#(teams)}"#)
        let after = file(#"{"id": "X", "name": "New", \#(teams)}, {"id": "Z", "name": "Fresh", \#(teams)}"#)
        XCTAssertEqual(RulesChange.between(before, after),
                       RulesChange(file: .edited, added: ["Fresh"], removed: ["Drop"], changed: [],
                                   renamed: [RulesChange.Rename(from: "Old", to: "New")]))
    }

    func testAnIdCopiedOntoASecondRuleIsPairedOnce() {
        // A rule duplicated by hand carries the original's id. One of the two
        // is the original; the other is new, not a second rename.
        let before = file(#"{"id": "X", "name": "Old", \#(teams)}"#)
        let after = file(#"{"id": "X", "name": "New", \#(teams)}, {"id": "X", "name": "Copy", \#(teams)}"#)
        let change = RulesChange.between(before, after)
        XCTAssertEqual(change.renamed, [RulesChange.Rename(from: "Old", to: "New")])
        XCTAssertEqual(change.added, ["Copy"])
        XCTAssertEqual(change.removed, [])
    }

    func testAnEditIntoSomethingUnreadableIsSaid() {
        XCTAssertEqual(RulesChange.between(file(""), data("{ half-typed")).file, .unreadable)
    }
}
