import XCTest
@testable import NotificationCore

/// What the loader says about a rule it keeps: a Shortcut the Shortcuts app
/// does not list is a warning, and the rule stays in effect (M5 ruling 21).
/// Fixtures are invented text, never captured content (§10.1).
final class RuleWarningsTests: XCTestCase {
    private func rule(_ name: String = "Pager", enabled: Bool = true,
                      tier4: FinalAction? = .shortcut(name: "Page me")) -> Rule {
        Rule(name: name, condition: .field(.app, .equals, "Microsoft Teams"), isEnabled: enabled, alert: .silent,
             escalation: tier4.map { Escalation(tier4: FinalAlert(action: $0)) })
    }

    private func check(listed: Set<String>?) -> RuleSetCodec.SoundCheck {
        RuleSetCodec.SoundCheck(available: nil, unplayable: nil, voices: nil, shortcuts: listed.map { names in { names } })
    }

    private func notFound(_ name: String) -> String {
        "its final alert's Shortcut \"\(name)\" was not found in the Shortcuts app — the name must match one there exactly, including capitals, spaces and punctuation"
    }

    // MARK: - Which rules are warned about

    func testAnEnabledRuleWhoseShortcutIsNotListedIsWarnedAboutByNameAndShortcut() {
        let warnings = RuleWarnings.warnings(for: [rule()], sounds: check(listed: ["Log it"]))
        XCTAssertEqual(warnings, [RuleWarning(ruleName: "Pager", shortcutName: "Page me", sentence: notFound("Page me"))])
    }

    func testEachRuleThatNamesAMissingShortcutGetsItsOwnWarningInTheRulesOrder() {
        let rules = [rule("First", tier4: .shortcut(name: "Gone")),
                     rule("Fine", tier4: .shortcut(name: "Log it")),
                     rule("No ladder", tier4: nil),
                     rule("Sounds instead", tier4: .alert(.sound(name: "Hero", gainDB: 0))),
                     rule("Last", tier4: .shortcut(name: "Also gone"))]
        let warnings = RuleWarnings.warnings(for: rules, sounds: check(listed: ["Log it"]))
        XCTAssertEqual(warnings.map(\.ruleName), ["First", "Last"])
        XCTAssertEqual(warnings.map(\.shortcutName), ["Gone", "Also gone"])
        XCTAssertEqual(warnings.map(\.sentence), [notFound("Gone"), notFound("Also gone")])
    }

    func testARuleThatIsOffIsNotWarnedAbout() {
        // It is not in effect, so there is nothing for the menu to say about
        // it, and nothing for the editor to advise beside a rule that is off.
        let off = rule(enabled: false)
        XCTAssertEqual(RuleWarnings.warnings(for: [off], sounds: check(listed: [])), [])
        XCTAssertEqual(RuleWarnings.sentences(for: off, sounds: check(listed: [])), [])
    }

    func testAListedNameAndAListThatCannotBeReadAreNotWarnedAbout() {
        XCTAssertEqual(RuleWarnings.warnings(for: [rule()], sounds: check(listed: ["Page me"])), [])
        XCTAssertEqual(RuleWarnings.warnings(for: [rule()], sounds: check(listed: nil)), [])
        let unreadable = RuleSetCodec.SoundCheck(available: nil, unplayable: nil, voices: nil, shortcuts: { nil })
        XCTAssertEqual(RuleWarnings.warnings(for: [rule()], sounds: unreadable), [])
    }

    func testARuleThatIsOffNeverHasTheShortcutsListed() {
        // Listing runs a process, and a rule that is not in effect is no
        // reason to run one.
        var listings = 0
        let counting = RuleSetCodec.SoundCheck(available: nil, unplayable: nil, voices: nil,
                                               shortcuts: { listings += 1; return [] })
        XCTAssertEqual(RuleWarnings.warnings(for: [rule(enabled: false)], sounds: counting), [])
        XCTAssertEqual(listings, 0)
        XCTAssertEqual(RuleWarnings.warnings(for: [rule(enabled: false), rule(), rule("Second")], sounds: counting).count, 2)
        XCTAssertEqual(listings, 1)
    }

    // MARK: - What the editor and the menu say

