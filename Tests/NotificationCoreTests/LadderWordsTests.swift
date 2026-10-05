import XCTest
@testable import NotificationCore

/// What the ladder editor says: the presets' names and meanings, the sentence
/// beneath the choice for every shape of ladder, and the words around the
/// controls. Every sentence names what the app knows, so every one is here.
final class LadderWordsTests: XCTestCase {
    typealias Preset = EscalationEditing.Preset

    private let hero = AlertAction.sound(name: "Hero", gainDB: 0)
    private let glass = AlertAction.sound(name: "Glass", gainDB: 0)
    private let speech = SpeechAction(voiceIdentifier: "com.apple.voice.compact.en-GB.Daniel")
    private let page = FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me"))

    private func sentence(_ escalation: Escalation?) -> String { EditorText.ladderSentence(escalation) }

    // MARK: - Presets

    func testThePresetsAreNamedAsThePickerShowsThem() {
        XCTAssertEqual(Preset.allCases.map(EditorText.presetName), ["Off", "Gentle", "On call", "Wake me"])
        XCTAssertEqual(EditorText.customName, "Custom")
        XCTAssertEqual(EditorText.segmentName(.preset(.onCall)), "On call")
        XCTAssertEqual(EditorText.segmentName(.custom), "Custom")
        XCTAssertEqual(EditorText.ifIDontAcknowledge, "If I don't acknowledge")
        XCTAssertEqual(EditorText.customise, "Customise…")
    }

    func testEachPresetSaysWhatItDoesFromItsOwnNumbers() {
        XCTAssertEqual(EditorText.presetMeaning(.off), "Nothing happens after the first alert.")
        XCTAssertEqual(EditorText.presetMeaning(.gentle), "After 10 seconds a panel stays on screen until you acknowledge it.")
        XCTAssertEqual(EditorText.presetMeaning(.onCall),
                       "After 10 seconds a panel stays on screen until you acknowledge it. "
                       + "Every 30 seconds, the first alert repeats, at most 20 times or 10 minutes, whichever comes first.")
        XCTAssertEqual(EditorText.presetMeaning(.wakeMe),
                       "After 5 seconds a panel stays on screen until you acknowledge it. "
                       + "Every 15 seconds, the first alert repeats, with no limit on repeats or time.")
        XCTAssertEqual(Set(Preset.allCases.map(EditorText.presetMeaning)).count, 4, "no two read alike")
    }

    func testTheShortcutNudgeIsOnlyUnderOnCallAndWakeMeWhileThereIsNoFinalStep() {
        let nudge = "A Shortcut can page your phone if nobody answers. Add one as the final step, under “Customise…”."
        for preset in [Preset.onCall, .wakeMe] {
            let ladder = preset.ladder(repeating: hero)
            XCTAssertEqual(EditorText.shortcutNudge(shown: .preset(preset), escalation: ladder), nudge, "\(preset)")
            var withFinal = ladder!
            withFinal.tier4 = page
            XCTAssertNil(EditorText.shortcutNudge(shown: .preset(preset), escalation: withFinal), "\(preset) with a final step")
            withFinal.tier4 = FinalAlert(action: .alert(glass))
            XCTAssertNil(EditorText.shortcutNudge(shown: .preset(preset), escalation: withFinal), "an alert is a final step too")
        }
        XCTAssertNil(EditorText.shortcutNudge(shown: .preset(.off), escalation: nil))
        XCTAssertNil(EditorText.shortcutNudge(shown: .preset(.gentle), escalation: Preset.gentle.ladder(repeating: hero)))
        XCTAssertNil(EditorText.shortcutNudge(shown: .custom, escalation: Escalation(tier2: PanelAlert(delaySeconds: 3))))
        XCTAssertTrue(nudge.contains(EditorText.customise), "it names where the control is")
    }

    /// The preset called On call and the switch called On-call mode are two
    /// things with the owner's own two names, so the preset says which it is
    /// (M5 plan, Ruling 9). Nothing is said beside the others.
    func testTheNoteAboutTheTwoOnCallsIsBesideTheOnCallPresetAlone() {
        XCTAssertEqual(EditorText.onCallPresetNote(shown: .preset(.onCall)),
                       "On call applies whenever this rule matches, whether or not On-call mode is on.")
        for shown in [EscalationEditing.Shown.preset(.off), .preset(.gentle), .preset(.wakeMe), .custom] {
            XCTAssertNil(EditorText.onCallPresetNote(shown: shown), "\(shown)")
        }
        XCTAssertEqual(EditorText.onCallPresetNote(shown: .preset(.onCall)), EditorText.onCallPresetSentence)
    }

    func testTheNoteNamesBothTheLadderAndTheModeAndSaysTheyAreSeparate() {
        let note = EditorText.onCallPresetSentence
        XCTAssertTrue(note.contains("whenever this rule matches"))
        XCTAssertTrue(note.contains("whether or not On-call mode is on"))
    }

    func testTheHintToChooseWhatPlaysFirstIsSaidOnlyWhileThereIsNoFirstAlert() {
        XCTAssertEqual(EditorText.presetHint(forAlert: nil), "Choose what plays first (Silent is fine) to use a preset.")
        XCTAssertNil(EditorText.presetHint(forAlert: .silent))
        XCTAssertNil(EditorText.presetHint(forAlert: hero))
    }

