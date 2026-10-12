import XCTest
@testable import NotificationCore

/// The snooze opt-in in the rule format, and the rule's own decision about
/// whether a snooze may hold it (M5 plan, Task 4, Rulings 2, 3 and 12, O8).
/// Fixtures are invented text, never captured content (§10.1).
final class QuietWhenSnoozedTests: XCTestCase {
    private let daniel = "com.apple.voice.compact.en-GB.Daniel"
    private let teams = #""condition": {"field": "app", "op": "equals", "value": "Microsoft Teams"}"#

    private func file(version: Int = 5, _ rules: String) -> Data {
        Data("{\"version\": \(version), \"rules\": [\(rules)]}".utf8)
    }

    /// One rule that sounds and climbs, with `extra` written after its keys.
    private func ruleJSON(_ extra: String = "") -> String {
        #"{"name": "Pager", \#(teams), "alert": {"sound": "Glass"}\#(extra.isEmpty ? "" : ", " + extra)}"#
    }

    /// One rule that needs no version above 1: no alert, no ladder.
    private func plainJSON(_ extra: String = "") -> String {
        #"{"name": "Plain", \#(teams)\#(extra.isEmpty ? "" : ", " + extra)}"#
    }

    private func rule(alert: AlertAction? = .sound(name: "Glass", gainDB: 0), _ escalation: Escalation? = nil,
                      quiet: Bool = true, enabled: Bool = true) -> Rule {
        Rule(name: "Pager", condition: .field(.app, .equals, "Microsoft Teams"), isEnabled: enabled,
             alert: alert, escalation: escalation, quietWhenSnoozed: quiet)
    }

    private let glass = AlertAction.sound(name: "Glass", gainDB: 0)
    private let page = FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me"))

    private let snoozeGate = "quietWhenSnoozed needs \"version\": 5 — an older SignalLadder reading this file would reject the rule without saying why"

    // MARK: - Version 5

