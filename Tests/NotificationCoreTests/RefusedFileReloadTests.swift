import XCTest
@testable import NotificationCore

/// A reload of a file that loads but refuses every rule in it that is on (#102). A
/// misspelt key in the only rule is as much a typo as a misplaced comma, and to someone
/// on call it must not silence the rules that were working: they stay in effect, and
/// the menu and the on-call check say the file is not.
final class RefusedFileReloadTests: XCTestCase {
    private let mark = "\u{26A0}\u{FE0E} "

    private func load(_ json: String?) -> (rules: [Rule], status: RuleStoreStatus) {
        RuleStoreStatus.load(json.map { Data($0.utf8) }, availableSounds: nil, unplayable: nil, availableVoices: nil)
    }

    /// Two rules on and one off.
    private let working = """
    {"version": 1, "rules": [
      {"name": "Pager", "condition": {"field": "app", "op": "equals", "value": "PagerDuty"}},
      {"name": "Prod", "condition": {"field": "title", "op": "matches", "value": "#prod-*"}},
      {"name": "Old", "enabled": false, "condition": {"field": "app", "op": "equals", "value": "Mail"}}
    ]}
    """

    /// One rule, with `alert` misspelt: the file is JSON, and the rule is refused.
    private let misspelt = """
    {"version": 2, "rules": [
      {"name": "Pager", "alrt": {"sound": "Glass"}, "condition": {"field": "app", "op": "equals", "value": "PagerDuty"}}
    ]}
    """

    // MARK: - A file whose every rule that is on is refused keeps the rules in effect

    func testAFileWhoseOnlyRuleIsRefusedKeepsTheRulesThatWereInEffect() throws {
        let running = load(working).rules
        let fresh = load(misspelt)
        guard case .loadedWithProblems(0, 0, let rejected) = fresh.status, rejected.count == 1 else {
            return XCTFail("the misspelt rule is not refused: \(fresh.status)")
        }
        let (rules, status) = RuleStoreStatus.reloaded(fresh, replacing: running)
        XCTAssertEqual(rules, running)
        XCTAssertEqual(status, .notReloaded(enabled: 2, disabled: 1, because: .everyRuleRefused(rejected)))
    }

    /// A rule that is off is not one the user expects to page them, so a file whose
    /// only rules beside the refused one are off is refused as a whole too.
    func testAFileWithOnlyRulesOffBesideTheRefusedOneKeepsThemToo() {
        let running = load(working).rules
        let fresh = load("""
        {"version": 1, "rules": [
          {"name": "Old", "enabled": false, "condition": {"field": "app", "op": "equals", "value": "Mail"}},
          {"name": "Bad", "condition": {"or": []}}
        ]}
        """)
        let (rules, status) = RuleStoreStatus.reloaded(fresh, replacing: running)
        XCTAssertEqual(rules, running)
        guard case .notReloaded(2, 1, .everyRuleRefused(let rejected)) = status else { return XCTFail("\(status)") }
        XCTAssertEqual(rejected.map(\.index), [1])
    }

    /// One rule on is enough for the file to be what runs, as before: the refused rule
    /// is reported beside it.
    func testAFileWithOneRuleOnBesideARefusedOneStillReplacesThem() {
        let fresh = load("""
        {"version": 1, "rules": [
          {"name": "Pager", "condition": {"field": "app", "op": "equals", "value": "PagerDuty"}},
          {"name": "Bad", "condition": {"or": []}}
        ]}
        """)
        let reloaded = RuleStoreStatus.reloaded(fresh, replacing: load(working).rules)
        XCTAssertEqual(reloaded.rules, fresh.rules)
        XCTAssertEqual(reloaded.status, fresh.status)
        XCTAssertFalse(reloaded.status.keepsEarlierRules)
    }

    /// Once the rule is fixed, the file is what runs.
    func testFixingTheRefusedRuleThenReloadingLoadsTheFile() {
        let kept = RuleStoreStatus.reloaded(load(misspelt), replacing: load(working).rules)
        XCTAssertTrue(kept.status.keepsEarlierRules)
        let fixed = load(misspelt.replacingOccurrences(of: "\"alrt\"", with: "\"alert\""))
        let (rules, status) = RuleStoreStatus.reloaded(fixed, replacing: kept.rules)
        XCTAssertEqual(rules, fixed.rules)
        XCTAssertEqual(status, .loaded(enabled: 1, disabled: 0))
    }

    /// With no rule on before, there is nothing to keep, and the file is reported as it
    /// was read.
    func testWithNoRuleOnBeforeARefusedFileIsReportedAsItWas() {
        let allOff = load(#"{"version": 1, "rules": [{"name": "Old", "enabled": false, "condition": {"field": "app", "op": "equals", "value": "Mail"}}]}"#).rules
        let fresh = load(misspelt)
        for running in [[], allOff] {
            let reloaded = RuleStoreStatus.reloaded(fresh, replacing: running)
            XCTAssertEqual(reloaded.rules, [])
            XCTAssertEqual(reloaded.status, fresh.status)
        }
    }

    /// The first load at launch has nothing running, so a refused file still reads as one.
    func testTheFirstLoadOfARefusedFileIsNotChanged() {
        let fresh = load(misspelt)
        guard case .loadedWithProblems(0, 0, _) = fresh.status else { return XCTFail("\(fresh.status)") }
        XCTAssertEqual(fresh.rules, [])
    }

    // MARK: - What the menu and the on-call check say

    func testTheMenuSaysHowManyCouldNotBeUsedAndThatTheEarlierRulesAre() {
        let problem = RuleSetCodec.Problem(index: 0, name: "Pager", reason: "unknown key \"alrt\"")
        let status = RuleStoreStatus.notReloaded(enabled: 2, disabled: 1, because: .everyRuleRefused([problem]))
        XCTAssertEqual(status.summary, mark + "Rules: 1 could not be used — keeping the earlier rules: 2 active, 1 off")
        XCTAssertTrue(status.summary.hasPrefix(mark + RuleStoreStatus.summaryStem))
        XCTAssertEqual(status.detail, [problem.description], "each refused rule is listed, so the file can be fixed")
        XCTAssertTrue(status.isProblem)
        XCTAssertTrue(status.keepsEarlierRules)
    }

    func testTheOnCallCheckSaysTheFileIsNotInEffectAndTheEarlierRulesAre() throws {
        let problem = RuleSetCodec.Problem(index: 0, name: nil, reason: "x")
        let inputs = OnCallCheck.Inputs(health: .verified, unconfirmedMutedApps: [], outputSilent: false, alertVolume: 1,
                                        reach: RuleReach(enabled: 2, alertingAloud: 2, withShortcut: 0),
                                        ruleStatus: .notReloaded(enabled: 2, disabled: 1, because: .everyRuleRefused([problem])),
                                        ruleWarnings: [], startsAtLogin: nil, loginItem: nil, acknowledgeHotkeyRegistered: true)
        let found = OnCallCheck.findings(inputs)
        let finding = try XCTUnwrap(found.first { $0.kind == .rulesFileNotInEffect })
        XCTAssertEqual(finding.text,
                       "The rules file is not in effect: every rule in it that is on was refused, so the earlier rules still are")
        XCTAssertFalse(found.contains { $0.kind == .noRuleEnabled }, "the earlier rules are on")
    }
}