    // MARK: - The ladder's sentence

    func testTheSentenceForEachPresetNamesWhatRepeats() {
        XCTAssertEqual(sentence(nil), "Nothing happens after the first alert.")
        XCTAssertEqual(sentence(Preset.gentle.ladder(repeating: hero)),
                       "After 10 seconds a panel stays on screen until you acknowledge it.")
        XCTAssertEqual(sentence(Preset.onCall.ladder(repeating: hero)),
                       "After 10 seconds a panel stays on screen until you acknowledge it. "
                       + "Every 30 seconds, Hero plays again, at most 20 times or 10 minutes, whichever comes first.")
        XCTAssertEqual(sentence(Preset.wakeMe.ladder(repeating: hero)),
                       "After 5 seconds a panel stays on screen until you acknowledge it. "
                       + "Every 15 seconds, Hero plays again, with no limit on repeats or time. "
                       + "It keeps sounding, and keeps the Mac awake, until you acknowledge it.")
    }

    func testTheSentenceForEachShapeOfRepeat() {
        func repeating(_ action: AlertAction = AlertAction.sound(name: "Hero", gainDB: 0), interval: Double = 30,
                       repeats: Int? = 20, duration: Double? = 600) -> String {
            sentence(Escalation(tier3: RepeatAlert(action: action, intervalSeconds: interval, maxRepeats: repeats,
                                                   maxDurationSeconds: duration)))
        }
        XCTAssertEqual(repeating(.speak(speech), interval: 45, repeats: 3, duration: nil),
                       "Every 45 seconds, the line is spoken again, at most 3 times.")
        XCTAssertEqual(repeating(interval: 90, repeats: nil, duration: 600),
                       "Every 1 minute 30 seconds, Hero plays again, for at most 10 minutes.")
        XCTAssertEqual(repeating(repeats: 1, duration: nil), "Every 30 seconds, Hero plays again, at most once.")
        XCTAssertEqual(repeating(repeats: 1, duration: 60),
                       "Every 30 seconds, Hero plays again, at most once or 1 minute, whichever comes first.")
        XCTAssertEqual(repeating(.soundAndSpeak(soundName: "Hero", soundGainDB: 0, speech: speech), repeats: nil, duration: nil),
                       "Every 30 seconds, Hero plays and the line is spoken again, with no limit on repeats or time. "
                       + "It keeps sounding, and keeps the Mac awake, until you acknowledge it.")
        XCTAssertEqual(repeating(.silent, repeats: 2, duration: nil),
                       "Every 30 seconds, nothing sounds again, as it is silent, at most 2 times.")
    }

    func testARepeatWithNeitherLimitIsFollowedByWhatItCostsAndNoOtherRepeatIs() {
        let cost = "It keeps sounding, and keeps the Mac awake, until you acknowledge it."
        func repeating(_ action: AlertAction = AlertAction.sound(name: "Hero", gainDB: 0), repeats: Int?, time: Double?) -> Escalation {
            Escalation(tier3: RepeatAlert(action: action, intervalSeconds: 15, maxRepeats: repeats, maxDurationSeconds: time))
        }
        // Wake me, and a Custom ladder whose limits are both off: said.
        XCTAssertTrue(sentence(Preset.wakeMe.ladder(repeating: hero)).hasSuffix(" " + cost), "Wake me")
        XCTAssertTrue(sentence(repeating(repeats: nil, time: nil)).hasSuffix(" " + cost), "a custom ladder with no limits")
        XCTAssertTrue(sentence(repeating(.speak(speech), repeats: nil, time: nil)).hasSuffix(" " + cost), "whatever it plays")
        // Either limit ends the repeats of itself, so there is no cost to say.
        for escalation in [repeating(repeats: 3, time: nil), repeating(repeats: nil, time: 600), repeating(repeats: 3, time: 600),
                           Preset.onCall.ladder(repeating: hero)!] {
            XCTAssertFalse(sentence(escalation).contains("awake"), sentence(escalation))
            XCTAssertFalse(sentence(escalation).contains("keeps sounding"), sentence(escalation))
        }
        // No repeat at all, whatever else the ladder holds.
        for escalation in [Preset.gentle.ladder(repeating: hero)!, Escalation(tier2: PanelAlert(delaySeconds: 3)),
                           Escalation(tier4: page), Escalation()] as [Escalation] {
            XCTAssertFalse(sentence(escalation).contains("awake"), sentence(escalation))
        }
        XCTAssertFalse(sentence(nil).contains("awake"))
    }

    func testTheCostFollowsTheRepeatAndTheFinalStepKeepsItsOwnSentence() {
        var ladder = Preset.wakeMe.ladder(repeating: hero)!
        ladder.tier4 = page
        XCTAssertEqual(sentence(ladder),
                       "After 5 seconds a panel stays on screen until you acknowledge it. "
                       + "Every 15 seconds, Hero plays again, with no limit on repeats or time. "
                       + "It keeps sounding, and keeps the Mac awake, until you acknowledge it. "
                       + "After 2 minutes it starts the Shortcut “Page me”.",
                       "the cost is said of the repeat, before the final step, so \"It\" is the repeat and not the Shortcut")
    }

