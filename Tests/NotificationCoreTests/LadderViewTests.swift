import XCTest
@testable import NotificationCore

/// What the ladder editor's views ask of the core: the numbers a user types,
/// the segment a click chooses, where the notes go, and what the Test Shortcut
/// button decides and says. The views are in the app target, which has no
/// tests, and decide nothing of their own: each of these is a function they
/// call, so each is here.
final class LadderViewTests: XCTestCase {
    typealias Field = EscalationEditing.NumberField
    typealias Preset = EscalationEditing.Preset
    typealias SetAside = EscalationEditing.SetAside

    private let hero = AlertAction.sound(name: "Hero", gainDB: 0)
    private let spoken = AlertAction.speak(SpeechAction(voiceIdentifier: "com.apple.voice.compact.en-GB.Daniel"))
    private let page = FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me"))

    /// Every number set, each different, so a field that reads or writes
    /// another's cannot pass.
    private var full: Escalation {
        Escalation(tier2: PanelAlert(delaySeconds: 10),
                   tier3: RepeatAlert(action: hero, intervalSeconds: 30, maxRepeats: 20, maxDurationSeconds: 600),
                   tier4: page)
    }

    // MARK: - Typed numbers: what a field shows

    func testEachFieldShowsTheNumberTheLadderHoldsAsTypedText() {
        let shown = Field.allCases.map { EscalationEditing.fieldText($0, in: full) }
        XCTAssertEqual(shown, ["10", "30", "20", "600", "120"])
        XCTAssertEqual(Field.allCases, [.tier2Delay, .tier3Interval, .tier3MaxRepeats, .tier3MaxDuration, .tier4Delay])
    }

    func testAFieldShowsAnyNumberTheTypeCanHoldSoAHandWrittenProblemCanBeFixed() {
        let odd = Escalation(tier2: PanelAlert(delaySeconds: 0),
                             tier3: RepeatAlert(action: hero, intervalSeconds: -5, maxRepeats: 0, maxDurationSeconds: 2.5),
                             tier4: FinalAlert(afterSeconds: 1e20, action: .shortcut(name: "Page me")))
        let shown = Field.allCases.map { EscalationEditing.fieldText($0, in: odd) }
        XCTAssertEqual(shown, ["0", "-5", "0", "2.5", EditorText.fieldText(seconds: 1e20)])
        XCTAssertFalse(shown.contains(nil))
    }

    func testAFieldHasNoTextWhereTheLadderHoldsNoNumber() {
        for field in Field.allCases {
            XCTAssertNil(EscalationEditing.fieldText(field, in: nil), "\(field) over Off")
            XCTAssertNil(EscalationEditing.fieldText(field, in: Escalation()), "\(field) over an empty ladder")
        }
        var noLimits = full
        noLimits.tier3?.maxRepeats = nil
        noLimits.tier3?.maxDurationSeconds = nil
        XCTAssertNil(EscalationEditing.fieldText(.tier3MaxRepeats, in: noLimits), "No limit holds no number")
        XCTAssertNil(EscalationEditing.fieldText(.tier3MaxDuration, in: noLimits))
        XCTAssertEqual(EscalationEditing.fieldText(.tier3Interval, in: noLimits), "30")
        var noFinal = full
        noFinal.tier4 = nil
        XCTAssertNil(EscalationEditing.fieldText(.tier4Delay, in: noFinal))
        XCTAssertEqual(EscalationEditing.fieldText(.tier2Delay, in: noFinal), "10")
        var noRepeat = full
        noRepeat.tier3 = nil
        XCTAssertNil(EscalationEditing.fieldText(.tier3Interval, in: noRepeat))
        XCTAssertNil(EscalationEditing.fieldText(.tier3MaxRepeats, in: noRepeat))
    }

    func testOnlyTimesHaveSecondsAndACountHasNone() {
        XCTAssertEqual(Field.allCases.map { EscalationEditing.seconds(of: $0, in: full) }, [10, 30, nil, 600, 120])
    }

    // MARK: - Typed numbers: what typing writes

