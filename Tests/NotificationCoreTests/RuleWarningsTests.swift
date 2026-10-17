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

    func testTheSummarySentenceIsTheLineWithoutItsMark() {
        for count in [1, 2, 12] {
            XCTAssertEqual(RuleWarnings.summaryLine(count: count), "⚠︎ " + RuleWarnings.summarySentence(count: count)!, "\(count)")
        }
        XCTAssertNil(RuleWarnings.summarySentence(count: 0))
        XCTAssertNil(RuleWarnings.summarySentence(count: -1))
    }

    // MARK: - A sound or a voice that cannot be played

    /// A check that finds three sounds and one voice, and calls the sounds in
    /// `unplayable` unplayable for the reason given.
    private func sounds(unplayable: [String: String] = [:]) -> RuleSetCodec.SoundCheck {
        RuleSetCodec.SoundCheck(available: ["Glass", "Hero", "Sosumi"], unplayable: { unplayable[$0] },
                                voices: ["voice.here"], shortcuts: { ["Page me"] })
    }

    private func soundRule(_ name: String = "Pager", enabled: Bool = true, alert: AlertAction,
                           escalation: Escalation? = nil) -> Rule {
        Rule(name: name, condition: .field(.app, .equals, "Microsoft Teams"), isEnabled: enabled, alert: alert,
             escalation: escalation)
    }

    private let soundNotFound = "sound \"Klaxon\" was not found — available: Glass, Hero, Sosumi"
    private let voiceNotInstalled = "voice \"voice.gone\" is not installed — choose another in the rule editor, or add it in System Settings › Accessibility › Read & Speak (Spoken Content before macOS 26)"

    func testARuleWhoseSoundIsMissingIsLoadedWholeAndWarnedAboutAndNotRefused() {
        // It used to be refused, and the rules below it took its matches: a
        // silent catch-all beneath it swallowed the page (finding of 2026-10-16).
        let file = Data(#"{"version": 2, "rules": [{"name": "Pager", "condition": {"field": "app", "op": "equals", "value": "Microsoft Teams"}, "alert": {"sound": "Klaxon"}}]}"#.utf8)
        let (rules, status) = RuleStoreStatus.load(file, availableSounds: ["Glass", "Hero", "Sosumi"], unplayable: nil,
                                                   availableVoices: nil)
        XCTAssertEqual(rules.map(\.name), ["Pager"], "the rule is in effect")
        XCTAssertEqual(status, .loaded(enabled: 1, disabled: 0))
        XCTAssertEqual(RuleWarnings.warnings(for: rules, sounds: sounds()),
                       [RuleWarning(ruleName: "Pager", kind: .cannotPlay, sentence: soundNotFound)])
    }

    /// A blank name or voice is refused when the rules load, and is not warned
    /// about as well. Blank counts line breaks there, so it does here: a name of
    /// "\n" was both refused and warned about as a sound that was not found.
    func testABlankNameOrVoiceIsRefusedAndNotWarnedAboutToo() {
        for blank in ["  ", "\n", " \t\n"] {
            let speech = SpeechAction(voiceIdentifier: blank)
            for alert: AlertAction in [.sound(name: blank, gainDB: 0), .speak(speech),
                                       .soundAndSpeak(soundName: blank, soundGainDB: 0, speech: speech)] {
                let rule = soundRule(alert: alert)
                XCTAssertFalse(RuleSetCodec.problems(in: rule).isEmpty, "\(alert) is refused")
                XCTAssertEqual(RuleWarnings.warnings(for: [rule], sounds: sounds()), [], "\(alert)")
            }
        }
    }

    func testAVoiceThatIsNotInstalledAndASoundThatCannotBePlayedAreWarnedAboutTheSameWay() {
        XCTAssertEqual(RuleWarnings.warnings(for: [soundRule(alert: .speak(SpeechAction(voiceIdentifier: "voice.gone")))],
                                             sounds: sounds()).map(\.sentence),
                       [voiceNotInstalled])
        XCTAssertEqual(RuleWarnings.warnings(for: [soundRule(alert: .sound(name: "Hero", gainDB: 0))],
                                             sounds: sounds(unplayable: ["Hero": "sound \"Hero\" is silent"])).map(\.sentence),
                       ["sound \"Hero\" is silent"])
        XCTAssertEqual(RulesDocument.problems(in: soundRule(alert: .sound(name: "Klaxon", gainDB: 0)), sounds: sounds(),
                                              fileVersion: nil), [],
                       "and the editor calls the rule clean, as the loader does")
    }

    func testEveryAlertOfARuleIsCheckedAndARuleHasOneSoundWarningInTierOrder() {
        let ladder = Escalation(tier3: RepeatAlert(action: .speak(SpeechAction(voiceIdentifier: "voice.gone")),
                                                   intervalSeconds: 30, maxRepeats: 2, maxDurationSeconds: nil),
                                tier4: FinalAlert(action: .alert(.sound(name: "Klaxon", gainDB: 0))))
        let warnings = RuleWarnings.warnings(for: [soundRule(alert: .sound(name: "Hero", gainDB: 0), escalation: ladder)],
                                             sounds: sounds(unplayable: ["Hero": "sound \"Hero\" is silent"]))
        XCTAssertEqual(warnings, [RuleWarning(
            ruleName: "Pager", kind: .cannotPlay,
            sentence: "sound \"Hero\" is silent; its repeat's \(voiceNotInstalled); its final alert's \(soundNotFound)")])
    }

    func testARuleWithBothKindsOfFaultHasTheSoundWarningThenTheShortcutWarning() {
        let ladder = Escalation(tier4: FinalAlert(action: .shortcut(name: "Gone")))
        let warnings = RuleWarnings.warnings(for: [soundRule(alert: .sound(name: "Klaxon", gainDB: 0), escalation: ladder)],
                                             sounds: sounds())
        XCTAssertEqual(warnings.map(\.kind), [.cannotPlay, .shortcutNotFound("Gone")])
        XCTAssertEqual(warnings.map(\.shortcutName), [nil, "Gone"])
    }

    func testARuleThatIsOffOrACheckThatCannotSayIsNotWarnedAboutItsSound() {
        XCTAssertEqual(RuleWarnings.warnings(for: [soundRule(enabled: false, alert: .sound(name: "Klaxon", gainDB: 0))],
                                             sounds: sounds()), [])
        XCTAssertEqual(RuleWarnings.warnings(for: [soundRule(alert: .sound(name: "Klaxon", gainDB: 0))], sounds: .none), [])
        XCTAssertEqual(RuleWarnings.warnings(for: [soundRule(alert: .silent)], sounds: sounds()), [])
    }

    func testTheEditorAdvisesAboutTheSoundBesideTheRuleAndAboutTheShortcutBesideItsField() {
        let ladder = Escalation(tier4: FinalAlert(action: .shortcut(name: "Gone")))
        let both = soundRule(alert: .sound(name: "Klaxon", gainDB: 0), escalation: ladder)
        XCTAssertEqual(RuleWarnings.alertSentences(for: both, sounds: sounds()), [soundNotFound])
        XCTAssertEqual(RuleWarnings.sentences(for: both, sounds: sounds()), [notFound("Gone")],
                       "the advice beside the Shortcut's name is about the Shortcut alone")
        XCTAssertEqual(RuleWarnings.alertSentences(for: soundRule(alert: .sound(name: "Glass", gainDB: 0)), sounds: sounds()), [])
    }

    func testTheSoundSummarySaysOneAndManyAndNothingForNone() {
        XCTAssertEqual(RuleWarnings.alertSummaryLine(count: 1),
                       "⚠︎ 1 rule has a sound or voice that cannot be played — it is still in effect")
        XCTAssertEqual(RuleWarnings.alertSummaryLine(count: 3),
                       "⚠︎ 3 rules have a sound or voice that cannot be played — they are still in effect")
        XCTAssertNil(RuleWarnings.alertSummaryLine(count: 0))
        for count in [1, 3] {
            XCTAssertEqual(RuleWarnings.alertSummaryLine(count: count), "⚠︎ " + RuleWarnings.alertSummarySentence(count: count)!)
        }
        XCTAssertNil(RuleWarnings.alertSummarySentence(count: 0))
    }

    func testTheMenuGivesEachKindItsOwnSummaryWithItsRulesBeneathIt() {
        let ladder = Escalation(tier4: FinalAlert(action: .shortcut(name: "Gone")))
        let warnings = RuleWarnings.warnings(for: [soundRule("A", alert: .sound(name: "Klaxon", gainDB: 0)),
                                                   soundRule("B", alert: .silent, escalation: ladder)],
                                             sounds: sounds())
        XCTAssertEqual(RuleWarnings.menuLines(for: warnings), [
            RuleWarnings.MenuLine(text: RuleWarnings.summaryLine(count: 1)!, indented: false),
            RuleWarnings.MenuLine(text: "Rule \"B\": \(notFound("Gone"))", indented: true),
            RuleWarnings.MenuLine(text: RuleWarnings.alertSummaryLine(count: 1)!, indented: false),
            RuleWarnings.MenuLine(text: "Rule \"A\": \(soundNotFound)", indented: true),
        ])
        XCTAssertEqual(RuleWarnings.menuLines(for: []), [])
    }

    // MARK: - The icon

    func testAWarningOfEitherKindRaisesTheIcon() {
        func isProblem(warningCount: Int) -> Bool {
            StatusGlyph.isProblem(StatusGlyph.Facts(
                health: .verified, healthAlarmState: HealthAlarmPlan.State(), now: Date(timeIntervalSince1970: 1_790_000_000),
                ruleStatusProblem: false, ruleWarningCount: warningCount, unresolvedAlertFailure: false,
                unresolvedShortcutFailure: false, outputSilent: false, anEnabledRuleSounds: true, alertVolume: 1,
                escalationLive: false, snoozeEndsAt: nil, heldSummary: HeldSummary(), onCall: false, selfTestsRunning: true))
        }
        let warnings = RuleWarnings.warnings(for: [soundRule(alert: .sound(name: "Klaxon", gainDB: 0))], sounds: sounds())
        XCTAssertEqual(warnings.map(\.kind), [.cannotPlay])
        XCTAssertTrue(isProblem(warningCount: warnings.count))
        XCTAssertFalse(isProblem(warningCount: 0))
    }

    func testARuleWithAnUnlistedShortcutIsLoadedWholeAndOnlyTheWarningRaisesTheIcon() {
        let file = Data(#"{"version": 4, "rules": [{"name": "Pager", "condition": {"field": "app", "op": "equals", "value": "Microsoft Teams"}, "alert": "silent", "escalation": {"tier4": {"shortcut": "Page me"}}}]}"#.utf8)
        let (rules, status) = RuleStoreStatus.load(file, availableSounds: nil, unplayable: nil, availableVoices: nil)
        XCTAssertEqual(rules.count, 1, "the rule is in effect")
        XCTAssertEqual(status, .loaded(enabled: 1, disabled: 0))
        XCTAssertFalse(status.isProblem)

        func isProblem(warningCount: Int) -> Bool {
            StatusGlyph.isProblem(StatusGlyph.Facts(
                health: .verified, healthAlarmState: HealthAlarmPlan.State(), now: Date(timeIntervalSince1970: 1_790_000_000),
                ruleStatusProblem: status.isProblem, ruleWarningCount: warningCount, unresolvedAlertFailure: false,
                unresolvedShortcutFailure: false, outputSilent: false, anEnabledRuleSounds: true, alertVolume: 1,
                escalationLive: false, snoozeEndsAt: nil, heldSummary: HeldSummary(), onCall: false, selfTestsRunning: true))
        }
        let warnings = RuleWarnings.warnings(for: rules, sounds: check(listed: ["Log it"]))
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(isProblem(warningCount: warnings.count), "the warning is what raises the icon")
        XCTAssertFalse(isProblem(warningCount: RuleWarnings.warnings(for: rules, sounds: check(listed: ["Page me"])).count))
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
        pipeline = CapturePipeline.forTest(
            playSound: { name, _ in played.append(name); return .played(sound: name, gainDB: 0, outputSilent: false) },
            beginEscalation: { rule, notification, entry, tier1 in
                ladder.begin(rule: rule, notification: notification, entryID: entry, tier1Outcome: tier1)
            },
            joinEscalation: { rule, notification in ladder.join(rule: rule, notification: notification) })
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