    func testASilentRepeatWithNeitherLimitCostsTheMacAwakeAndDoesNotSaySoundingForNothing() {
        let silent = Escalation(tier3: RepeatAlert(action: .silent, intervalSeconds: 30, maxRepeats: nil, maxDurationSeconds: nil))
        XCTAssertEqual(sentence(silent),
                       "Every 30 seconds, nothing sounds again, as it is silent, with no limit on repeats or time. "
                       + "It keeps the Mac awake until you acknowledge it.")
        XCTAssertFalse(sentence(silent).contains("keeps sounding"))
    }

    func testTheCostIsInTheSentenceBeneathThePickerAndInTheOffSentenceThatBringsTheLadderBack() {
        let wake = Preset.wakeMe.ladder(repeating: hero)
        XCTAssertEqual(EditorText.underChoice(escalation: wake, setAside: .init(), confirmingShortcut: nil), sentence(wake))
        XCTAssertTrue(EditorText.underChoice(escalation: wake, setAside: .init(), confirmingShortcut: nil).contains("keeps the Mac awake"))
        var aside = EscalationEditing.SetAside()
        aside.custom = wake
        XCTAssertTrue(EditorText.offSentence(setAside: aside).hasSuffix(sentence(wake)),
                      "what Custom would bring back is described as the ladder is")
    }

    func testALadderWhoseTimeLimitEndsBeforeTheFirstRepeatSaysItNeverRepeats() {
        // On call with the interval raised to 15 minutes and the 10 minute
        // limit kept: the coordinator arms no repeat at all, so the sentence
        // cannot say Hero plays again.
        let onCallSlowed = Escalation(tier2: PanelAlert(delaySeconds: 10),
                                      tier3: RepeatAlert(action: hero, intervalSeconds: 900, maxRepeats: 20, maxDurationSeconds: 600))
        XCTAssertEqual(sentence(onCallSlowed),
                       "After 10 seconds a panel stays on screen until you acknowledge it. "
                       + "It never repeats: the first repeat would come after 15 minutes, and the time limit ends at 10 minutes.")
        XCTAssertFalse(sentence(onCallSlowed).contains("plays again"))

        func never(_ action: AlertAction, interval: Double, repeats: Int? = 20, duration: Double?) -> String {
            sentence(Escalation(tier3: RepeatAlert(action: action, intervalSeconds: interval, maxRepeats: repeats,
                                                   maxDurationSeconds: duration)))
        }
        let expected = "It never repeats: the first repeat would come after 30 seconds, and the time limit ends at 10 seconds."
        for action in [hero, .speak(speech), .soundAndSpeak(soundName: "Hero", soundGainDB: 0, speech: speech), .silent] {
            XCTAssertEqual(never(action, interval: 30, duration: 10), expected, "whatever the repeat would have played: \(action)")
        }
        XCTAssertEqual(never(hero, interval: 30, repeats: nil, duration: 29.5),
                       "It never repeats: the first repeat would come after 30 seconds, and the time limit ends at 29.5 seconds.",
                       "with no limit on repeats it is the time limit that decides")
        XCTAssertEqual(never(hero, interval: 61, duration: 60),
                       "It never repeats: the first repeat would come after 1 minute 1 second, and the time limit ends at 1 minute.")
    }

    func testALimitEqualToTheIntervalAllowsExactlyOneRepeatAndTheSentenceStillSaysItRepeats() {
        func with(interval: Double, duration: Double) -> String {
            sentence(Escalation(tier3: RepeatAlert(action: hero, intervalSeconds: interval, maxRepeats: 20,
                                                   maxDurationSeconds: duration)))
        }
        XCTAssertEqual(with(interval: 600, duration: 600),
                       "Every 10 minutes, Hero plays again, at most 20 times or 10 minutes, whichever comes first.",
                       "the first repeat is due at the limit, which is in time")
        XCTAssertTrue(with(interval: 601, duration: 600).hasPrefix("It never repeats"), "a second past it is not")
        XCTAssertEqual(with(interval: 300, duration: 600),
                       "Every 5 minutes, Hero plays again, at most 20 times or 10 minutes, whichever comes first.")
    }

    func testTheSentenceAndTheCoordinatorAskTheSameRuleAboutTheTimeLimit() {
        // Whatever the numbers, "never repeats" is said exactly when the rule
        // the coordinator arms its first repeat by says no repeat is due.
        let intervals: [Double] = [1, 29.9, 30, 30.0000005, 30.01, 600, 900, 0.1]
        let limits: [Double?] = [nil, 29, 30, 30.01, 600, 0.3, -1, 0]
        for interval in intervals {
            for limit in limits {
                let repeatAlert = RepeatAlert(action: hero, intervalSeconds: interval, maxRepeats: 20, maxDurationSeconds: limit)
                let said = sentence(Escalation(tier3: repeatAlert)).hasPrefix("It never repeats")
                XCTAssertEqual(said, !repeatAlert.timeLimitAllowsRepeat(number: 1), "every \(interval) s, limit \(String(describing: limit))")
            }
        }
    }