    func testTypingAnEditWritesThatNumberAndNoOther() {
        var expected: [Field: Escalation] = [:]
        var delay = full; delay.tier2?.delaySeconds = 7; expected[.tier2Delay] = delay
        var interval = full; interval.tier3?.intervalSeconds = 7; expected[.tier3Interval] = interval
        var repeats = full; repeats.tier3?.maxRepeats = 7; expected[.tier3MaxRepeats] = repeats
        var duration = full; duration.tier3?.maxDurationSeconds = 7; expected[.tier3MaxDuration] = duration
        var final = full; final.tier4?.afterSeconds = 7; expected[.tier4Delay] = final
        for field in Field.allCases {
            XCTAssertEqual(EscalationEditing.typing("7", into: field, of: full), expected[field], "\(field)")
        }
    }

    func testTypingWritesAsTheControlsWriteAtLeastOneSecondOrOneRepeat() {
        for typed in ["0", "-3", "0.5"] {
            XCTAssertEqual(EscalationEditing.typing(typed, into: .tier3Interval, of: full)?.tier3?.intervalSeconds, 1, typed)
            XCTAssertEqual(EscalationEditing.typing(typed, into: .tier2Delay, of: full)?.tier2?.delaySeconds, 1, typed)
            XCTAssertEqual(EscalationEditing.typing(typed, into: .tier4Delay, of: full)?.tier4?.afterSeconds, 1, typed)
            XCTAssertEqual(EscalationEditing.typing(typed, into: .tier3MaxDuration, of: full)?.tier3?.maxDurationSeconds, 1, typed)
        }
        for typed in ["0", "-2"] {
            XCTAssertEqual(EscalationEditing.typing(typed, into: .tier3MaxRepeats, of: full)?.tier3?.maxRepeats, 1, typed)
        }
    }

    func testTypingTheTextAFieldAlreadyShowsRewritesNothingEvenWhenItIsOutOfRange() {
        let odd = Escalation(tier2: PanelAlert(delaySeconds: 0),
                             tier3: RepeatAlert(action: hero, intervalSeconds: -5, maxRepeats: 0, maxDurationSeconds: 0.5),
                             tier4: FinalAlert(afterSeconds: 1e20, action: .shortcut(name: "Page me")))
        for field in Field.allCases {
            let shown = EscalationEditing.fieldText(field, in: odd)!
            XCTAssertEqual(EscalationEditing.typing(shown, into: field, of: odd), odd, "\(field): \(shown)")
            XCTAssertEqual(EscalationEditing.typing(" \(shown) ", into: field, of: odd), odd, "\(field), padded")
        }
    }

    func testTypingTextThatIsNotYetANumberWritesNothing() {
        for typed in ["", " ", "-", ".", "abc", "1e999", "nan", "inf", "12 s"] {
            for field in Field.allCases {
                XCTAssertEqual(EscalationEditing.typing(typed, into: field, of: full), full, "\(field): “\(typed)”")
            }
        }
        // A count is a whole number: half of a number is not one.
        XCTAssertEqual(EscalationEditing.typing("3.5", into: .tier3MaxRepeats, of: full), full)
    }

    func testTypingIntoANumberTheLadderDoesNotHoldWritesNothing() {
        for field in Field.allCases {
            XCTAssertNil(EscalationEditing.typing("7", into: field, of: nil), "\(field) over Off")
        }
        var noRepeat = full
        noRepeat.tier3 = nil
        for field in [Field.tier3Interval, .tier3MaxRepeats, .tier3MaxDuration] {
            XCTAssertEqual(EscalationEditing.typing("7", into: field, of: noRepeat), noRepeat, "\(field) with no repeat")
        }
    }

    // MARK: - Typed numbers: telling an edit from a change made elsewhere

