import XCTest
@testable import NotificationCore

/// Two rules in one file with the same "id", which a hand-copied rule block is.
/// Everything that finds a rule by its id (the editor's edit, move and delete,
/// an escalation's join, a banner's "already set off") would take the copy for
/// the original, so the loader refuses the copy and the editor will not edit a
/// file that holds one.
final class DuplicateRuleIDTests: XCTestCase {
    private let id = "00000000-0000-0000-0000-0000000000A1"
    private let otherID = "00000000-0000-0000-0000-0000000000B2"
    private let teams = #""condition": {"field": "app", "op": "equals", "value": "Microsoft Teams"}"#
    private let slack = #""condition": {"field": "app", "op": "equals", "value": "Slack"}"#

    private func file(_ rules: String...) -> Data {
        Data("{\"version\": 5, \"rules\": [\(rules.joined(separator: ", "))]}".utf8)
    }

    // MARK: - The loader

    func testTheFirstRuleWithAnIDLoadsAndALaterCopyIsRefused() throws {
        let (rules, problems) = try RuleSetCodec.decode(file(
            #"{"id": "\#(id)", "name": "Original", \#(teams)}"#,
            #"{"id": "\#(id)", "name": "Copy", \#(slack)}"#))
        XCTAssertEqual(rules.map(\.name), ["Original"])
        XCTAssertEqual(problems.map(\.index), [1])
        XCTAssertEqual(problems.first?.name, "Copy")
        XCTAssertEqual(problems.first?.reason,
                       "its \"id\" is already used by rule 1 — give it an id of its own, or delete its \"id\" line and one is made when the file loads")
    }

    func testEveryLaterCopyNamesTheFirstRuleThatUsedTheID() throws {
        let (rules, problems) = try RuleSetCodec.decode(file(
            #"{"name": "Other", \#(teams)}"#,
            #"{"id": "\#(id)", "name": "Original", \#(teams)}"#,
            #"{"id": "\#(id)", "name": "Copy", \#(slack)}"#,
            #"{"id": "\#(id)", "name": "Third", \#(slack)}"#))
        XCTAssertEqual(rules.map(\.name), ["Other", "Original"])
        XCTAssertEqual(problems.map(\.index), [2, 3])
        for problem in problems {
            XCTAssertTrue(problem.reason.contains("already used by rule 2"), problem.reason)
        }
    }

    func testRulesWithDifferentIDsAndRulesWithNoIDAreNotDuplicates() throws {
        let (rules, problems) = try RuleSetCodec.decode(file(
            #"{"id": "\#(id)", "name": "A", \#(teams)}"#,
            #"{"id": "\#(otherID)", "name": "B", \#(teams)}"#,
            #"{"name": "C", \#(teams)}"#,
            #"{"name": "D", \#(teams)}"#))
        XCTAssertEqual(problems, [])
        XCTAssertEqual(rules.map(\.name), ["A", "B", "C", "D"])
    }

    func testARuleRefusedForSomethingElseStillHoldsItsID() throws {
        // The editor keeps a rule the loader refuses, so its id still points
        // at it there, and a later rule with the id would still be mistaken
        // for it. The copy carries both reasons.
        let (rules, problems) = try RuleSetCodec.decode(file(
            #"{"id": "\#(id)", "name": "Loud", \#(teams), "alert": {"sound": "Glass", "gainDB": 100}}"#,
            #"{"id": "\#(id)", "name": "Copy", \#(slack)}"#))
        XCTAssertEqual(rules, [])
        guard problems.count == 2 else { return XCTFail("\(problems)") }
        XCTAssertEqual(problems.map(\.index), [0, 1])
        XCTAssertTrue(problems[0].reason.contains("gainDB 100"), problems[0].reason)
        XCTAssertFalse(problems[0].reason.contains("already used"), problems[0].reason)
        XCTAssertTrue(problems[1].reason.contains("already used by rule 1"), problems[1].reason)
    }

    func testACopyWithAnotherProblemIsToldBothInOneLine() throws {
        let (_, problems) = try RuleSetCodec.decode(file(
            #"{"id": "\#(id)", "name": "Original", \#(teams)}"#,
            #"{"id": "\#(id)", "name": " ", \#(slack)}"#))
        guard problems.count == 1 else { return XCTFail("\(problems)") }
        XCTAssertTrue(problems[0].reason.contains("it has no name"), problems[0].reason)
        XCTAssertTrue(problems[0].reason.contains("already used by rule 1"), problems[0].reason)
    }

    func testTheMenuCountsTheCopyAsRefused() {
        let (rules, status) = RuleStoreStatus.load(file(
            #"{"id": "\#(id)", "name": "Original", \#(teams)}"#,
            #"{"id": "\#(id)", "name": "Copy", \#(slack)}"#))
        XCTAssertEqual(rules.map(\.name), ["Original"])
        guard case .loadedWithProblems(let enabled, _, let rejected) = status else { return XCTFail("\(status)") }
        XCTAssertEqual(enabled, 1)
        XCTAssertEqual(rejected.map(\.index), [1])
    }

    // MARK: - The editor

    func testTheEditorDoesNotOfferAFileWithTwoRulesOfOneID() {
        let document = RulesDocument.load(file(
            #"{"id": "\#(id)", "name": "Original", \#(teams)}"#,
            #"{"id": "\#(id)", "name": "Copy", \#(slack)}"#))
        guard case .readOnly(.undecodable(let problems)) = document else { return XCTFail("\(document)") }
        XCTAssertEqual(problems.map(\.index), [1])
        XCTAssertTrue(problems.first?.reason.contains("already used by rule 1") ?? false, "\(problems)")
    }

    func testTheEditorAndTheLoaderRefuseTheSameRules() throws {
        let data = file(
            #"{"id": "\#(id)", "name": "Original", \#(teams)}"#,
            #"{"id": "\#(otherID)", "name": "B", \#(teams)}"#,
            #"{"id": "\#(otherID)", "name": "B copy", \#(slack)}"#,
            #"{"id": "\#(id)", "name": "Copy", \#(slack), "alrt": "silent"}"#)
        let loader = try RuleSetCodec.decode(data).problems
        guard case .readOnly(.undecodable(let editor)) = RulesDocument.load(data) else { return XCTFail() }
        // The editor lists the copy the loader refused for its id, and the
        // entry that is not a rule at all, which the loader refuses too.
        XCTAssertEqual(editor.map(\.index), [2, 3])
        XCTAssertEqual(loader.map(\.index), [2, 3])
        XCTAssertEqual(editor, loader)
    }

    func testAFileWhoseIDsAreAllDifferentIsStillEditable() {
        let document = RulesDocument.load(file(
            #"{"id": "\#(id)", "name": "A", \#(teams)}"#,
            #"{"id": "\#(otherID)", "name": "B", \#(slack)}"#))
        guard case .editable(let rules, _) = document else { return XCTFail("\(document)") }
        XCTAssertEqual(rules.map(\.name), ["A", "B"])
    }
}