    func testTheFlagNeedsVersion5AndAnOlderFileReportsItByName() throws {
        for version in 1...4 {
            let (rules, problems) = try RuleSetCodec.decode(file(version: version, ruleJSON(#""quietWhenSnoozed": true"#)))
            XCTAssertEqual(rules, [], "version \(version)")
            // The alert beside it needs 2, and is not mentioned: one message,
            // the one that names the newest version.
            XCTAssertEqual(problems.map(\.reason), [snoozeGate], "version \(version)")
            XCTAssertEqual(problems.first?.name, "Pager", "version \(version)")
        }
        let (rules, problems) = try RuleSetCodec.decode(file(version: 5, ruleJSON(#""quietWhenSnoozed": true"#)))
        XCTAssertEqual(problems, [])
        XCTAssertEqual(rules.map(\.quietWhenSnoozed), [true])
    }

    func testARuleThatNeedsMoreThanOneVersionIsToldOnlyFive() throws {
        // Speech, a ladder and the flag in a version 1 file: one message, naming 5.
        let all = #"{"name": "All", \#(teams), "alert": {"speak": {"voice": "\#(daniel)"}}, "escalation": {"tier2": {}}, "quietWhenSnoozed": true}"#
        for version in 1...4 {
            let (_, problems) = try RuleSetCodec.decode(file(version: version, all))
            XCTAssertEqual(problems.map(\.reason), [snoozeGate], "version \(version)")
        }
    }

    func testAFileIsWrittenAtTheLowestVersionThatHoldsItsRules() {
        let speech = rule(alert: .speak(SpeechAction(voiceIdentifier: daniel)), quiet: false)
        let ladder = rule(Escalation(tier2: PanelAlert()), quiet: false)
        XCTAssertEqual(RuleSetCodec.version(for: [rule()]), 5, "a rule that has it")
        XCTAssertEqual(RuleSetCodec.version(for: [speech, ladder, rule()]), 5, "one rule among others")
        XCTAssertEqual(RuleSetCodec.version(for: [rule(alert: nil)]), 5, "a rule with no alert and no ladder")
        var refused = rule()
        refused.name = ""
        XCTAssertEqual(RuleSetCodec.version(for: [refused]), 5,
                       "a rule that is refused counts too, as an alert is counted whatever else is wrong with it")
        XCTAssertEqual(RuleSetCodec.version(for: [speech, ladder]), 4, "without it, as before")
        XCTAssertEqual(RuleSetCodec.version(for: [speech]), 3)
        XCTAssertEqual(RuleSetCodec.version(for: [rule(quiet: false)]), 2)
        XCTAssertEqual(RuleSetCodec.version(for: [rule(alert: nil, quiet: false)]), 1)
        XCTAssertEqual(RuleSetCodec.version(for: []), 1)
    }

    func testAVersion5FileIsUnderstoodAndAFileThatDeclaresMoreIsRefused() throws {
        XCTAssertEqual(RuleSetCodec.currentVersion, 5)
        XCTAssertNoThrow(try RuleSetCodec.decode(file(version: 5, plainJSON())))
        XCTAssertThrowsError(try RuleSetCodec.decode(file(version: 6, plainJSON()))) {
            XCTAssertEqual($0 as? RuleSetCodec.FileError, .unsupportedVersion(6))
        }
    }

    // MARK: - Written only when true

    func testTheFlagIsWrittenOnlyWhenTrueAndThenAtVersion5() throws {
        let on = String(decoding: try RuleSetCodec.encode([rule()]), as: UTF8.self)
        XCTAssertTrue(on.contains(#""quietWhenSnoozed" : true"#), on)
        XCTAssertTrue(on.contains(#""version" : 5"#), on)

        let off = String(decoding: try RuleSetCodec.encode([rule(quiet: false)]), as: UTF8.self)
        XCTAssertFalse(off.contains("quietWhenSnoozed"), off)
        XCTAssertTrue(off.contains(#""version" : 2"#), "a file that does not use it keeps the version it had: \(off)")
    }

    func testEveryShapeOfRuleRoundTripsWithTheFlagKept() throws {
        // Including the ones a snooze will never hold: the choice is the
        // user's and is kept, for the day the Shortcut is taken away.
        let rules = [
            rule(),
            rule(alert: nil),
            rule(alert: .silent),
            rule(alert: .speak(SpeechAction(voiceIdentifier: daniel))),
            rule(Escalation(tier2: PanelAlert(), tier3: RepeatAlert(action: glass))),
            rule(Escalation(tier4: page)),
            rule(enabled: false),
            rule(quiet: false),
        ]
        let (decoded, problems) = try RuleSetCodec.decode(try RuleSetCodec.encode(rules))
        XCTAssertEqual(problems, [])
        XCTAssertEqual(decoded.map(\.quietWhenSnoozed), rules.map(\.quietWhenSnoozed))
        XCTAssertEqual(decoded, rules)
    }

    // MARK: - Reading it

    func testFalseNullAndAnAbsentKeyNeedNothingAndReadAsTheDefault() throws {
        for extra in ["", #""quietWhenSnoozed": false"#, #""quietWhenSnoozed": null"#] {
            for version in [1, 4] {
                let (rules, problems) = try RuleSetCodec.decode(file(version: version, plainJSON(extra)))
                XCTAssertEqual(problems, [], "version \(version): \(extra)")
                XCTAssertEqual(rules.map(\.quietWhenSnoozed), [false], "version \(version): \(extra)")
            }
        }
    }

    func testAValueThatIsNotABooleanIsRefusedWithItsLocation() throws {
        for value in [#""yes""#, "1", "0", #""true""#, "[true]", "{}"] {
            let (rules, problems) = try RuleSetCodec.decode(file(version: 5, """
                \(plainJSON()), \(plainJSON(#""quietWhenSnoozed": \#(value)"#))
                """))
            XCTAssertEqual(rules.map(\.name), ["Plain"], "the other rule still loads: \(value)")
            XCTAssertEqual(problems.count, 1, value)
            XCTAssertEqual(problems.first?.index, 1, value)
            XCTAssertEqual(problems.first?.name, "Plain", value)
            let reason = problems.first?.reason ?? ""
            XCTAssertTrue(reason.hasSuffix(" at rules[1].quietWhenSnoozed"), "where it went wrong: \(reason)")
        }
    }

    func testAnUnknownKeyBesideItIsStillRefused() throws {
        let (rules, problems) = try RuleSetCodec.decode(file(version: 5, ruleJSON(#""quietWhenSnoozed": true, "quietWhenSnoozd": true"#)))
        XCTAssertEqual(rules, [])
        let reason = problems.first?.reason ?? ""
        XCTAssertTrue(reason.contains("unknown key \"quietWhenSnoozd\" in a rule"), reason)
        XCTAssertTrue(reason.contains("\"quietWhenSnoozed\""), "the key is among those it expects: \(reason)")
    }

    func testAMisspeltFlagAloneIsRefusedAndNotReadAsOff() throws {
        let (rules, problems) = try RuleSetCodec.decode(file(version: 5, ruleJSON(#""quietWhenSnoozd": true"#)))
        XCTAssertEqual(rules, [])
        XCTAssertTrue(problems.first?.reason.contains("unknown key \"quietWhenSnoozd\"") ?? false, "\(problems)")
    }

    func testTheLoaderKeepsAFlaggedRuleInEffectInAVersion5File() {
        let (rules, status) = RuleStoreStatus.load(file(version: 5, ruleJSON(#""quietWhenSnoozed": true"#)),
                                                   availableSounds: ["Glass"], unplayable: nil, availableVoices: nil)
        XCTAssertEqual(status, .loaded(enabled: 1, disabled: 0))
        XCTAssertEqual(rules.map(\.quietWhenSnoozed), [true])
    }

    // MARK: - Whether a snooze may hold the rule

    func testAFlaggedRuleThatSoundsAndRunsNoShortcutMayBeHeld() {
        XCTAssertTrue(rule().snoozeMayHold)
        XCTAssertTrue(rule(Escalation(tier2: PanelAlert())).snoozeMayHold, "a panel beside the sound")
        XCTAssertTrue(rule(Escalation(tier2: PanelAlert(), tier3: RepeatAlert(action: glass))).snoozeMayHold)
        XCTAssertTrue(rule(Escalation(tier4: FinalAlert(action: .alert(glass)))).snoozeMayHold,
                      "a last step that is a sound and not a Shortcut")
    }

    func testEachOfTheThreeConditionsIsNeededAndOneAloneIsNotEnough() {
        // flag, sounds, ends in a Shortcut → may hold. A literal table, so
        // that it is not the rule's own formula written out a second time.
        let table: [(flag: Bool, sounds: Bool, shortcut: Bool, mayHold: Bool)] = [
            (false, false, false, false),
            (false, false, true, false),
            (false, true, false, false),
            (false, true, true, false),
            (true, false, false, false),
            (true, false, true, false),
            (true, true, false, true),
            (true, true, true, false),
        ]
        for row in table {
            let made = rule(alert: row.sounds ? glass : .silent, row.shortcut ? Escalation(tier4: page) : nil, quiet: row.flag)
            XCTAssertEqual(made.snoozeMayHold, row.mayHold, "flag \(row.flag), sounds \(row.sounds), Shortcut \(row.shortcut)")
        }
    }

    func testARuleThatMakesNoSoundIsNeverHeldWhateverItsBoxSays() {
        XCTAssertFalse(rule(alert: nil).snoozeMayHold, "no alert")
        XCTAssertFalse(rule(alert: .silent).snoozeMayHold, "a silent alert")
        XCTAssertFalse(rule(alert: .silent, Escalation(tier2: PanelAlert())).snoozeMayHold, "a silent alert and a panel")
        XCTAssertFalse(rule(enabled: false).snoozeMayHold, "a rule that is off")
    }

    func testARuleThatSoundsOnALaterTierAloneIsStillOneThatSounds() {
        // Silent first, a repeat that plays: the rule is the one ruling 6's
        // own wording points people to, and it makes a noise.
        XCTAssertTrue(rule(alert: .silent, Escalation(tier3: RepeatAlert(action: glass))).snoozeMayHold)
        XCTAssertTrue(rule(alert: .silent, Escalation(tier4: FinalAlert(action: .alert(.speak(SpeechAction(voiceIdentifier: daniel)))))).snoozeMayHold)
    }

    func testARuleWhoseLastStepIsAShortcutIsNeverHeldWhateverItsBoxSays() {
        XCTAssertFalse(rule(Escalation(tier4: page)).snoozeMayHold, "the phone page still goes")
        XCTAssertFalse(rule(Escalation(tier2: PanelAlert(), tier3: RepeatAlert(action: glass), tier4: page)).snoozeMayHold,
                       "whatever the rule does before it")
        XCTAssertFalse(rule(Escalation(tier4: FinalAlert(action: .shortcut(name: "")))).snoozeMayHold,
                       "a Shortcut with no name is still a Shortcut, the safe direction")
    }

    func testTheFlagIsKeptWhileAShortcutIsThereAndCountsAgainWhenItIsTakenAway() throws {
        var made = rule(Escalation(tier2: PanelAlert(), tier3: RepeatAlert(action: glass), tier4: page))
        XCTAssertFalse(made.snoozeMayHold)
        XCTAssertTrue(made.quietWhenSnoozed, "ignored, not cleared")

        // Through the file, with the Shortcut still there.
        let (decoded, problems) = try RuleSetCodec.decode(try RuleSetCodec.encode([made]))
        XCTAssertEqual(problems, [])
        let read = try XCTUnwrap(decoded.first)
        XCTAssertTrue(read.quietWhenSnoozed)
        XCTAssertFalse(read.snoozeMayHold)

        // Taken away by the editor's own control, which changes the ladder alone.
        let edit = EscalationEditing.settingTier4(false, in: made.escalation, setAside: .init(), firstAlert: made.alert,
                                                  defaultSound: "Glass")
        XCTAssertNil(edit.escalation?.tier4)
        made.escalation = edit.escalation
        XCTAssertTrue(made.snoozeMayHold, "true again, the box having been kept")

        // And put back: false again, with the same box.
        let back = EscalationEditing.settingTier4(true, in: made.escalation, setAside: edit.setAside, firstAlert: made.alert,
                                                  defaultSound: "Glass")
        XCTAssertEqual(back.escalation?.tier4, page, "the Shortcut comes back whole")
        made.escalation = back.escalation
        XCTAssertFalse(made.snoozeMayHold)
        XCTAssertTrue(made.quietWhenSnoozed)
    }

    func testAShortcutRemovedWithTheWholeLadderLeavesTheBoxAsItWas() {
        var made = rule(Escalation(tier2: PanelAlert(), tier4: page))
        let edit = EscalationEditing.answeringOff(.remove, escalation: made.escalation, setAside: .init())
        XCTAssertNil(edit.escalation)
        made.escalation = edit.escalation
        XCTAssertTrue(made.quietWhenSnoozed)
        XCTAssertTrue(made.snoozeMayHold)
    }

    func testANewRuleStartsOptedOut() {
        XCTAssertFalse(Rule(name: "New rule", condition: .blank, isEnabled: false).quietWhenSnoozed,
                       "a rule starts opted out")
        let seeded = RuleSeed.rule(from: CapturedNotification(
            timestamp: Date(timeIntervalSince1970: 0), appNameGuess: "Microsoft Teams", title: "t", subtitle: "", body: "b",
            rawText: "", subrole: ""))
        XCTAssertFalse(seeded.quietWhenSnoozed, "a rule made from a notification starts opted out")
    }
}