    func testTextStandsForTheNumberItWasTypedToMakeAsTypedOrClamped() {
        XCTAssertTrue(EscalationEditing.textStandsFor("30", field: .tier3Interval, in: full))
        XCTAssertTrue(EscalationEditing.textStandsFor(" 30 ", field: .tier3Interval, in: full))
        XCTAssertTrue(EscalationEditing.textStandsFor("30.0", field: .tier3Interval, in: full))
        XCTAssertTrue(EscalationEditing.textStandsFor("20", field: .tier3MaxRepeats, in: full))
        // Typed as 0, held as 1: still the user's edit, and not for the field
        // to snap back to 1 while they are typing "05".
        var clamped = full
        clamped.tier3?.intervalSeconds = 1
        clamped.tier3?.maxRepeats = 1
        XCTAssertTrue(EscalationEditing.textStandsFor("0", field: .tier3Interval, in: clamped))
        XCTAssertTrue(EscalationEditing.textStandsFor("-4", field: .tier3Interval, in: clamped))
        XCTAssertTrue(EscalationEditing.textStandsFor("0", field: .tier3MaxRepeats, in: clamped))
    }

    func testTextDoesNotStandForAnotherNumberOrForNothing() {
        XCTAssertFalse(EscalationEditing.textStandsFor("31", field: .tier3Interval, in: full))
        XCTAssertFalse(EscalationEditing.textStandsFor("1", field: .tier3Interval, in: full), "1 is not 30, clamped or not")
        XCTAssertFalse(EscalationEditing.textStandsFor("21", field: .tier3MaxRepeats, in: full))
        for text in ["", "-", "abc", "1e999"] {
            XCTAssertFalse(EscalationEditing.textStandsFor(text, field: .tier3Interval, in: full), text)
        }
        XCTAssertFalse(EscalationEditing.textStandsFor("2.5", field: .tier3MaxRepeats, in: full), "not a whole number")
        for field in Field.allCases {
            XCTAssertFalse(EscalationEditing.textStandsFor("10", field: field, in: nil), "\(field): Off holds none")
        }
    }

    func testAFieldKeepsWhatIsTypedWhileTheLadderFollowsItAndShowsAChangeMadeElsewhere() {
        // Typing "3", "30", "300" into an interval of 30: each keystroke is
        // written, and each leaves the text standing for the ladder, so the
        // field is never rewritten under the user's fingers.
        var ladder: Escalation? = full
        for typed in ["3", "30", "300", "3000"] {
            ladder = EscalationEditing.typing(typed, into: .tier3Interval, of: ladder)
            XCTAssertEqual(ladder?.tier3?.intervalSeconds, Double(typed), typed)
            XCTAssertTrue(EscalationEditing.textStandsFor(typed, field: .tier3Interval, in: ladder), typed)
        }
        // Typing "0" is written as 1, and the "0" stays.
        ladder = EscalationEditing.typing("0", into: .tier3Interval, of: ladder)
        XCTAssertEqual(ladder?.tier3?.intervalSeconds, 1)
        XCTAssertTrue(EscalationEditing.textStandsFor("0", field: .tier3Interval, in: ladder))
        // Then a preset is chosen: the ladder says 15, and the field's text no
        // longer stands for it, so it shows 15.
        let wake = Preset.wakeMe.ladder(repeating: hero)
        XCTAssertFalse(EscalationEditing.textStandsFor("0", field: .tier3Interval, in: wake))
        XCTAssertEqual(EscalationEditing.fieldText(.tier3Interval, in: wake), "15")
    }

    // MARK: - The segment a click chooses

    func testChoosingASegmentIsChoosingAPresetOrCustom() {
        var aside = SetAside()
        aside.custom = Escalation(tier3: RepeatAlert(action: hero))
        let onCall = Preset.onCall.ladder(repeating: hero)
        for preset in Preset.allCases {
            XCTAssertEqual(
                EscalationEditing.choose(.preset(preset), escalation: onCall, setAside: aside, firstAlert: hero,
                                         defaultSound: "Glass"),
                EscalationEditing.choose(preset, escalation: onCall, setAside: aside, firstAlert: hero,
                                         defaultSound: "Glass"), "\(preset)")
        }
        let custom = EscalationEditing.choose(.custom, escalation: onCall, setAside: aside, firstAlert: hero,
                                              defaultSound: "Glass")
        XCTAssertEqual(custom, EscalationEditing.chooseCustom(escalation: onCall, setAside: aside))
        XCTAssertNotEqual(custom, .unchanged, "there is a custom ladder to bring back")
        XCTAssertEqual(
            EscalationEditing.choose(.custom, escalation: onCall, setAside: SetAside(), firstAlert: hero,
                                     defaultSound: "Glass"), .unchanged, "and none to bring back")
    }