    func testTheSentenceForEachShapeOfFinalStep() {
        func final(_ action: FinalAction, after: Double = 120) -> String {
            sentence(Escalation(tier4: FinalAlert(afterSeconds: after, action: action)))
        }
        XCTAssertEqual(final(.alert(glass)), "After 2 minutes it plays Glass.")
        XCTAssertEqual(final(.alert(.speak(speech)), after: 30), "After 30 seconds it speaks the line.")
        XCTAssertEqual(final(.alert(.soundAndSpeak(soundName: "Glass", soundGainDB: 3, speech: speech))),
                       "After 2 minutes it plays Glass and speaks the line.")
        XCTAssertEqual(final(.alert(.silent)), "After 2 minutes it does nothing, as it is silent.")
        XCTAssertEqual(final(.shortcut(name: "Page me")), "After 2 minutes it starts the Shortcut “Page me”.",
                       "a Shortcut by name, and only ever started")
        XCTAssertEqual(final(.shortcut(name: "")), "After 2 minutes it starts a Shortcut that has no name yet.")
        XCTAssertEqual(final(.shortcut(name: "  ")), "After 2 minutes it starts a Shortcut that has no name yet.")
    }

    func testTheSentenceForAWholeLadderTakesTheTiersInOrderWithTheShortcutBesideAPreset() {
        var ladder = Preset.onCall.ladder(repeating: hero)!
        ladder.tier4 = page
        XCTAssertEqual(sentence(ladder),
                       "After 10 seconds a panel stays on screen until you acknowledge it. "
                       + "Every 30 seconds, Hero plays again, at most 20 times or 10 minutes, whichever comes first. "
                       + "After 2 minutes it starts the Shortcut “Page me”.",
                       "describes the actual ladder, a Shortcut included, though the picker shows On call")
    }

    func testAnEmptyLadderIsSaidToHaveNoSteps() {
        XCTAssertEqual(sentence(Escalation()), "This ladder has no steps, so nothing happens after the first alert.")
    }

    func testTheSentenceNeverFailsOnAZeroANegativeAFractionOrAHugeValue() {
        XCTAssertEqual(sentence(Escalation(tier2: PanelAlert(delaySeconds: 0), tier3: RepeatAlert(
            action: hero, intervalSeconds: -5, maxRepeats: 0, maxDurationSeconds: -1))),
                       "After 0 seconds a panel stays on screen until you acknowledge it. "
                       + "Every −5 seconds, Hero plays again, at most 0 times or −1 seconds, whichever comes first.")
        XCTAssertEqual(sentence(Escalation(tier2: PanelAlert(delaySeconds: 10.5))),
                       "After 10.5 seconds a panel stays on screen until you acknowledge it.")
        XCTAssertEqual(sentence(Escalation(tier3: RepeatAlert(action: hero, intervalSeconds: 1, maxRepeats: Int.min,
                                                              maxDurationSeconds: nil))),
                       "Every 1 second, Hero plays again, at most −9223372036854775808 times.")
        for odd in [1e300, -1e300, Double.nan, .infinity, -.infinity, 1e15, 86_400, 5e-324] {
            let ladder = Escalation(tier2: PanelAlert(delaySeconds: odd),
                                    tier3: RepeatAlert(action: hero, intervalSeconds: odd, maxRepeats: Int.max, maxDurationSeconds: odd),
                                    tier4: FinalAlert(afterSeconds: odd, action: .alert(hero)))
            XCTAssertFalse(sentence(ladder).isEmpty, "\(odd)")
            XCTAssertFalse(EditorText.fieldText(seconds: odd).isEmpty, "\(odd)")
        }
    }

    func testTimesReadInSecondsMinutesAndHoursInTheSingularAndThePlural() {
        let expected: [(Double, String)] = [
            (1, "1 second"), (10, "10 seconds"), (59, "59 seconds"), (60, "1 minute"), (90, "1 minute 30 seconds"),
            (120, "2 minutes"), (600, "10 minutes"), (3600, "1 hour"), (7200, "2 hours"), (3660, "1 hour 1 minute"),
            (3661, "1 hour 1 minute 1 second"), (5400, "1 hour 30 minutes"), (86_400, "24 hours"),
        ]
        for (seconds, text) in expected {
            XCTAssertEqual(EditorText.duration(seconds), text, "\(seconds)")
        }
    }

    func testTimesThatAreNotWholeSecondsOrNotPositiveReadInSecondsAndNeverCrash() {
        XCTAssertEqual(EditorText.duration(0), "0 seconds")
        XCTAssertEqual(EditorText.duration(-5), "−5 seconds", "with a true minus")
        XCTAssertEqual(EditorText.duration(-90), "−1 minute 30 seconds")
        XCTAssertEqual(EditorText.duration(2.5), "2.5 seconds")
        XCTAssertEqual(EditorText.duration(0.5), "0.5 seconds")
        XCTAssertEqual(EditorText.duration(90.5), "90.5 seconds", "a fraction is not rounded away")
        XCTAssertEqual(EditorText.duration(1e300), "1e+300 seconds")
        XCTAssertEqual(EditorText.duration(.nan), "a time that cannot be shown")
        XCTAssertEqual(EditorText.duration(.infinity), "a time that cannot be shown")
    }

