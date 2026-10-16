import XCTest
@testable import NotificationCore

/// What a reload leaves the app running on. A file the user can no longer use
/// — a typo that leaves it not JSON, a file that cannot be opened, one written
/// by a newer SignalLadder — must not take away rules that were working, so
/// the rules in effect stay in effect and the menu says the file is not.
final class RulesReloadTests: XCTestCase {
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

    /// The file above, with a comma too many: the edit most likely to break a file by hand.
    private let typo = """
    {"version": 1, "rules": [
      {"name": "Pager", "condition": {"field": "app", "op": "equals", "value": "PagerDuty"}},,
    ]}
    """

    private let newer = #"{"version": 99, "rules": []}"#

    // MARK: - A file that cannot be used keeps the rules in effect

    func testAFileThatIsNotJSONKeepsTheRulesThatWereInEffect() {
        let running = load(working).rules
        let fresh = load(typo)
        guard case .unreadable(let why) = fresh.status else { return XCTFail("the typo loads: \(fresh.status)") }
        let (rules, status) = RuleStoreStatus.reloaded(fresh, replacing: running)
        XCTAssertEqual(rules, running)
        XCTAssertEqual(status, .notReloaded(enabled: 2, disabled: 1, because: .unreadable(why)))
    }

    func testAFileWrittenByANewerSignalLadderKeepsTheRulesThatWereInEffect() {
        let running = load(working).rules
        let (rules, status) = RuleStoreStatus.reloaded(load(newer), replacing: running)
        XCTAssertEqual(rules, running)
        XCTAssertEqual(status, .notReloaded(enabled: 2, disabled: 1, because: .unsupportedVersion(99)))
    }

    /// The app hands over a file it cannot open as unreadable, with no rules, and it is
    /// decided the same way.
    func testAFileThatCannotBeOpenedKeepsThemToo() {
        let running = load(working).rules
        let (rules, status) = RuleStoreStatus.reloaded(([], .unreadable("permission denied")), replacing: running)
        XCTAssertEqual(rules, running)
        XCTAssertEqual(status, .notReloaded(enabled: 2, disabled: 1, because: .unreadable("permission denied")))
    }

    /// A second failure keeps the same rules, and the status gives the latest reason.
    func testTwoFailedReloadsInARowKeepTheSameRules() {
        let running = load(working).rules
        let first = RuleStoreStatus.reloaded(load(typo), replacing: running)
        let second = RuleStoreStatus.reloaded(load(newer), replacing: first.rules)
        XCTAssertEqual(second.rules, running)
        XCTAssertEqual(second.status, .notReloaded(enabled: 2, disabled: 1, because: .unsupportedVersion(99)))
    }

    /// Once the file is fixed, it is what runs.
    func testFixingTheFileReplacesTheKeptRules() {
        let kept = RuleStoreStatus.reloaded(load(typo), replacing: load(working).rules)
        let fixed = load(#"{"version": 1, "rules": [{"name": "Pager", "condition": {"field": "app", "op": "equals", "value": "PagerDuty"}}]}"#)
        let (rules, status) = RuleStoreStatus.reloaded(fixed, replacing: kept.rules)
        XCTAssertEqual(rules, fixed.rules)
        XCTAssertEqual(status, .loaded(enabled: 1, disabled: 0))
    }

    // MARK: - Anything else is what the file says

    /// A file that loads is what the user wrote, whatever was running before: fewer
    /// rules, a rule refused, every rule off, or none.
    func testAFileThatLoadsReplacesTheRulesInEffect() {
        let running = load(working).rules
        let files = [
            #"{"version": 1, "rules": [{"name": "Pager", "condition": {"field": "app", "op": "equals", "value": "PagerDuty"}}]}"#,
            #"{"version": 1, "rules": [{"name": "Pager", "condition": {"field": "app", "op": "equals", "value": "PagerDuty"}}, {"name": "Bad", "condition": {"or": []}}]}"#,
            #"{"version": 1, "rules": [{"name": "Pager", "enabled": false, "condition": {"field": "app", "op": "equals", "value": "PagerDuty"}}]}"#,
            #"{"version": 1, "rules": []}"#,
        ]
        for json in files {
            let fresh = load(json)
            let reloaded = RuleStoreStatus.reloaded(fresh, replacing: running)
            XCTAssertEqual(reloaded.rules, fresh.rules, json)
            XCTAssertEqual(reloaded.status, fresh.status, json)
        }
    }

    /// Removing the file is a way to have no rules, so a file that is not there is not
    /// a file that failed.
    func testARemovedFileStillMeansNoRules() {
        let (rules, status) = RuleStoreStatus.reloaded(load(nil), replacing: load(working).rules)
        XCTAssertEqual(rules, [])
        XCTAssertEqual(status, .noRulesFile)
    }

    /// With no rule on before, keeping them would change nothing, and "no rules are
    /// active" is the truth.
    func testWithNoRuleEnabledBeforeTheFailureIsReportedAsItWas() {
        let allOff = load(#"{"version": 1, "rules": [{"name": "Old", "enabled": false, "condition": {"field": "app", "op": "equals", "value": "Mail"}}]}"#).rules
        XCTAssertEqual(allOff.count, 1)
        for running in [[], allOff] {
            for fresh in [load(typo), load(newer)] {
                let reloaded = RuleStoreStatus.reloaded(fresh, replacing: running)
                XCTAssertEqual(reloaded.rules, [])
                XCTAssertEqual(reloaded.status, fresh.status)
            }
        }
    }

    // MARK: - What the menu says

    func testTheMenuSaysTheFileIsNotInEffectAndThatTheEarlierRulesAre() {
        let unreadable = RuleStoreStatus.notReloaded(enabled: 2, disabled: 1, because: .unreadable("line 3, column 4: …"))
        XCTAssertEqual(unreadable.summary, mark + "Rules file could not be read — keeping the earlier rules: 2 active, 1 off")
        XCTAssertEqual(unreadable.detail, ["line 3, column 4: …"], "the reason is shown, so the file can be fixed")
        XCTAssertTrue(unreadable.isProblem)

        let newer = RuleStoreStatus.notReloaded(enabled: 1, disabled: 0, because: .unsupportedVersion(9))
        XCTAssertEqual(newer.summary, mark + "Rules file needs a newer SignalLadder (format 9) — keeping the earlier rules: 1 active")
        XCTAssertEqual(newer.detail, [])
        XCTAssertTrue(newer.isProblem)
    }

    /// The app keeps the fingerprint of the file the rules in effect came from while it
    /// keeps them, and reads this to know when.
    func testOnlyAFileNotReloadedKeepsTheEarlierRules() {
        let statuses: [RuleStoreStatus] = [
            .noRulesFile, .loaded(enabled: 1, disabled: 0),
            .loadedWithProblems(enabled: 1, disabled: 0, rejected: [RuleSetCodec.Problem(index: 0, name: nil, reason: "x")]),
            .unreadable("x"), .unsupportedVersion(9),
        ]
        for status in statuses { XCTAssertFalse(status.keepsEarlierRules, "\(status)") }
        XCTAssertTrue(RuleStoreStatus.notReloaded(enabled: 1, disabled: 0, because: .unreadable("x")).keepsEarlierRules)
        XCTAssertTrue(RuleStoreStatus.notReloaded(enabled: 1, disabled: 0, because: .unsupportedVersion(9)).keepsEarlierRules)
    }
}