    func testCustomiseStartsOpenOnlyWhileTheLadderIsCustom() {
        XCTAssertFalse(EscalationEditing.customiseStartsOpen(for: nil))
        for preset in Preset.allCases {
            XCTAssertFalse(EscalationEditing.customiseStartsOpen(for: preset.ladder(repeating: hero)), "\(preset)")
        }
        var withShortcut = Preset.onCall.ladder(repeating: hero)!
        withShortcut.tier4 = page
        XCTAssertFalse(EscalationEditing.customiseStartsOpen(for: withShortcut), "a Shortcut beside a preset is still the preset")
        XCTAssertTrue(EscalationEditing.customiseStartsOpen(for: Escalation(tier3: RepeatAlert(action: hero))))
        XCTAssertTrue(EscalationEditing.customiseStartsOpen(for: Escalation(tier4: page)))
        XCTAssertTrue(EscalationEditing.customiseStartsOpen(for: Escalation()), "a hand-written {} needs its fix in view")
        XCTAssertTrue(EscalationEditing.customiseStartsOpen(for: Escalation(tier2: PanelAlert(delaySeconds: 11))))
    }

    func testEachLimitKnowsWhetherItIsNoLimit() {
        XCTAssertFalse(EscalationEditing.hasNoLimit(on: .repeats, in: full))
        XCTAssertFalse(EscalationEditing.hasNoLimit(on: .duration, in: full))
        var oneLimit = full
        oneLimit.tier3?.maxRepeats = nil
        XCTAssertTrue(EscalationEditing.hasNoLimit(on: .repeats, in: oneLimit))
        XCTAssertFalse(EscalationEditing.hasNoLimit(on: .duration, in: oneLimit))
        oneLimit.tier3?.maxDurationSeconds = nil
        XCTAssertTrue(EscalationEditing.hasNoLimit(on: .duration, in: oneLimit))
        for limit in [EscalationEditing.Limit.repeats, .duration] {
            XCTAssertFalse(EscalationEditing.hasNoLimit(on: limit, in: nil), "no repeat has no limit to be without")
            XCTAssertFalse(EscalationEditing.hasNoLimit(on: limit, in: Escalation(tier2: PanelAlert())))
        }
    }

    func testTier4OffersAnAlertAndAShortcutInThatOrder() {
        XCTAssertEqual(EscalationEditing.FinalKind.allCases, [.alert, .shortcut])
        XCTAssertEqual(EscalationEditing.FinalKind.allCases.map(EditorText.finalKindName), ["Alert", "Shortcut"])
    }

    // MARK: - A later alert's editor

    func testALaterAlertsEditorWritingNoAlertChangesNothing() {
        XCTAssertEqual(EscalationEditing.settingRepeatAction(nil, in: full), full)
        XCTAssertEqual(EscalationEditing.settingFinalAlert(nil, in: Escalation(tier4: FinalAlert(action: .alert(hero)))),
                       Escalation(tier4: FinalAlert(action: .alert(hero))))
        XCTAssertEqual(EscalationEditing.settingRepeatAction(spoken, in: full)?.tier3?.action, spoken)
        XCTAssertEqual(EscalationEditing.settingFinalAlert(spoken, in: Escalation(tier4: FinalAlert(action: .alert(hero))))?
            .tier4?.action, .alert(spoken))
    }

    // MARK: - Where the muted-output note goes