    func testAFieldShowsTheNumberTypedAndACaptionSaysItInMinutes() {
        let expected: [(Double, String)] = [(10, "10"), (2.5, "2.5"), (0, "0"), (-5, "-5"), (-0.0, "0"), (600, "600"),
                                            (1e300, "1e+300")]
        for (seconds, text) in expected {
            XCTAssertEqual(EditorText.fieldText(seconds: seconds), text, "\(seconds)")
            if let parsed = EscalationEditing.parseSeconds(text) { XCTAssertEqual(parsed, seconds, "it reads back as shown") }
        }
        XCTAssertEqual(EditorText.fieldText(count: 20), "20")
        XCTAssertEqual(EditorText.fieldText(count: -1), "-1")

        XCTAssertNil(EditorText.secondsCaption(30), "under a minute the field already says it")
        XCTAssertNil(EditorText.secondsCaption(59.9))
        XCTAssertNil(EditorText.secondsCaption(.nan))
        XCTAssertEqual(EditorText.secondsCaption(60), "1 minute")
        XCTAssertEqual(EditorText.secondsCaption(150), "2 minutes 30 seconds")
        XCTAssertEqual(EditorText.secondsCaption(600), "10 minutes")
    }

    // MARK: - Off

    func testOffSaysWhatCustomBringsBackOnlyWhileThereIsACustomLadderToBringBack() {
        var aside = EscalationEditing.SetAside()
        XCTAssertEqual(EditorText.offSentence(setAside: aside), "Nothing happens after the first alert.")

        aside.tier3 = RepeatAlert(action: hero)
        XCTAssertEqual(EditorText.offSentence(setAside: aside),
                       "Nothing happens after the first alert. Choose a preset to bring the ladder back.",
                       "no Custom segment exists, so Custom is not named")

        aside.custom = Escalation(tier2: PanelAlert(delaySeconds: 17), tier4: page)
        XCTAssertEqual(EditorText.offSentence(setAside: aside),
                       "Nothing happens after the first alert. Choose Custom to bring back the ladder you set aside. "
                       + "After 17 seconds a panel stays on screen until you acknowledge it. "
                       + "After 2 minutes it starts the Shortcut “Page me”.")
    }

    func testTheQuestionNamesTheShortcutAndTheButtonsAreRemoveAndKeep() {
        XCTAssertEqual(EditorText.offQuestion(shortcutName: "Page me"), "Remove this ladder, including the Shortcut “Page me”?")
        XCTAssertEqual(EditorText.offQuestion(shortcutName: ""), "Remove this ladder, including its Shortcut?")
        XCTAssertEqual(EditorText.offQuestion(shortcutName: "  "), "Remove this ladder, including its Shortcut?")
        XCTAssertEqual(EditorText.removeLadder, "Remove")
        XCTAssertEqual(EditorText.keepLadder, "Keep")
    }

    func testTheSentenceBeneathTheChoiceIsTheQuestionWhileOffWaitsThenTheOffSentenceThenTheLadder() {
        var aside = EscalationEditing.SetAside()
        aside.custom = Escalation(tier2: PanelAlert(delaySeconds: 17))
        let ladder = Preset.onCall.ladder(repeating: hero)
        XCTAssertEqual(EditorText.underChoice(escalation: ladder, setAside: aside, confirmingShortcut: "Page me"),
                       EditorText.offQuestion(shortcutName: "Page me"), "the picker has not moved, the sentence asks")
        XCTAssertEqual(EditorText.underChoice(escalation: ladder, setAside: aside, confirmingShortcut: nil),
                       EditorText.ladderSentence(ladder))
        XCTAssertEqual(EditorText.underChoice(escalation: nil, setAside: aside, confirmingShortcut: nil),
                       EditorText.offSentence(setAside: aside))
        XCTAssertEqual(EditorText.underChoice(escalation: nil, setAside: aside, confirmingShortcut: ""),
                       EditorText.offQuestion(shortcutName: ""), "a pending question wins, even for a blank name")
    }

    // MARK: - Captions, hints and the Test Shortcut wording

    func testTheUnlimitedRepeatCaptionIsOnlyForARepeatWithNeitherLimit() {
        let caption = "With no limit on repeats or time, the Mac stays awake and keeps sounding until you acknowledge it."
        XCTAssertEqual(EditorText.unlimitedRepeatCaption(for: Preset.wakeMe.ladder(repeating: hero)), caption)
        XCTAssertNil(EditorText.unlimitedRepeatCaption(for: Preset.onCall.ladder(repeating: hero)))
        XCTAssertNil(EditorText.unlimitedRepeatCaption(for: Escalation(tier3: RepeatAlert(action: hero, maxRepeats: nil))))
        XCTAssertNil(EditorText.unlimitedRepeatCaption(for: Escalation(tier3: RepeatAlert(action: hero, maxDurationSeconds: nil))))
        XCTAssertNil(EditorText.unlimitedRepeatCaption(for: Preset.gentle.ladder(repeating: hero)), "no repeat at all")
        XCTAssertNil(EditorText.unlimitedRepeatCaption(for: nil))
    }