    func testTheEditorGetsTheSentenceTheMenuUses() {
        let sounds = check(listed: ["Log it"])
        let pager = rule()
        XCTAssertEqual(RuleWarnings.sentences(for: pager, sounds: sounds),
                       RuleWarnings.warnings(for: [pager], sounds: sounds).map(\.sentence))
        XCTAssertEqual(RuleWarnings.sentences(for: rule(tier4: nil), sounds: sounds), [])
    }

    func testAMenuLineSaysWhichRuleAndWhatIsWrongWithIt() throws {
        let warning = try XCTUnwrap(RuleWarnings.warnings(for: [rule()], sounds: check(listed: [])).first)
        XCTAssertEqual(warning.detail, "Rule \"Pager\": \(notFound("Page me"))")
        // A blank name is left out, as a problem's is, and not shown as "".
        let blank = RuleWarning(ruleName: "  ", shortcutName: "Page me", sentence: "x")
        XCTAssertEqual(blank.detail, "Rule: x")
    }

    func testTheSummaryLineSaysOneAndManyAndNothingForNone() {
        XCTAssertEqual(RuleWarnings.summaryLine(count: 1),
                       "⚠︎ 1 Shortcut name was not found — the rule using it is still in effect")
        XCTAssertEqual(RuleWarnings.summaryLine(count: 2),
                       "⚠︎ 2 Shortcut names were not found — the rules using them are still in effect")
        XCTAssertEqual(RuleWarnings.summaryLine(count: 12),
                       "⚠︎ 12 Shortcut names were not found — the rules using them are still in effect")
        XCTAssertNil(RuleWarnings.summaryLine(count: 0))
        XCTAssertNil(RuleWarnings.summaryLine(count: -1))
    }

    // MARK: - The icon

    func testARuleWithAnUnlistedShortcutIsLoadedWholeAndOnlyTheWarningRaisesTheIcon() {
        let file = Data(#"{"version": 4, "rules": [{"name": "Pager", "condition": {"field": "app", "op": "equals", "value": "Microsoft Teams"}, "alert": "silent", "escalation": {"tier4": {"shortcut": "Page me"}}}]}"#.utf8)
        let (rules, status) = RuleStoreStatus.load(file, availableSounds: nil, unplayable: nil, availableVoices: nil)
        XCTAssertEqual(rules.count, 1, "the rule is in effect")
        XCTAssertEqual(status, .loaded(enabled: 1, disabled: 0))
        XCTAssertFalse(status.isProblem)

        let warnings = RuleWarnings.warnings(for: rules, sounds: check(listed: ["Log it"]))
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(StatusProblem.isProblem(healthAlarming: false, ruleStatusProblem: status.isProblem,
                                              warningCount: warnings.count, unresolvedAlertFailure: false,
                                              unresolvedShortcutFailure: false),
                      "the warning is what raises the icon")
        XCTAssertFalse(StatusProblem.isProblem(healthAlarming: false, ruleStatusProblem: status.isProblem,
                                               warningCount: RuleWarnings.warnings(for: rules, sounds: check(listed: ["Page me"])).count,
                                               unresolvedAlertFailure: false, unresolvedShortcutFailure: false))
    }

    func testTheIconSaysProblemForEachOfItsFiveFactsAlone() {
        func problem(health: Bool = false, rules: Bool = false, warnings: Int = 0, alert: Bool = false,
                     shortcut: Bool = false) -> Bool {
            StatusProblem.isProblem(healthAlarming: health, ruleStatusProblem: rules, warningCount: warnings,
                                    unresolvedAlertFailure: alert, unresolvedShortcutFailure: shortcut)
        }
        XCTAssertFalse(problem(), "none of them")
        XCTAssertTrue(problem(health: true), "health alarming")
        XCTAssertTrue(problem(rules: true), "a rule-status problem")
        XCTAssertTrue(problem(warnings: 1), "a Shortcut warning")
        XCTAssertTrue(problem(warnings: 3), "more than one")
        XCTAssertTrue(problem(alert: true), "an unresolved alert failure")
        XCTAssertTrue(problem(shortcut: true), "an unresolved Shortcut failure")
        XCTAssertFalse(problem(warnings: 0), "a count of zero is not a problem")
        XCTAssertTrue(problem(health: true, rules: true, warnings: 2, alert: true, shortcut: true), "all of them")
    }
}

/// A rule whose Shortcut is not listed still pages: the first alert, every
/// repeat and the last step all run, and a last step that fails is held (M5
/// ruling 21, M4 ruling 6).
@MainActor
final class RuleWarningsWiringTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func testARuleWithAnUnlistedShortcutStillFiresEveryTierAndAFailedLastStepIsHeld() throws {
        let file = Data("""
            {"version": 4, "rules": [{"name": "Pager",
              "condition": {"field": "app", "op": "equals", "value": "Microsoft Teams"},
              "alert": {"sound": "Glass"},
              "escalation": {"tier3": {"action": {"sound": "Hero"}, "intervalSeconds": 30,
                                       "maxRepeats": 2, "maxDurationSeconds": null},
                             "tier4": {"afterSeconds": 100, "shortcut": "Page the on-call phone"}}}]}
            """.utf8)
        let names: Set<String> = ["Glass", "Hero"]
        let (rules, status) = RuleStoreStatus.load(file, availableSounds: names, unplayable: nil, availableVoices: nil)
        let check = RuleSetCodec.SoundCheck(available: names, unplayable: nil, voices: nil, shortcuts: { ["Log it"] })
        XCTAssertEqual(rules.count, 1, "the rule is loaded whole")
        XCTAssertFalse(status.isProblem)
        XCTAssertEqual(RuleWarnings.warnings(for: rules, sounds: check).map(\.shortcutName), ["Page the on-call phone"],
                       "and warned about")