    func testTheNoteIsWithTheFirstAlertWheneverTheFirstAlertMakesASound() {
        for first in [hero, spoken, .soundAndSpeak(soundName: "Hero", soundGainDB: 0, speech: SpeechAction(voiceIdentifier: "v"))] {
            XCTAssertEqual(EscalationEditing.mutedOutputNoteSite(firstAlert: first, escalation: nil), .firstAlert)
            XCTAssertEqual(EscalationEditing.mutedOutputNoteSite(firstAlert: first, escalation: full), .firstAlert,
                           "a repeat that sounds as well does not say it twice")
        }
    }

    func testTheNoteIsWithTheLadderWhenOnlyALaterStepMakesASound() {
        XCTAssertEqual(EscalationEditing.mutedOutputNoteSite(firstAlert: .silent, escalation: full), .ladder)
        XCTAssertEqual(EscalationEditing.mutedOutputNoteSite(firstAlert: nil, escalation: full), .ladder)
        let finalOnly = Escalation(tier4: FinalAlert(action: .alert(spoken)))
        XCTAssertEqual(EscalationEditing.mutedOutputNoteSite(firstAlert: .silent, escalation: finalOnly), .ladder)
    }

    func testThereIsNoNoteWhereNothingWouldBeHeard() {
        XCTAssertNil(EscalationEditing.mutedOutputNoteSite(firstAlert: nil, escalation: nil))
        XCTAssertNil(EscalationEditing.mutedOutputNoteSite(firstAlert: .silent, escalation: nil))
        // A panel is silent, and a Shortcut makes no sound on the Mac.
        XCTAssertNil(EscalationEditing.mutedOutputNoteSite(firstAlert: .silent, escalation: Preset.gentle.ladder(repeating: hero)))
        XCTAssertNil(EscalationEditing.mutedOutputNoteSite(firstAlert: .silent, escalation: Escalation(tier4: page)))
        XCTAssertNil(EscalationEditing.mutedOutputNoteSite(firstAlert: nil, escalation: Escalation()))
        XCTAssertNil(EscalationEditing.mutedOutputNoteSite(
            firstAlert: .silent, escalation: Escalation(tier3: RepeatAlert(action: .silent))), "a silent repeat")
    }

    // MARK: - The Test Shortcut button

    func testTheButtonIsOfferedOnlyForANameAndWhileNoTestIsPending() {
        XCTAssertTrue(ShortcutTest.canRun(name: "Page me", pending: false))
        XCTAssertFalse(ShortcutTest.canRun(name: "Page me", pending: true), "a double click must not page twice")
        for blank in ["", " ", "  \t", "\n"] {
            XCTAssertFalse(ShortcutTest.canRun(name: blank, pending: false), "“\(blank)”")
        }
        XCTAssertFalse(ShortcutTest.canRun(name: "", pending: true))
    }

    func testAResultIsShownOnlyBesideTheExactNameItWasFor() {
        let report = ShortcutTest.Report(name: "Page me", outcome: .started)
        XCTAssertEqual(ShortcutTest.shown(report, forField: "Page me"), report)
        for other in ["page me", "Page Me", "Page me ", " Page me", "Page  me", "Page", "Page me 2", ""] {
            XCTAssertNil(ShortcutTest.shown(report, forField: other), "“\(other)”")
        }
        XCTAssertNil(ShortcutTest.shown(nil, forField: "Page me"))
        let failed = ShortcutTest.Report(name: "Page me", outcome: .failed("the Shortcut \"Page me\" is not installed"))
        XCTAssertEqual(ShortcutTest.shown(failed, forField: "Page me"), failed)
        XCTAssertNil(ShortcutTest.shown(failed, forField: "Page Me"))
    }

    func testAStartedResultSaysStartedAndAFailedOneSaysTheRunnersOwnReasonAsItIs() {
        let started = ShortcutTest.Report(name: "Page me", outcome: .started)
        XCTAssertEqual(started.text, "Started “Page me”")
        XCTAssertTrue(started.started)
        let reason = "the Shortcut \"Page me\" stopped with exit code 1"
        let failed = ShortcutTest.Report(name: "Page me", outcome: .failed(reason))
        XCTAssertEqual(failed.text, reason)
        XCTAssertFalse(failed.started, "a failure is not a start, so it clears nothing")
        XCTAssertNotEqual(started, failed)
        XCTAssertNotEqual(ShortcutTest.Report(name: "Page me", outcome: .started),
                          ShortcutTest.Report(name: "Page you", outcome: .started))
    }