    private func repeating(repeats: Int?, time: Double?) -> Escalation {
        Escalation(tier3: RepeatAlert(action: hero, maxRepeats: repeats, maxDurationSeconds: time))
    }

    func testEachLimitHasANoLimitSwitchAndAHintThatSaysItRepeatsUntilAcknowledgedOnlyWhenNothingElseStopsIt() {
        XCTAssertEqual(EditorText.noLimit, "No limit")
        let neither = repeating(repeats: nil, time: nil)
        XCTAssertEqual(EditorText.noLimitHint(.repeats, in: neither), "No limit on repeats: it repeats until you acknowledge it.")
        XCTAssertEqual(EditorText.noLimitHint(.duration, in: neither), "No time limit: it repeats until you acknowledge it.")
    }

    func testAHintNamesTheLimitThatStillStopsTheRepeats() {
        // On call's own limits, with one of them switched to no limit.
        let onlyTheTimeLimit = repeating(repeats: nil, time: 600)
        XCTAssertEqual(EditorText.noLimitHint(.repeats, in: onlyTheTimeLimit),
                       "No limit on repeats: it still stops after 10 minutes.")
        let onlyTheCount = repeating(repeats: 20, time: nil)
        XCTAssertEqual(EditorText.noLimitHint(.duration, in: onlyTheCount),
                       "No time limit: it still stops after 20 repeats.")
        XCTAssertEqual(EditorText.noLimitHint(.duration, in: repeating(repeats: 1, time: nil)),
                       "No time limit: it still stops after 1 repeat.", "one repeat, not 1 repeats")
        XCTAssertEqual(EditorText.noLimitHint(.repeats, in: repeating(repeats: nil, time: 90)),
                       "No limit on repeats: it still stops after 1 minute 30 seconds.")
        XCTAssertEqual(EditorText.noLimitHint(.duration, in: repeating(repeats: 0, time: nil)),
                       "No time limit: it still stops after 0 repeats.", "a hand-written 0 is shown as it is")
    }

    func testAHintSaysUntilYouAcknowledgeItOnlyWhenBothLimitsAreOff() {
        let numbers: [(repeats: Int?, time: Double?)] = [(nil, nil), (20, nil), (nil, 600), (20, 600)]
        for (repeats, time) in numbers {
            let ladder = repeating(repeats: repeats, time: time)
            let bothOff = repeats == nil && time == nil
            let hints = [(EscalationEditing.Limit.repeats, repeats == nil), (.duration, time == nil)]
                .map { limit, ticked in (limit, ticked, EditorText.noLimitHint(limit, in: ladder)) }
            for (limit, ticked, hint) in hints {
                let what = "\(limit) over repeats \(String(describing: repeats)) and time \(String(describing: time))"
                XCTAssertEqual(hint != nil, ticked, "a hint is for a switch that is ticked: \(what)")
                guard let hint else { continue }
                XCTAssertEqual(hint.contains("until you acknowledge it"), bothOff,
                               "it repeats until acknowledged only if nothing else stops it: \(what): \(hint)")
                if !bothOff {
                    XCTAssertTrue(hint.contains("still stops after"), hint)
                    XCTAssertTrue(hint.contains(limit == .repeats ? "10 minutes" : "20 repeats"), "names the other limit: \(hint)")
                }
            }
        }
    }

    func testAHintIsForARepeatThatExists() {
        XCTAssertNil(EditorText.noLimitHint(.repeats, in: nil))
        XCTAssertNil(EditorText.noLimitHint(.duration, in: nil))
        let gentle = Preset.gentle.ladder(repeating: hero)
        XCTAssertNil(EditorText.noLimitHint(.repeats, in: gentle), "no tier 3, nothing to limit")
        XCTAssertNil(EditorText.noLimitHint(.duration, in: Escalation(tier4: page)))
        XCTAssertEqual(EditorText.noLimitHint(.repeats, in: Preset.wakeMe.ladder(repeating: hero)),
                       "No limit on repeats: it repeats until you acknowledge it.", "Wake me's own")
        XCTAssertNil(EditorText.noLimitHint(.repeats, in: Preset.onCall.ladder(repeating: hero)), "On call has a limit on repeats")
    }

    func testTestShortcutSaysItReallyRunsTheShortcutAndTheResultSaysStartedNeverWorked() {
        XCTAssertEqual(EditorText.testShortcut, "Test Shortcut")
        XCTAssertEqual(EditorText.testShortcutHelp, "This really runs the Shortcut.")
        XCTAssertEqual(EditorText.shortcutTestStarted("Page me"), "Started “Page me”")
        XCTAssertFalse(EditorText.shortcutTestStarted("Page me").lowercased().contains("work"))
    }