        let clock = ManualScheduler(start: t0)
        var played: [String] = []
        var shortcutsRun: [String] = []
        let reason = "the Shortcut \"Page the on-call phone\" is not installed"
        var pipeline: CapturePipeline!
        var ladder: EscalationCoordinator!
        ladder = EscalationCoordinator(
            scheduler: clock,
            playSound: { name, _ in played.append(name); return .played(sound: name, gainDB: 0, outputSilent: false) },
            speak: { _, _ in .couldNotSpeak("unused") },
            playAndSpeak: { _, _, _, _ in .couldNotSpeak("unused") },
            runShortcut: { name, _, report in
                shortcutsRun.append(name)
                report(.shortcutFailed(name: name, reason: reason))
            },
            updatePanel: { _ in },
            recordSummary: { entry, summary in pipeline.recordEscalation(entryID: entry, summary, at: clock.now()) },
            retired: { entry in pipeline.escalationRetired(entryID: entry) },
            beginPowerAssertion: {}, endPowerAssertion: {}, silenceIfIdle: {})
        pipeline = CapturePipeline(
            ownAppName: "SignalLadder",
            isSelfTest: { _, _ in false },
            playSound: { name, _ in played.append(name); return .played(sound: name, gainDB: 0, outputSilent: false) },
            speak: { _, _ in .couldNotSpeak("unused") },
            playAndSpeak: { _, _, _, _ in .couldNotSpeak("unused") },
            beginEscalation: { rule, notification, entry in
                ladder.begin(rule: rule, notification: notification, entryID: entry)
            })
        pipeline.setRules(rules)

        pipeline.process(RawCapture(timestamp: t0,
                                    rawText: "Microsoft Teams, Alex Example mentioned you, Placeholder body text",
                                    subrole: "AXNotificationCenterBanner"),
                         textChildren: ["Alex Example mentioned you", "Placeholder body text"])
        XCTAssertEqual(played, ["Glass"], "the first alert")
        clock.advance(by: 60)
        XCTAssertEqual(played, ["Glass", "Hero", "Hero"], "and each repeat")
        XCTAssertEqual(shortcutsRun, [])
        clock.advance(by: 40)
        XCTAssertEqual(shortcutsRun, ["Page the on-call phone"], "and the last step tries the name when it fires")

        XCTAssertEqual(pipeline.unresolvedShortcutFailure,
                       CapturePipeline.ShortcutFailure(ruleName: "Pager", shortcutName: "Page the on-call phone",
                                                       at: t0 + 100, reason: reason))
        XCTAssertEqual(AlertMenuText.escalationLines(listed: [], shortcutFailure: pipeline.unresolvedShortcutFailure,
                                                     time: { _ in "09:00" }),
                       ["⚠︎ Pager at 09:00: \(reason)"], "held as a Shortcut that did not run")
    }
}