    // MARK: - The words around the controls

    func testEachTiersSwitchIsSummarisedAndAScreenReaderSaysTheSameWords() {
        XCTAssertEqual([2, 3, 4].map(EditorText.tierSummary),
                       ["Show a panel until acknowledged", "Repeat the alert", "A final step"])
        let labels: [Int: EditorText.Control] = [2: .tier2Switch, 3: .tier3Switch, 4: .tier4Switch]
        for (tier, control) in labels {
            let summary = EditorText.tierSummary(tier)
            let lowered = summary.prefix(1).lowercased() + summary.dropFirst()
            XCTAssertEqual(EditorText.label(control), "\(EditorText.tierHeading(tier)), \(lowered)", "tier \(tier)")
        }
        XCTAssertEqual(EditorText.tierSummary(1), "", "the first alert has its own editor")
    }

    func testEachTypedNumberIsLedAndFollowedByTheWordsTheSentenceUses() {
        XCTAssertEqual(Field.allCases.map(EditorText.fieldLead), ["After", "Every", "At most", "Stop after", "After"])
        XCTAssertEqual(Field.allCases.map(EditorText.fieldUnit), ["seconds", "seconds", "times", "seconds", "seconds"])
        let sentence = EditorText.ladderSentence(full)
        for word in ["After 10 seconds", "Every 30 seconds", "at most 20 times", "After 2 minutes"] {
            XCTAssertTrue(sentence.contains(word), "“\(word)” is the field's own wording: \(sentence)")
        }
    }

    func testEachTypedNumberHasADistinctLabelForAScreenReaderThatSaysItsTier() {
        let labels = Field.allCases.map(EditorText.fieldLabel)
        XCTAssertEqual(Set(labels).count, 5)
        XCTAssertEqual(labels, [EditorText.label(.tier2Delay), EditorText.label(.tier3Interval),
                                EditorText.label(.tier3MaxRepeats), EditorText.label(.tier3MaxDuration),
                                EditorText.label(.tier4Delay)])
        for label in labels { XCTAssertTrue(label.hasPrefix("Tier "), label) }
    }

    func testATimeFromAMinuteUpIsCaptionedInMinutesAndNothingElseIs() {
        XCTAssertEqual(EditorText.fieldCaption(.tier3MaxDuration, in: full), "10 minutes")
        XCTAssertEqual(EditorText.fieldCaption(.tier4Delay, in: full), "2 minutes")
        XCTAssertNil(EditorText.fieldCaption(.tier2Delay, in: full), "10 seconds says itself")
        XCTAssertNil(EditorText.fieldCaption(.tier3Interval, in: full))
        XCTAssertNil(EditorText.fieldCaption(.tier3MaxRepeats, in: full), "a count has no minutes")
        var manyRepeats = full
        manyRepeats.tier3?.maxRepeats = 120
        XCTAssertNil(EditorText.fieldCaption(.tier3MaxRepeats, in: manyRepeats), "120 times is not 2 minutes")
        var noLimit = full
        noLimit.tier3?.maxDurationSeconds = nil
        XCTAssertNil(EditorText.fieldCaption(.tier3MaxDuration, in: noLimit))
        XCTAssertNil(EditorText.fieldCaption(.tier4Delay, in: nil))
    }

    func testTheShortcutNameFieldSaysWhereTheNameIsReadFrom() {
        XCTAssertEqual(EditorText.shortcutNamePrompt, "Name, exactly as in the Shortcuts app")
    }

    // MARK: - The advice for a name not found, beside what else the pane says