    func testTheNotFoundAdviceSaysWhatANameNotFoundDoesAndNotWhetherTheRuleIsInEffect() {
        let advice = EditorText.shortcutNotFoundAdvice
        XCTAssertTrue(advice.hasPrefix("Not found in the Shortcuts app."), advice)
        XCTAssertTrue(advice.contains("exactly, including capitals, spaces and punctuation"), advice)
        XCTAssertTrue(advice.contains("A name that is not found does not switch the rule off"),
                      "a warning, not a refusal (M5 plan, ruling 21)")
        // It is shown beside a draft that is not saved, and beside a rule that
        // has other problems, and in both the dry-run line below it says the
        // rule is not in effect. Whether it is is that line's to say.
        XCTAssertFalse(advice.lowercased().contains("in effect"), advice)
        XCTAssertTrue(advice.contains(EditorText.testShortcut), "and says how to try the name")
    }

    // MARK: - Headings, segments and assistive technology

    func testTheTiersAreHeadedAsThePanelAndTheInspectorSayThem() {
        XCTAssertEqual([2, 3, 4].map(EditorText.tierHeading), ["Tier 2", "Tier 3", "Tier 4"])
        XCTAssertEqual(EditorText.finalKindName(.alert), "Alert")
        XCTAssertEqual(EditorText.finalKindName(.shortcut), "Shortcut")
    }

    func testEveryControlHasADistinctLabelForAScreenReaderThatSaysItsTier() {
        let labels = EditorText.Control.allCases.map(EditorText.label)
        XCTAssertEqual(Set(labels).count, labels.count, "no two controls are announced alike")
        XCTAssertFalse(labels.contains { $0.isEmpty })
        XCTAssertEqual(EditorText.label(.ladderChoice), EditorText.ifIDontAcknowledge)
        XCTAssertEqual(EditorText.label(.tier4TestShortcut), EditorText.testShortcut)
        // The snooze box follows the ladder and is no tier: it says its own visible words.
        XCTAssertEqual(EditorText.label(.snoozeSwitch), SnoozeText.ruleSwitchLabel)
        XCTAssertEqual(EditorText.label(.snoozeSwitch), "Stay quiet while I have snoozed")
        for control in EditorText.Control.allCases {
            let label = EditorText.label(control)
            guard control != .ladderChoice, control != .tier4TestShortcut, control != .snoozeSwitch else { continue }
            XCTAssertTrue(label.hasPrefix("Tier "), "\(control): \(label)")
        }
        XCTAssertEqual(EditorText.Control.allCases.count, 15)
    }

    func testEachAlertPickerHasALabelOfItsOwn() {
        let roles: [AlertEditing.Role] = [.first, .repeating, .final]
        let labels = roles.map(EditorText.alertPickerLabel)
        XCTAssertEqual(Set(labels).count, 3)
        XCTAssertEqual(labels[1], "Tier 3 alert")
        XCTAssertEqual(labels[2], "Tier 4 alert")
        XCTAssertFalse(labels[0].isEmpty, "the first alert's picker has no label today")
    }

    // MARK: - The rule list's row

    func testARowSaysWhatTheLadderIsBesideTheAlert() {
        func summary(_ alert: AlertAction?, _ ladder: Escalation?) -> String { EditorText.alertSummary(alert, escalation: ladder) }
        XCTAssertEqual(summary(hero, nil), "Hero")
        XCTAssertEqual(summary(hero, Escalation()), "Hero", "an empty ladder is no ladder")
        XCTAssertEqual(summary(hero, Preset.onCall.ladder(repeating: hero)), "Hero, escalating: On call")
        XCTAssertEqual(summary(.sound(name: "Hero", gainDB: 6), Preset.wakeMe.ladder(repeating: hero)),
                       "Hero (+6 dB), escalating: Wake me")
        XCTAssertEqual(summary(.silent, Preset.gentle.ladder(repeating: hero)), "Silent, escalating: Gentle")
        XCTAssertEqual(summary(nil, Preset.gentle.ladder(repeating: hero)), "No alert, escalating: Gentle")
        XCTAssertEqual(summary(hero, Escalation(tier2: PanelAlert(delaySeconds: 3))), "Hero, escalating: custom ladder")
        var withShortcut = Preset.onCall.ladder(repeating: hero)!
        withShortcut.tier4 = page
        XCTAssertEqual(summary(hero, withShortcut), "Hero, escalating: On call, with a Shortcut")
        XCTAssertEqual(summary(hero, Escalation(tier4: page)), "Hero, escalating: custom ladder, with a Shortcut")
        withShortcut.tier4 = FinalAlert(action: .alert(glass))
        XCTAssertEqual(summary(hero, withShortcut), "Hero, escalating: On call", "a final alert is not a Shortcut")
    }

    func testTheOldRowSummaryIsKeptAsItWas() {
        XCTAssertEqual(EditorText.alertSummary(nil), "No alert")
        XCTAssertEqual(EditorText.alertSummary(.silent), "Silent")
        XCTAssertEqual(EditorText.alertSummary(hero), "Hero")
        XCTAssertEqual(EditorText.alertSummary(.speak(speech)), "Spoken")
        XCTAssertEqual(EditorText.alertSummary(.soundAndSpeak(soundName: "Hero", soundGainDB: -3, speech: speech)), "Hero (−3 dB), spoken")
        XCTAssertEqual(EditorText.alertSummary(hero, escalation: nil), EditorText.alertSummary(hero))
    }

    // MARK: - What each kind of alert does, by step

    func testTheFirstAlertsMeaningIsAsItWas() {
        XCTAssertEqual(EditorText.alertMeaning(nil), "Matching notifications are marked in the Inspector. Nothing plays.")
        XCTAssertEqual(EditorText.alertMeaning(.silent),
                       "Matching notifications are claimed and stay quiet: no rule below can sound for them.")
        XCTAssertEqual(EditorText.alertMeaning(hero), "Plays this sound when a notification matches.")
        XCTAssertEqual(EditorText.alertMeaning(.speak(speech)), "Speaks a line built from the notification when one matches.")
        XCTAssertEqual(EditorText.alertMeaning(.soundAndSpeak(soundName: "Hero", soundGainDB: 0, speech: speech)),
                       "Plays this sound, then speaks a line built from the notification.")
        for alert in [nil, .silent, hero, .speak(speech)] as [AlertAction?] {
            XCTAssertEqual(EditorText.alertMeaning(alert, role: .first), EditorText.alertMeaning(alert))
        }
    }

    func testARepeatsAndAFinalAlertsMeaningAreWordedForTheirStep() {
        let both = AlertAction.soundAndSpeak(soundName: "Hero", soundGainDB: 0, speech: speech)
        let alerts: [AlertAction?] = [nil, .silent, hero, .speak(speech), both]
        XCTAssertEqual(EditorText.alertMeaning(hero, role: .repeating), "Plays this sound again each time the ladder repeats.")
        XCTAssertEqual(EditorText.alertMeaning(.speak(speech), role: .repeating),
                       "Speaks a line built from the notification each time the ladder repeats.")
        XCTAssertEqual(EditorText.alertMeaning(both, role: .repeating),
                       "Plays this sound, then speaks a line built from the notification, each time the ladder repeats.")
        XCTAssertEqual(EditorText.alertMeaning(.silent, role: .repeating),
                       "This repeat is silent, so it repeats nothing. Choose a sound or speech.")
        XCTAssertEqual(EditorText.alertMeaning(hero, role: .final), "Plays this sound once, if nobody has acknowledged by then.")
        XCTAssertEqual(EditorText.alertMeaning(.speak(speech), role: .final),
                       "Speaks a line built from the notification once, if nobody has acknowledged by then.")
        XCTAssertEqual(EditorText.alertMeaning(both, role: .final),
                       "Plays this sound, then speaks a line built from the notification, once, if nobody has acknowledged by then.")
        XCTAssertEqual(EditorText.alertMeaning(.silent, role: .final),
                       "This final alert is silent, so it would do nothing. Choose a sound or speech, or a Shortcut.")
        XCTAssertEqual(EditorText.alertMeaning(nil, role: .repeating), "There is no alert here, so nothing repeats.")
        XCTAssertEqual(EditorText.alertMeaning(nil, role: .final), "There is no alert here, so nothing happens at the final step.")
        for alert in alerts {
            let said = [AlertEditing.Role.first, .repeating, .final].map { EditorText.alertMeaning(alert, role: $0) }
            XCTAssertEqual(Set(said).count, 3, "a later step never borrows the first alert's words: \(String(describing: alert))")
        }
    }

    // MARK: - Nothing a notification said

    func testNothingTheLadderSaysHoldsAWordOfANotification() {
        let notifications = [AlertEditing.sampleNotification, AlertEditing.shortcutTestNotification]
        let fields = notifications.flatMap { [$0.appNameGuess, $0.title, $0.subtitle, $0.body] }
            .filter { !$0.isEmpty }
        var said: [String] = []
        for preset in Preset.allCases {
            said.append(EditorText.presetMeaning(preset))
            said.append(sentence(preset.ladder(repeating: hero)))
        }
        var aside = EscalationEditing.SetAside()
        aside.custom = Escalation(tier2: PanelAlert(), tier3: RepeatAlert(action: .speak(speech)), tier4: page)
        said.append(sentence(aside.custom))
        said.append(EditorText.offSentence(setAside: aside))
        said.append(EditorText.offQuestion(shortcutName: "Page me"))
        said.append(EditorText.shortcutTestStarted("Page me"))
        for (repeats, time) in [(nil, nil), (20, nil), (nil, 600)] as [(Int?, Double?)] {
            let ladder = repeating(repeats: repeats, time: time)
            said += [EscalationEditing.Limit.repeats, .duration].compactMap { EditorText.noLimitHint($0, in: ladder) }
        }
        said.append(sentence(Escalation(tier3: RepeatAlert(action: hero, intervalSeconds: 900, maxDurationSeconds: 600))))
        said.append(EditorText.shortcutNotFoundAdvice)
        said.append(EditorText.testShortcutHelp)
        said += EditorText.Control.allCases.map(EditorText.label)
        let alerts: [AlertAction?] = [nil, .silent, hero, .speak(speech)]
        for role in [AlertEditing.Role.first, .repeating, .final] {
            said += alerts.map { EditorText.alertMeaning($0, role: role) }
        }
        for line in said {
            for field in fields {
                XCTAssertFalse(line.contains(field), "“\(line)” holds “\(field)”")
            }
        }
    }
}