    /// The two lines the pane can put near each other for a rule, each from
    /// the function the views call: what the dry-run says of whether the rule
    /// is in effect, and the advice beside the name field. The advice is shown
    /// while the rule's warnings are not empty, whatever else is true of it.
    private func paneLines(for rule: Rule, saved: [Rule], sounds: RuleSetCodec.SoundCheck)
        -> (inEffect: String?, advice: String?) {
        let problems = RulesDocument.problems(in: rule, sounds: sounds, fileVersion: nil)
        let unsaved = DryRun.isUnsaved(rule.id, draft: [rule], saved: saved, fileVersion: nil, sounds: sounds)
        return (EditorText.notInEffect(hasProblems: !problems.isEmpty, isOff: !rule.isEnabled, isUnsaved: unsaved),
                RuleWarnings.sentences(for: rule, sounds: sounds).isEmpty ? nil : EditorText.shortcutNotFoundAdvice)
    }

    func testTheAdviceForANameNotFoundIsShownBesideAnUnsavedRuleAndOneThatIsRefusedAndClaimsNoEffectInEither() throws {
        let sounds = RuleSetCodec.SoundCheck(available: nil, unplayable: nil, voices: nil, shortcuts: { ["Log it"] })
        func rule(alert: AlertAction?) -> Rule {
            Rule(name: "Pager", condition: .field(.app, .equals, "Microsoft Teams"), alert: alert,
                 escalation: Escalation(tier4: FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me"))))
        }
        let advice = EditorText.shortcutNotFoundAdvice

        // A new rule, never saved: the pane says it is not in effect until it is.
        let draft = rule(alert: .silent)
        let unsaved = paneLines(for: draft, saved: [], sounds: sounds)
        XCTAssertEqual(unsaved.inEffect, "Not in effect until you save.")
        XCTAssertEqual(unsaved.advice, advice, "the name is still the thing to check before you save")

        // The same rule once it is saved: nothing else to say, and the advice stays.
        let saved = paneLines(for: draft, saved: [draft], sounds: sounds)
        XCTAssertNil(saved.inEffect)
        XCTAssertEqual(saved.advice, advice)

        // An escalation with no first alert, which the loader refuses whatever
        // the Shortcut is called: the pane says it has problems, and the advice
        // is there as well, since the name is wrong whatever else is.
        let refused = rule(alert: nil)
        XCTAssertFalse(RulesDocument.problems(in: refused, sounds: sounds, fileVersion: nil).isEmpty)
        let broken = paneLines(for: refused, saved: [refused], sounds: sounds)
        XCTAssertEqual(broken.inEffect, "Not in effect: this rule has problems, and will not run until they are fixed.")
        XCTAssertEqual(broken.advice, advice)

        // Wherever the pane says the rule is not in effect, the advice does not
        // say it is: not that it stays, and not that it is in effect.
        for lines in [unsaved, broken] {
            let said = try XCTUnwrap(lines.inEffect)
            XCTAssertTrue(said.hasPrefix("Not in effect"), said)
            let advised = try XCTUnwrap(lines.advice)
            XCTAssertFalse(advised.lowercased().contains("in effect"), advised)
        }
    }

    func testNothingTheEditorSaysAroundItsControlsHoldsAWordOfANotification() {
        let notifications = [AlertEditing.sampleNotification, AlertEditing.shortcutTestNotification]
        let fields = notifications.flatMap { [$0.appNameGuess, $0.title, $0.subtitle, $0.body] }.filter { !$0.isEmpty }
        var said: [String] = [EditorText.shortcutNamePrompt]
        said += [2, 3, 4].map(EditorText.tierSummary)
        said += Field.allCases.flatMap { [EditorText.fieldLead($0), EditorText.fieldUnit($0), EditorText.fieldLabel($0)] }
        said += Field.allCases.compactMap { EditorText.fieldCaption($0, in: full) }
        said.append(ShortcutTest.Report(name: "Page me", outcome: .started).text)
        said.append(ShortcutTest.Report(name: "Page me", outcome: .failed("the Shortcut \"Page me\" is not installed")).text)
        for line in said {
            for field in fields {
                XCTAssertFalse(line.contains(field), "“\(line)” holds “\(field)”")
            }
        }
    }
}
