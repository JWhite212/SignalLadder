import XCTest
@testable import NotificationCore

/// The ladder editor's controls, as state transitions. Fixtures are invented
/// text, never captured content (§10.1).
final class EscalationEditingTests: XCTestCase {
    typealias Preset = EscalationEditing.Preset
    typealias SetAside = EscalationEditing.SetAside

    private let daniel = "com.apple.voice.compact.en-GB.Daniel"
    private let hero = AlertAction.sound(name: "Hero", gainDB: 0)
    private let glass = AlertAction.sound(name: "Glass", gainDB: 0)
    private var spoken: AlertAction { .speak(SpeechAction(voiceIdentifier: daniel, template: "{title}")) }
    private var heroAndSpeech: AlertAction {
        .soundAndSpeak(soundName: "Hero", soundGainDB: 6, speech: SpeechAction(voiceIdentifier: daniel))
    }
    private let page = FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me"))

    /// A sound check that has what these tests name, so a rule that names
    /// anything else is reported.
    private var sounds: RuleSetCodec.SoundCheck {
        RuleSetCodec.SoundCheck(available: ["Hero", "Glass"], unplayable: nil, voices: [daniel], shortcuts: nil)
    }

    private func rule(alert: AlertAction?, _ escalation: Escalation?) -> Rule {
        Rule(name: "Pager", condition: .field(.app, .equals, "Microsoft Teams"), alert: alert, escalation: escalation)
    }

    private func choose(_ preset: Preset, _ escalation: Escalation?, aside: SetAside = SetAside(),
                        alert: AlertAction? = AlertAction.sound(name: "Hero", gainDB: 0)) -> EscalationEditing.Choice {
        EscalationEditing.choose(preset, escalation: escalation, setAside: aside, firstAlert: alert, defaultSound: "Glass")
    }

    /// The edit a choice made, failing the test when it made none.
    private func edit(_ choice: EscalationEditing.Choice, file: StaticString = #filePath,
                      line: UInt = #line) -> EscalationEditing.Edit {
        guard case .changed(let edit) = choice else {
            XCTFail("expected a change, got \(choice)", file: file, line: line)
            return EscalationEditing.Edit(escalation: nil, setAside: SetAside())
        }
        return edit
    }

    /// The On call ladder repeating `action`, with a final step beside it.
    private func onCall(_ action: AlertAction? = nil, tier4: FinalAlert? = nil) -> Escalation {
        var ladder = Preset.onCall.ladder(repeating: action ?? hero)!
        ladder.tier4 = tier4
        return ladder
    }

    private func repeatAction(_ edit: EscalationEditing.Edit) -> AlertAction? { edit.escalation?.tier3?.action }

    // MARK: - Presets

    func testEachPresetOverEachFirstAlertKindMakesARuleTheLoaderAccepts() {
        let firsts: [AlertAction] = [.silent, hero, spoken, heroAndSpeech]
        for preset in Preset.allCases where preset != .off {
            for first in firsts {
                let result = edit(choose(preset, nil, alert: first))
                let made = rule(alert: first, result.escalation)
                XCTAssertNotNil(result.escalation, "\(preset) over \(first)")
                XCTAssertEqual(RuleSetCodec.problems(in: made), [], "\(preset) over \(first)")
                XCTAssertEqual(RuleSetCodec.reasons(for: made, fileVersion: 4, sounds: sounds), [],
                               "\(preset) over \(first), against a check that holds the default sound")
            }
        }
    }

    func testEachPresetRoundTripsThroughTheFileAtVersion4AndOffWritesNoEscalationKey() throws {
        for preset in Preset.allCases where preset != .off {
            let made = rule(alert: hero, edit(choose(preset, nil)).escalation)
            let data = try RuleSetCodec.encode([made])
            XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""version" : 4"#), "\(preset)")
            let (decoded, problems) = try RuleSetCodec.decode(data)
            XCTAssertEqual(problems, [], "\(preset)")
            XCTAssertEqual(decoded, [made], "\(preset)")
            XCTAssertEqual(EscalationEditing.shown(for: decoded[0].escalation), .preset(preset), "\(preset)")
        }
        let off = rule(alert: hero, edit(choose(.off, onCall())).escalation)
        XCTAssertNil(off.escalation)
        XCTAssertFalse(String(decoding: try RuleSetCodec.encode([off]), as: UTF8.self).contains("escalation"))
    }

    func testAnEditCarriesALadderAndWhatWasSetAsideAndNothingOfTheRule() {
        // A rule opted in to being held by a snooze must have been opted in on
        // purpose, so a preset never carries it (M5 plan, ruling 3). What
        // keeps it out of reach is the shape of an edit: `choose` is handed a
        // ladder, what was set aside and the first alert, never the rule, and
        // gives back an `Edit`, which the editor applies to the rule's ladder
        // and to its own state alone. So this holds the shape. A field added
        // to `Edit` for the rule's flag, or for anything else of the rule's,
        // fails here and has to be argued with ruling 3.
        for preset in Preset.allCases {
            let made = edit(choose(preset, preset == .off ? onCall() : nil))
            XCTAssertEqual(Mirror(reflecting: made).children.compactMap(\.label), ["escalation", "setAside"],
                           "the edit \(preset) makes")
        }
        for answer in [EscalationEditing.OffAnswer.keep, .remove] {
            let made = EscalationEditing.answeringOff(answer, escalation: onCall(tier4: page), setAside: SetAside())
            XCTAssertEqual(Mirror(reflecting: made).children.compactMap(\.label), ["escalation", "setAside"],
                           "the edit answering Off with \(answer) makes")
        }
    }

    func testTheFileAPresetMakesHasNoSnoozeKeyAndNeedsNoNewVersion() throws {
        // The file a preset makes is the file it always made: no
        // `quietWhenSnoozed` key and a version below 5. The rule is built by
        // this file's helper, so this cannot trip on a preset's own doing
        // (the test above pins that); it trips if a rule the editor writes
        // with a ladder were to need the new version, or to write the key
        // when the flag is off.
        let firsts: [AlertAction] = [.silent, hero, spoken, heroAndSpeech]
        for preset in Preset.allCases {
            for first in firsts {
                let made = rule(alert: first, preset == .off ? nil : edit(choose(preset, nil, alert: first)).escalation)
                XCTAssertFalse(made.quietWhenSnoozed, "\(preset) over \(first)")

                let data = try RuleSetCodec.encode([made])
                let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                let written = try XCTUnwrap((root["rules"] as? [[String: Any]])?.first)
                XCTAssertNil(written["quietWhenSnoozed"], "\(preset) over \(first)")
                XCTAssertLessThanOrEqual(try XCTUnwrap(root["version"] as? Int), 4, "\(preset) over \(first)")
            }
        }
    }

    /// The `escalation` object a rule is written with, as the file holds it.
    private func writtenEscalation(_ preset: Preset) throws -> (object: NSDictionary, text: String) {
        let data = try RuleSetCodec.encode([rule(alert: hero, preset.ladder(repeating: hero))])
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rules = try XCTUnwrap(root["rules"] as? [[String: Any]])
        return (try XCTUnwrap(rules[0]["escalation"] as? NSDictionary), String(decoding: data, as: UTF8.self))
    }

    func testOnCallIsPinnedToTodaysDefaultsAndToItsExactFile() throws {
        // A preset is recognised by its numbers, so these are literals and a
        // change to a default is a conscious act (M5 plan, ruling 3).
        XCTAssertEqual(Preset.onCall.tier2, PanelAlert())
        XCTAssertEqual(Preset.onCall.repeating, Preset.Timing(intervalSeconds: RepeatAlert.defaultIntervalSeconds,
                                                              maxRepeats: RepeatAlert.defaultMaxRepeats,
                                                              maxDurationSeconds: RepeatAlert.defaultMaxDurationSeconds))
        XCTAssertEqual(Preset.onCall.ladder(repeating: hero), Escalation(tier2: PanelAlert(), tier3: RepeatAlert(action: hero)))

        let expected: NSDictionary = [
            "tier2": ["delaySeconds": 10],
            "tier3": ["action": ["gainDB": 0, "sound": "Hero"], "intervalSeconds": 30,
                      "maxDurationSeconds": 600, "maxRepeats": 20] as NSDictionary,
        ]
        XCTAssertEqual(try writtenEscalation(.onCall).object, expected)
    }

    func testWakeMeAndGentleHaveTheirExactFilesAndWakeMeWritesBothLimitsAsNull() throws {
        let wake = try writtenEscalation(.wakeMe)
        let expected: NSDictionary = [
            "tier2": ["delaySeconds": 5],
            "tier3": ["action": ["gainDB": 0, "sound": "Hero"], "intervalSeconds": 15,
                      "maxDurationSeconds": NSNull(), "maxRepeats": NSNull()] as NSDictionary,
        ]
        XCTAssertEqual(wake.object, expected)
        // Written out, since a key that is absent reads as the default.
        XCTAssertTrue(wake.text.contains(#""maxRepeats" : null"#), wake.text)
        XCTAssertTrue(wake.text.contains(#""maxDurationSeconds" : null"#), wake.text)

        XCTAssertEqual(try writtenEscalation(.gentle).object, ["tier2": ["delaySeconds": 10]] as NSDictionary)
    }

    func testEachPresetIsRecognisedAsItself() {
        XCTAssertEqual(EscalationEditing.shown(for: nil), .preset(.off), "nil is Off")
        for preset in Preset.allCases {
            XCTAssertEqual(EscalationEditing.shown(for: preset.ladder(repeating: hero)), .preset(preset), "\(preset)")
        }
    }

    func testALadderThatDiffersByOneFieldIsCustom() {
        func ladder(_ change: (inout Escalation) -> Void, from preset: Preset = .onCall) -> Escalation {
            var ladder = preset.ladder(repeating: hero)!
            change(&ladder)
            return ladder
        }
        let custom: [(String, Escalation)] = [
            ("an interval of 31", ladder { $0.tier3?.intervalSeconds = 31 }),
            ("a limit of 21", ladder { $0.tier3?.maxRepeats = 21 }),
            ("a delay of 11", ladder { $0.tier2 = PanelAlert(delaySeconds: 11) }),
            ("a time limit of 601", ladder { $0.tier3?.maxDurationSeconds = 601 }),
            ("a tier 3 added to Gentle", ladder({ $0.tier3 = RepeatAlert(action: self.hero, intervalSeconds: 45) }, from: .gentle)),
            ("Wake me with a repeat limit", ladder({ $0.tier3?.maxRepeats = 20 }, from: .wakeMe)),
            ("Wake me with a time limit", ladder({ $0.tier3?.maxDurationSeconds = 3600 }, from: .wakeMe)),
            ("Wake me with a delay of 6", ladder({ $0.tier2 = PanelAlert(delaySeconds: 6) }, from: .wakeMe)),
            ("On call without its panel", ladder { $0.tier2 = nil }),
        ]
        for (what, escalation) in custom {
            XCTAssertEqual(EscalationEditing.shown(for: escalation), .custom, what)
        }
    }

    func testADifferentRepeatActionAndAnAddedTier4LeaveThePresetAsItWas() {
        for preset in [Preset.onCall, .wakeMe] {
            var ladder = preset.ladder(repeating: hero)!
            ladder.tier3?.action = spoken
            XCTAssertEqual(EscalationEditing.shown(for: ladder), .preset(preset), "a different repeat, \(preset)")
            ladder.tier3?.action = heroAndSpeech
            XCTAssertEqual(EscalationEditing.shown(for: ladder), .preset(preset), "a sound with speech, \(preset)")
        }
        for preset in Preset.allCases where preset != .off {
            var ladder = preset.ladder(repeating: hero)!
            ladder.tier4 = page
            XCTAssertEqual(EscalationEditing.shown(for: ladder), .preset(preset), "a Shortcut beside \(preset)")
            ladder.tier4 = FinalAlert(action: .alert(glass))
            XCTAssertEqual(EscalationEditing.shown(for: ladder), .preset(preset), "an alert beside \(preset)")
        }
    }

    func testTier4AloneAnEmptyLadderASilentRepeatAndABlankShortcutAreCustom() {
        XCTAssertEqual(EscalationEditing.shown(for: Escalation(tier4: page)), .custom, "tier 4 alone")
        XCTAssertEqual(EscalationEditing.shown(for: Escalation(tier4: FinalAlert(action: .shortcut(name: "")))), .custom,
                       "a blank Shortcut name alone")
        XCTAssertEqual(EscalationEditing.shown(for: Escalation()), .custom, "an empty {} is not Off")
        XCTAssertEqual(EscalationEditing.shown(for: Escalation(tier3: RepeatAlert(action: hero))), .custom, "tier 3 alone")
        for preset in [Preset.onCall, .wakeMe] {
            var silent = preset.ladder(repeating: hero)!
            silent.tier3?.action = .silent
            XCTAssertEqual(EscalationEditing.shown(for: silent), .custom, "a silent repeat is not \(preset)")
        }
    }

    func testNoTwoPresetsOverlap() {
        for preset in Preset.allCases {
            let ladder = preset.ladder(repeating: hero)
            XCTAssertEqual(Preset.allCases.filter { $0.matches(ladder) }, [preset], "\(preset)")
        }
        XCTAssertEqual(Preset.allCases.filter { $0.matches(Escalation()) }, [], "an empty ladder is no preset")
    }

    func testChoosingAPresetKeepsTier4AndTheRepeatsAction() {
        let result = edit(choose(.wakeMe, onCall(spoken, tier4: page)))
        XCTAssertEqual(result.escalation?.tier4, page)
        XCTAssertEqual(repeatAction(result), spoken, "the repeat's action is kept, not derived again")
        XCTAssertEqual(result.escalation?.tier3?.intervalSeconds, 15, "its numbers are the preset's")
        XCTAssertEqual(EscalationEditing.shown(for: result.escalation), .preset(.wakeMe))
    }

    func testChoosingOnePresetAfterAnotherNeverSetsTheOldOneAsideAsCustom() {
        // A preset is brought back by choosing it, so changing one for another
        // leaves nothing for Custom to restore: no Custom segment, and no
        // sentence that names it. A Shortcut beside the preset changes none of
        // that, since a preset owns tiers 2 and 3 only.
        let presets: [Preset] = [.gentle, .onCall, .wakeMe]
        for from in presets {
            for to in presets where to != from {
                for tier4 in [nil, page] as [FinalAlert?] {
                    let what = "\(from) then \(to), \(tier4 == nil ? "bare" : "with a Shortcut")"
                    var start = edit(choose(from, nil))
                    start.escalation?.tier4 = tier4
                    XCTAssertEqual(EscalationEditing.shown(for: start.escalation), .preset(from), what)

                    let changed = edit(choose(to, start.escalation, aside: start.setAside))
                    XCTAssertEqual(EscalationEditing.shown(for: changed.escalation), .preset(to), what)
                    XCTAssertNil(changed.setAside.custom, what)
                    XCTAssertFalse(EscalationEditing.segments(for: changed.escalation, setAside: changed.setAside)
                                    .contains(.custom), what)

                    // Off over a bare preset asks nothing and sets only its tiers aside.
                    guard tier4 == nil else {
                        XCTAssertEqual(choose(.off, changed.escalation), .needsConfirmation(shortcutName: "Page me"), what)
                        continue
                    }
                    let off = edit(choose(.off, changed.escalation, aside: changed.setAside))
                    XCTAssertNil(off.setAside.custom, what)
                    XCTAssertFalse(EscalationEditing.segments(for: nil, setAside: off.setAside).contains(.custom), what)
                    XCTAssertFalse(EditorText.offSentence(setAside: off.setAside).contains(EditorText.customName),
                                   "the sentence beneath Off does not name a Custom ladder that does not exist: \(what)")
                }
            }
        }
    }

    func testOffAndThenAPresetRestoresTier4AndTheRepeatsAction() {
        let before = onCall(spoken, tier4: FinalAlert(afterSeconds: 90, action: .alert(glass)))
        let off = edit(choose(.off, before))
        XCTAssertNil(off.escalation)
        let back = edit(choose(.onCall, off.escalation, aside: off.setAside))
        XCTAssertEqual(back.escalation, before, "the very ladder, tier 4 and the repeat's action included")
        let wake = edit(choose(.wakeMe, off.escalation, aside: off.setAside))
        XCTAssertEqual(wake.escalation?.tier4, before.tier4, "whichever preset comes back")
        XCTAssertEqual(repeatAction(wake), spoken)
    }

    func testAPresetOverANilFirstAlertChangesNothing() {
        for preset in Preset.allCases where preset != .off {
            XCTAssertFalse(EscalationEditing.isAvailable(preset, forAlert: nil), "\(preset)")
            XCTAssertEqual(choose(preset, nil, alert: nil), .unchanged, "\(preset)")
            XCTAssertEqual(choose(preset, onCall(), alert: nil), .unchanged, "\(preset), over a hand-written ladder")
            for alert in [AlertAction.silent, hero, spoken] {
                XCTAssertTrue(EscalationEditing.isAvailable(preset, forAlert: alert), "\(preset) over \(alert)")
            }
        }
        XCTAssertTrue(EscalationEditing.isAvailable(.off, forAlert: nil), "Off needs no alert")
    }

    func testThePickerIsDisabledWithNoFirstAlertUnlessALadderExistsToRemove() {
        XCTAssertFalse(EscalationEditing.isPickerEnabled(for: nil, alert: nil))
        XCTAssertTrue(EscalationEditing.isPickerEnabled(for: onCall(), alert: nil), "so Off can still remove it")
        XCTAssertTrue(EscalationEditing.isPickerEnabled(for: Escalation(), alert: nil), "an empty {} too")
        XCTAssertTrue(EscalationEditing.isPickerEnabled(for: nil, alert: .silent))
        XCTAssertTrue(EscalationEditing.isPickerEnabled(for: nil, alert: hero))
    }

    func testChoosingThePresetAlreadyShownChangesNothing() {
        for preset in Preset.allCases {
            XCTAssertEqual(choose(preset, preset.ladder(repeating: spoken)), .unchanged, "\(preset)")
        }
        var withTier4 = onCall()
        withTier4.tier4 = page
        XCTAssertEqual(choose(.onCall, withTier4), .unchanged, "a Shortcut beside it does not make it another")
    }

    func testCustomThenOnCallThenCustomRestoresTheOriginalExactly() {
        let original = Escalation(tier2: PanelAlert(delaySeconds: 17),
                                  tier3: RepeatAlert(action: spoken, intervalSeconds: 45, maxRepeats: 3, maxDurationSeconds: nil),
                                  tier4: page)
        XCTAssertEqual(EscalationEditing.shown(for: original), .custom)

        let preset = edit(choose(.onCall, original))
        XCTAssertEqual(EscalationEditing.shown(for: preset.escalation), .preset(.onCall))
        XCTAssertEqual(preset.setAside.custom, original, "the whole ladder is set aside")
        XCTAssertTrue(EscalationEditing.segments(for: preset.escalation, setAside: preset.setAside).contains(.custom))

        let back = edit(EscalationEditing.chooseCustom(escalation: preset.escalation, setAside: preset.setAside))
        XCTAssertEqual(back.escalation, original)
    }

    func testChoosingAPresetOverACustomLadderDoesNotLoseATier4AddedMeanwhile() {
        // Custom is restored exactly; what it replaces is kept tier by tier,
        // so a Shortcut typed in the meantime is still there to switch back on.
        let original = Escalation(tier2: PanelAlert(delaySeconds: 17), tier3: RepeatAlert(action: hero, intervalSeconds: 45))
        let preset = edit(choose(.onCall, original))
        var edited = preset.escalation!
        edited.tier4 = page
        let back = edit(EscalationEditing.chooseCustom(escalation: edited, setAside: preset.setAside))
        XCTAssertEqual(back.escalation, original)
        XCTAssertEqual(back.setAside.tier4, page)
        let on = EscalationEditing.settingTier4(true, in: back.escalation, setAside: back.setAside, firstAlert: hero,
                                                defaultSound: "Glass")
        XCTAssertEqual(on.escalation?.tier4, page)
    }

    func testChoosingCustomWhenNoneIsSetAsideOrCustomIsShownChangesNothing() {
        XCTAssertEqual(EscalationEditing.chooseCustom(escalation: onCall(), setAside: SetAside()), .unchanged)
        var aside = SetAside()
        aside.custom = Escalation(tier4: page)
        let custom = Escalation(tier2: PanelAlert(delaySeconds: 3))
        XCTAssertEqual(EscalationEditing.chooseCustom(escalation: custom, setAside: aside), .unchanged,
                       "already custom: nothing to go back to")
    }

    func testCustomIsASegmentOnlyWhileTheLadderIsCustomOrACustomOneIsSetAside() {
        let presets: [EscalationEditing.Shown] = [.preset(.off), .preset(.gentle), .preset(.onCall), .preset(.wakeMe)]
        XCTAssertEqual(EscalationEditing.segments(for: nil, setAside: SetAside()), presets)
        XCTAssertEqual(EscalationEditing.segments(for: onCall(), setAside: SetAside()), presets)
        XCTAssertEqual(EscalationEditing.segments(for: Escalation(tier4: page), setAside: SetAside()), presets + [.custom],
                       "shown while the ladder is custom, so the selection has a segment")
        var aside = SetAside()
        aside.custom = Escalation(tier4: page)
        XCTAssertEqual(EscalationEditing.segments(for: nil, setAside: aside), presets + [.custom])
        XCTAssertEqual(EscalationEditing.segments(for: onCall(), setAside: aside), presets + [.custom])
        for escalation in [nil, onCall(), Escalation(tier4: page), Escalation()] as [Escalation?] {
            XCTAssertTrue(EscalationEditing.segments(for: escalation, setAside: SetAside())
                            .contains(EscalationEditing.shown(for: escalation)), "a selection always has a segment")
        }
    }

    /// Ladders a hand-written file can hold, each wrong in one way, that the
    /// editor must still be able to show.
    private func oddLadders() -> [(String, Escalation)] {
        [
            ("an interval of 0", Escalation(tier2: PanelAlert(), tier3: RepeatAlert(action: hero, intervalSeconds: 0))),
            ("a negative delay", Escalation(tier2: PanelAlert(delaySeconds: -5))),
            ("a fraction", Escalation(tier2: PanelAlert(delaySeconds: 10.5))),
            ("a huge value", Escalation(tier2: PanelAlert(delaySeconds: 1e300))),
            ("a silent repeat", Escalation(tier2: PanelAlert(), tier3: RepeatAlert(action: .silent))),
            ("a blank Shortcut name", Escalation(tier2: PanelAlert(), tier4: FinalAlert(action: .shortcut(name: " ")))),
            ("a zero repeat limit", Escalation(tier3: RepeatAlert(action: hero, maxRepeats: 0, maxDurationSeconds: -1))),
        ]
    }

    func testShowingAHandWrittenLadderChangesNothing() {
        for (what, ladder) in oddLadders() {
            let shown = EscalationEditing.shown(for: ladder)
            XCTAssertTrue(EscalationEditing.segments(for: ladder, setAside: SetAside()).contains(shown), what)
            // What is shown is what is there: choosing it again writes nothing.
            switch shown {
            case .custom:
                XCTAssertEqual(EscalationEditing.chooseCustom(escalation: ladder, setAside: SetAside()), .unchanged, what)
            case .preset(let preset):
                XCTAssertEqual(choose(preset, ladder), .unchanged, what)
            }
        }
        let blankBesideGentle = Escalation(tier2: PanelAlert(), tier4: FinalAlert(action: .shortcut(name: " ")))
        XCTAssertEqual(EscalationEditing.shown(for: blankBesideGentle), .preset(.gentle),
                       "a blank Shortcut name beside Gentle is Gentle: tier 4 is ignored, and the problem is reported elsewhere")
    }

    // MARK: - What a preset repeats

    func testAPresetRepeatsTheFirstAlertsSoundAtItsGain() {
        let loud = AlertAction.sound(name: "Hero", gainDB: 6)
        XCTAssertEqual(repeatAction(edit(choose(.onCall, nil, alert: loud))), loud)
        XCTAssertEqual(repeatAction(edit(choose(.wakeMe, nil, alert: .sound(name: "Glass", gainDB: -3)))),
                       .sound(name: "Glass", gainDB: -3))
    }

    func testASoundWithSpeechRepeatsTheSoundAloneSoASentenceIsNotReadOutTwentyTimes() {
        XCTAssertEqual(repeatAction(edit(choose(.onCall, nil, alert: heroAndSpeech))), .sound(name: "Hero", gainDB: 6))
    }

    func testSpeechAloneRepeatsTheSameSpeech() {
        XCTAssertEqual(repeatAction(edit(choose(.onCall, nil, alert: spoken))), spoken)
    }

    func testASilentFirstAlertRepeatsTheDefaultSoundAtZero() {
        XCTAssertEqual(repeatAction(edit(choose(.onCall, nil, alert: .silent))), .sound(name: "Glass", gainDB: 0))
        XCTAssertEqual(repeatAction(edit(choose(.gentle, onCall(), alert: .silent))), nil, "Gentle repeats nothing")
        XCTAssertEqual(edit(choose(.gentle, onCall(), alert: .silent)).setAside.tier3?.action, hero)
    }

    func testACurrentOrSetAsideRepeatActionWinsOverAllFourFirstAlerts() {
        for first in [AlertAction.silent, glass, spoken, heroAndSpeech] {
            let current = onCall(spoken)
            XCTAssertEqual(repeatAction(edit(choose(.wakeMe, current, alert: first))), spoken, "current over \(first)")

            var aside = SetAside()
            aside.tier3 = RepeatAlert(action: hero)
            XCTAssertEqual(repeatAction(edit(choose(.onCall, nil, aside: aside, alert: first))), hero, "set aside over \(first)")
        }
        var aside = SetAside()
        aside.tier3 = RepeatAlert(action: glass)
        XCTAssertEqual(repeatAction(edit(choose(.wakeMe, onCall(spoken), aside: aside))), spoken, "current over set aside")
    }

    func testASilentRepeatIsIgnoredSoAPresetChosenOverItGivesARuleTheLoaderAccepts() {
        let silentRepeat = Escalation(tier2: PanelAlert(delaySeconds: 20),
                                      tier3: RepeatAlert(action: .silent, intervalSeconds: 40))
        XCTAssertFalse(RuleSetCodec.problems(in: rule(alert: hero, silentRepeat)).isEmpty, "the loader refuses it")
        let result = edit(choose(.onCall, silentRepeat))
        XCTAssertEqual(repeatAction(result), hero, "derived from the first alert")
        XCTAssertEqual(RuleSetCodec.problems(in: rule(alert: hero, result.escalation)), [])
        XCTAssertEqual(EscalationEditing.shown(for: result.escalation), .preset(.onCall), "and the picker is not left on Custom")

        var aside = SetAside()
        aside.tier3 = RepeatAlert(action: .silent)
        let fromAside = edit(choose(.onCall, nil, aside: aside))
        XCTAssertEqual(repeatAction(fromAside), hero, "a silent set-aside repeat is ignored too")
        XCTAssertEqual(RuleSetCodec.problems(in: rule(alert: hero, fromAside.escalation)), [])
    }

    func testAPresetOverASilentTier4LeavesItAsItFoundItAndNeverRestoresASilentSetAsideAction() {
        let silentFinal = FinalAlert(action: .alert(.silent))
        var ladder = Preset.gentle.ladder(repeating: hero)!
        ladder.tier4 = silentFinal
        XCTAssertEqual(edit(choose(.onCall, ladder)).escalation?.tier4, silentFinal,
                       "a preset owns tiers 2 and 3 and leaves tier 4 for the editor to report")

        var aside = SetAside()
        aside.tier4 = silentFinal
        XCTAssertNil(edit(choose(.onCall, nil, aside: aside)).escalation?.tier4, "never restored")
        aside.tier4 = FinalAlert(action: .shortcut(name: "  "))
        XCTAssertNil(edit(choose(.onCall, nil, aside: aside)).escalation?.tier4, "nor a blank Shortcut name")
    }

    func testSwitchingOnTier4OverASilentSetAsideAlertStartsFromTheDerivedOne() {
        var aside = SetAside()
        aside.tier4 = FinalAlert(action: .alert(.silent))
        aside.finalAlert = .silent
        let result = EscalationEditing.settingTier4(true, in: Escalation(tier2: PanelAlert()), setAside: aside,
                                                    firstAlert: spoken, defaultSound: "Glass")
        XCTAssertEqual(result.escalation?.tier4, FinalAlert(action: .alert(spoken)))
        XCTAssertEqual(RuleSetCodec.problems(in: rule(alert: spoken, result.escalation)), [])
    }

    // MARK: - What Off does

    func testOffOverABarePresetIsDoneAtOnceAndComesBackWithAPreset() {
        let result = edit(choose(.off, onCall()))
        XCTAssertNil(result.escalation)
        XCTAssertEqual(result.setAside.tier2, PanelAlert())
        XCTAssertEqual(result.setAside.tier3, RepeatAlert(action: hero))
        XCTAssertNil(result.setAside.custom, "a preset is brought back by choosing it, so it is not Custom")
        XCTAssertEqual(edit(choose(.onCall, nil, aside: result.setAside)).escalation, onCall())
    }

    func testOffOverACustomLadderWithNoShortcutIsDoneAtOnceAndCustomBringsItBack() {
        let custom = Escalation(tier2: PanelAlert(delaySeconds: 17), tier3: RepeatAlert(action: spoken, intervalSeconds: 45),
                                tier4: FinalAlert(afterSeconds: 90, action: .alert(glass)))
        let result = edit(choose(.off, custom))
        XCTAssertNil(result.escalation)
        XCTAssertEqual(result.setAside.custom, custom)
        XCTAssertEqual(edit(EscalationEditing.chooseCustom(escalation: nil, setAside: result.setAside)).escalation, custom)
        XCTAssertTrue(EditorText.offSentence(setAside: result.setAside).contains(EditorText.customName),
                      "and the sentence says so")
    }

    func testOffOverALadderWithAShortcutAsksAndChangesNothing() {
        for (what, ladder) in [("a preset", onCall(tier4: page)),
                               ("a custom ladder", Escalation(tier2: PanelAlert(delaySeconds: 17), tier4: page)),
                               ("tier 4 alone", Escalation(tier4: page))] {
            XCTAssertEqual(choose(.off, ladder), .needsConfirmation(shortcutName: "Page me"), what)
        }
        XCTAssertEqual(choose(.off, Escalation(tier2: PanelAlert(), tier4: FinalAlert(action: .shortcut(name: "")))),
                       .needsConfirmation(shortcutName: ""), "even a blank name asks: it is a Shortcut")
    }

    func testKeepChangesNothing() {
        var aside = SetAside()
        aside.custom = Escalation(tier2: PanelAlert(delaySeconds: 3))
        let ladder = onCall(tier4: page)
        let kept = EscalationEditing.answeringOff(.keep, escalation: ladder, setAside: aside)
        XCTAssertEqual(kept, EscalationEditing.Edit(escalation: ladder, setAside: aside))
    }

    func testRemoveThenCustomRestoresTheWholeLadderTheShortcutsNameIncluded() {
        let ladder = onCall(tier4: page)
        let removed = EscalationEditing.answeringOff(.remove, escalation: ladder, setAside: SetAside())
        XCTAssertNil(removed.escalation)
        XCTAssertEqual(removed.setAside.custom, ladder, "the whole ladder, as the Custom ladder")
        let back = edit(EscalationEditing.chooseCustom(escalation: removed.escalation, setAside: removed.setAside))
        XCTAssertEqual(back.escalation, ladder)
        XCTAssertEqual(back.escalation?.tier4?.action.shortcutName, "Page me")
        // And a preset, chosen instead, brings the Shortcut back too.
        XCTAssertEqual(edit(choose(.onCall, nil, aside: removed.setAside)).escalation, ladder)
    }

    func testOffOverNothingChangesNothingAndOverAnEmptyLadderLeavesNothingToBringBack() {
        XCTAssertEqual(choose(.off, nil), .unchanged)
        let result = edit(choose(.off, Escalation()))
        XCTAssertNil(result.escalation)
        XCTAssertEqual(result.setAside, SetAside(), "an empty ladder has nothing to restore")
    }

    func testOffKeepsWhatWasAlreadySetAsideWhenALadderHasNoSuchTier() {
        // A tier that is absent does not clear its slot: Custom survives a trip
        // through a preset and Off.
        let custom = Escalation(tier2: PanelAlert(delaySeconds: 17), tier4: FinalAlert(action: .alert(glass)))
        let preset = edit(choose(.onCall, custom))
        let off = edit(choose(.off, preset.escalation, aside: preset.setAside))
        XCTAssertEqual(off.setAside.custom, custom, "Off over a preset does not displace the custom ladder")
        XCTAssertEqual(edit(EscalationEditing.chooseCustom(escalation: nil, setAside: off.setAside)).escalation, custom)
    }

    // MARK: - Tiers

    func testEachTierOffAndOnRestoresTheWholeValue() {
        let ladder = Escalation(tier2: PanelAlert(delaySeconds: 17),
                                tier3: RepeatAlert(action: spoken, intervalSeconds: 45, maxRepeats: 3, maxDurationSeconds: 90),
                                tier4: FinalAlert(afterSeconds: 200, action: .shortcut(name: "Page me")))

        let two = EscalationEditing.settingTier2(false, in: ladder, setAside: SetAside())
        XCTAssertNil(two.escalation?.tier2)
        XCTAssertEqual(two.escalation?.tier3, ladder.tier3, "only tier 2 went")
        XCTAssertEqual(two.escalation?.tier4, ladder.tier4)
        XCTAssertEqual(EscalationEditing.settingTier2(true, in: two.escalation, setAside: two.setAside).escalation, ladder)

        let three = EscalationEditing.settingTier3(false, in: ladder, setAside: SetAside(), firstAlert: hero, defaultSound: "Glass")
        XCTAssertNil(three.escalation?.tier3)
        XCTAssertEqual(three.escalation?.tier2, ladder.tier2)
        XCTAssertEqual(EscalationEditing.settingTier3(true, in: three.escalation, setAside: three.setAside, firstAlert: hero,
                                                      defaultSound: "Glass").escalation, ladder, "whole: action, interval and both limits")

        let four = EscalationEditing.settingTier4(false, in: ladder, setAside: SetAside(), firstAlert: hero, defaultSound: "Glass")
        XCTAssertNil(four.escalation?.tier4)
        XCTAssertEqual(four.escalation?.tier3, ladder.tier3)
        XCTAssertEqual(EscalationEditing.settingTier4(true, in: four.escalation, setAside: four.setAside, firstAlert: hero,
                                                      defaultSound: "Glass").escalation, ladder, "the Shortcut's name too")
    }

    func testSwitchingATierThatIsAlreadyInTheStateAskedForChangesNothing() {
        // Distinctive values, so that a tier rebuilt as a default would show.
        let ladder = Escalation(tier2: PanelAlert(delaySeconds: 17),
                                tier3: RepeatAlert(action: spoken, intervalSeconds: 45, maxRepeats: 3, maxDurationSeconds: 90),
                                tier4: FinalAlert(afterSeconds: 200, action: .shortcut(name: "Page me")))
        XCTAssertEqual(EscalationEditing.settingTier2(true, in: ladder, setAside: SetAside()).escalation, ladder)
        XCTAssertEqual(EscalationEditing.settingTier3(true, in: ladder, setAside: SetAside(), firstAlert: hero,
                                                      defaultSound: "Glass").escalation, ladder)
        XCTAssertEqual(EscalationEditing.settingTier4(true, in: ladder, setAside: SetAside(), firstAlert: hero,
                                                      defaultSound: "Glass").escalation, ladder)
        let bare = Escalation(tier2: PanelAlert())
        for edit in [EscalationEditing.settingTier3(false, in: bare, setAside: SetAside(), firstAlert: hero, defaultSound: "Glass"),
                     EscalationEditing.settingTier4(false, in: bare, setAside: SetAside(), firstAlert: hero, defaultSound: "Glass")] {
            XCTAssertEqual(edit, EscalationEditing.Edit(escalation: bare, setAside: SetAside()))
        }
    }

    func testEachLimitToNoLimitAndBackRestoresItsOwnNumberIndependently() {
        let ladder = Escalation(tier3: RepeatAlert(action: hero, intervalSeconds: 30, maxRepeats: 7, maxDurationSeconds: 123))
        func noLimit(_ on: Bool, _ limit: EscalationEditing.Limit, _ edit: EscalationEditing.Edit) -> EscalationEditing.Edit {
            EscalationEditing.settingNoLimit(on, on: limit, in: edit.escalation, setAside: edit.setAside)
        }
        let start = EscalationEditing.Edit(escalation: ladder, setAside: SetAside())

        let repeatsFree = noLimit(true, .repeats, start)
        XCTAssertNil(repeatsFree.escalation?.tier3?.maxRepeats)
        XCTAssertEqual(repeatsFree.escalation?.tier3?.maxDurationSeconds, 123, "the other limit is untouched")
        let bothFree = noLimit(true, .duration, repeatsFree)
        XCTAssertNil(bothFree.escalation?.tier3?.maxDurationSeconds)

        let durationBack = noLimit(false, .duration, bothFree)
        XCTAssertEqual(durationBack.escalation?.tier3?.maxDurationSeconds, 123, "its own number, not a default")
        XCTAssertNil(durationBack.escalation?.tier3?.maxRepeats, "and the repeats stay unlimited")
        let repeatsBack = noLimit(false, .repeats, durationBack)
        XCTAssertEqual(repeatsBack.escalation, ladder)

        // And in the other order, with the numbers edited in between.
        let edited = EscalationEditing.settingMaxRepeats(9, in: ladder)
        let free = noLimit(true, .repeats, EscalationEditing.Edit(escalation: edited, setAside: SetAside()))
        XCTAssertEqual(noLimit(false, .repeats, free).escalation?.tier3?.maxRepeats, 9, "the number as last edited")
    }

    func testAnUnlimitedRepeatWithNothingSetAsideComesBackAsTheDefaultLimit() {
        let free = Escalation(tier3: RepeatAlert(action: hero, maxRepeats: nil, maxDurationSeconds: nil))
        let repeats = EscalationEditing.settingNoLimit(false, on: .repeats, in: free, setAside: SetAside())
        XCTAssertEqual(repeats.escalation?.tier3?.maxRepeats, RepeatAlert.defaultMaxRepeats)
        XCTAssertNil(repeats.escalation?.tier3?.maxDurationSeconds)
        let duration = EscalationEditing.settingNoLimit(false, on: .duration, in: free, setAside: SetAside())
        XCTAssertEqual(duration.escalation?.tier3?.maxDurationSeconds, RepeatAlert.defaultMaxDurationSeconds)
        XCTAssertNil(duration.escalation?.tier3?.maxRepeats)
        // Asking for what is already so changes nothing.
        XCTAssertEqual(EscalationEditing.settingNoLimit(true, on: .repeats, in: free, setAside: SetAside()).escalation, free)
        let limited = Escalation(tier3: RepeatAlert(action: hero))
        XCTAssertEqual(EscalationEditing.settingNoLimit(false, on: .duration, in: limited, setAside: SetAside()).escalation, limited)
        XCTAssertEqual(EscalationEditing.settingNoLimit(true, on: .repeats, in: nil, setAside: SetAside()).escalation, nil)
    }

    func testTier4FromAlertToShortcutAndBackRestoresTheAlertAndBackAgainTheName() {
        let ladder = Escalation(tier2: PanelAlert(), tier4: FinalAlert(afterSeconds: 90, action: .alert(spoken)))
        func choose(_ kind: EscalationEditing.FinalKind, _ edit: EscalationEditing.Edit) -> EscalationEditing.Edit {
            EscalationEditing.choosingFinal(kind, in: edit.escalation, setAside: edit.setAside, firstAlert: hero, defaultSound: "Glass")
        }
        let start = EscalationEditing.Edit(escalation: ladder, setAside: SetAside())

        let shortcut = choose(.shortcut, start)
        XCTAssertEqual(shortcut.escalation?.tier4, FinalAlert(afterSeconds: 90, action: .shortcut(name: "")),
                       "the delay is kept, and the name is still to be typed")
        let named = EscalationEditing.Edit(
            escalation: EscalationEditing.settingShortcutName("Page me", in: shortcut.escalation), setAside: shortcut.setAside)
        let alert = choose(.alert, named)
        XCTAssertEqual(alert.escalation, ladder, "the alert as it was")
        let again = choose(.shortcut, alert)
        XCTAssertEqual(again.escalation?.tier4, FinalAlert(afterSeconds: 90, action: .shortcut(name: "Page me")),
                       "and back again, the name")
        XCTAssertEqual(choose(.shortcut, again), again, "asking for the kind it already is changes nothing")
        XCTAssertEqual(EscalationEditing.kind(of: .shortcut(name: "x")), .shortcut)
        XCTAssertEqual(EscalationEditing.kind(of: .alert(hero)), .alert)
    }

    func testChoosingAnAlertAfterAShortcutWithNothingSetAsideStartsAsAValidAlert() {
        let ladder = Escalation(tier3: RepeatAlert(action: spoken), tier4: page)
        let result = EscalationEditing.choosingFinal(.alert, in: ladder, setAside: SetAside(), firstAlert: hero, defaultSound: "Glass")
        XCTAssertEqual(result.escalation?.tier4?.action, .alert(spoken), "derived as a preset's repeat is: the repeat's action")
        XCTAssertEqual(result.setAside.shortcutName, "Page me")
        let silentFirst = EscalationEditing.choosingFinal(.alert, in: Escalation(tier4: page), setAside: SetAside(),
                                                          firstAlert: .silent, defaultSound: "Glass")
        XCTAssertEqual(silentFirst.escalation?.tier4?.action, .alert(.sound(name: "Glass", gainDB: 0)), "never silent")
        // A silent alert is not kept, and a blank name is not kept.
        let toShortcut = EscalationEditing.choosingFinal(.shortcut, in: Escalation(tier4: FinalAlert(action: .alert(.silent))),
                                                         setAside: SetAside(), firstAlert: hero, defaultSound: "Glass")
        XCTAssertNil(toShortcut.setAside.finalAlert)
        let blank = EscalationEditing.choosingFinal(.alert, in: Escalation(tier4: FinalAlert(action: .shortcut(name: " "))),
                                                    setAside: SetAside(), firstAlert: hero, defaultSound: "Glass")
        XCTAssertNil(blank.setAside.shortcutName)
    }

    func testSwitchingOnTier4StartsAsAValidAlertNeverSilentAndNeverABlankShortcutName() {
        func on(_ ladder: Escalation?, aside: SetAside = SetAside(), first: AlertAction?) -> FinalAlert? {
            EscalationEditing.settingTier4(true, in: ladder, setAside: aside, firstAlert: first, defaultSound: "Glass")
                .escalation?.tier4
        }
        XCTAssertEqual(on(nil, first: hero), FinalAlert(action: .alert(hero)))
        XCTAssertEqual(on(nil, first: .silent), FinalAlert(action: .alert(.sound(name: "Glass", gainDB: 0))))
        XCTAssertEqual(on(nil, first: heroAndSpeech), FinalAlert(action: .alert(.sound(name: "Hero", gainDB: 6))))
        XCTAssertEqual(on(nil, first: spoken), FinalAlert(action: .alert(spoken)))
        XCTAssertEqual(on(nil, first: nil), FinalAlert(action: .alert(.sound(name: "Glass", gainDB: 0))))
        XCTAssertEqual(on(onCall(spoken), first: hero), FinalAlert(action: .alert(spoken)), "the repeat's action, when there is one")

        var blank = SetAside()
        blank.tier4 = FinalAlert(action: .shortcut(name: ""))
        XCTAssertEqual(on(Escalation(tier2: PanelAlert()), aside: blank, first: hero), FinalAlert(action: .alert(hero)))
        var kept = SetAside()
        kept.finalAlert = glass
        XCTAssertEqual(on(Escalation(tier2: PanelAlert()), aside: kept, first: hero), FinalAlert(action: .alert(glass)),
                       "an alert the user had is kept over a derived one")
    }

    func testSwitchingOnTier3StartsAsTheDerivedActionAtTheDefaultTimings() {
        func on(aside: SetAside = SetAside(), first: AlertAction?) -> RepeatAlert? {
            EscalationEditing.settingTier3(true, in: nil, setAside: aside, firstAlert: first, defaultSound: "Glass").escalation?.tier3
        }
        XCTAssertEqual(on(first: heroAndSpeech), RepeatAlert(action: .sound(name: "Hero", gainDB: 6)))
        XCTAssertEqual(on(first: .silent), RepeatAlert(action: .sound(name: "Glass", gainDB: 0)))
        var silentAside = SetAside()
        silentAside.tier3 = RepeatAlert(action: .silent, intervalSeconds: 5)
        XCTAssertEqual(on(aside: silentAside, first: hero), RepeatAlert(action: hero), "a silent set-aside repeat counts as absent")
    }

    func testTheLastTierOffGivesNilAndTheFirstOnBuildsOnlyThatTier() {
        let only = Escalation(tier3: RepeatAlert(action: hero))
        let off = EscalationEditing.settingTier3(false, in: only, setAside: SetAside(), firstAlert: hero, defaultSound: "Glass")
        XCTAssertNil(off.escalation, "no tier left is Off")
        XCTAssertEqual(off.setAside.tier3, RepeatAlert(action: hero))
        XCTAssertNil(EscalationEditing.settingTier2(false, in: Escalation(tier2: PanelAlert()), setAside: SetAside()).escalation)
        XCTAssertNil(EscalationEditing.settingTier4(false, in: Escalation(tier4: page), setAside: SetAside(), firstAlert: hero,
                                                    defaultSound: "Glass").escalation)

        XCTAssertEqual(EscalationEditing.settingTier2(true, in: nil, setAside: SetAside()).escalation,
                       Escalation(tier2: PanelAlert()))
        XCTAssertEqual(EscalationEditing.settingTier3(true, in: nil, setAside: SetAside(), firstAlert: hero,
                                                      defaultSound: "Glass").escalation,
                       Escalation(tier3: RepeatAlert(action: hero)))
        XCTAssertEqual(EscalationEditing.settingTier4(true, in: nil, setAside: SetAside(), firstAlert: hero,
                                                      defaultSound: "Glass").escalation,
                       Escalation(tier4: FinalAlert(action: .alert(hero))))
    }

    func testAHandWrittenEmptyLadderIsUntouchedUntilEdited() {
        let empty = Escalation()
        XCTAssertEqual(EscalationEditing.shown(for: empty), .custom)
        XCTAssertEqual(EscalationEditing.settingTier2(false, in: empty, setAside: SetAside()).escalation, empty)
        XCTAssertEqual(EscalationEditing.settingTier3(false, in: empty, setAside: SetAside(), firstAlert: hero,
                                                      defaultSound: "Glass").escalation, empty)
        XCTAssertEqual(EscalationEditing.settingTier4(false, in: empty, setAside: SetAside(), firstAlert: hero,
                                                      defaultSound: "Glass").escalation, empty)
        XCTAssertEqual(EscalationEditing.settingDelay(5, in: empty), empty)
        XCTAssertEqual(EscalationEditing.settingInterval(5, in: empty), empty)
        XCTAssertEqual(EscalationEditing.settingFinalDelay(5, in: empty), empty)
        XCTAssertEqual(EscalationEditing.settingShortcutName("x", in: empty), empty)
        XCTAssertEqual(EscalationEditing.settingTier2(true, in: empty, setAside: SetAside()).escalation,
                       Escalation(tier2: PanelAlert()), "edited, it has the one tier switched on")
    }

    // MARK: Values

    func testSettersClampNewValuesToOneSecondOrOneRepeat() {
        let ladder = Escalation(tier2: PanelAlert(), tier3: RepeatAlert(action: hero), tier4: FinalAlert(action: .alert(hero)))
        for bad in [0, -5, 0.4, Double.nan, -Double.infinity] {
            XCTAssertEqual(EscalationEditing.settingDelay(bad, in: ladder)?.tier2?.delaySeconds, 1, "delay \(bad)")
            XCTAssertEqual(EscalationEditing.settingInterval(bad, in: ladder)?.tier3?.intervalSeconds, 1, "interval \(bad)")
            XCTAssertEqual(EscalationEditing.settingMaxDuration(bad, in: ladder)?.tier3?.maxDurationSeconds, 1, "limit \(bad)")
            XCTAssertEqual(EscalationEditing.settingFinalDelay(bad, in: ladder)?.tier4?.afterSeconds, 1, "tier 4 delay \(bad)")
        }
        for bad in [0, -1, Int.min] {
            XCTAssertEqual(EscalationEditing.settingMaxRepeats(bad, in: ladder)?.tier3?.maxRepeats, 1, "repeats \(bad)")
        }
        XCTAssertEqual(EscalationEditing.settingDelay(1, in: ladder)?.tier2?.delaySeconds, 1, "one second is allowed")
        XCTAssertEqual(EscalationEditing.settingDelay(2.5, in: ladder)?.tier2?.delaySeconds, 2.5, "so is a fraction above it")
        XCTAssertEqual(EscalationEditing.settingMaxRepeats(1, in: ladder)?.tier3?.maxRepeats, 1)
        XCTAssertEqual(EscalationEditing.settingMaxRepeats(50, in: ladder)?.tier3?.maxRepeats, 50)
        // A file cannot hold infinity, so a control never writes one.
        let huge = EscalationEditing.settingDelay(.infinity, in: ladder)
        XCTAssertEqual(huge?.tier2?.delaySeconds, Double.greatestFiniteMagnitude)
        XCTAssertNoThrow(try RuleSetCodec.encode([rule(alert: hero, huge)]))
        XCTAssertEqual(EscalationEditing.clampedSeconds(.nan), 1)
        XCTAssertEqual(EscalationEditing.clampedRepeats(-3), 1)
    }

    func testAValueTypedOverNoLimitIsClampedLikeAnyOther() {
        // Wake me has neither limit. Typing into a limit that was "no limit"
        // writes a number the file can hold, and never the 0 or the negative
        // that the loader refuses, which would switch the whole rule off.
        let unlimited = Preset.wakeMe.ladder(repeating: hero)
        XCTAssertNil(unlimited?.tier3?.maxDurationSeconds)
        XCTAssertNil(unlimited?.tier3?.maxRepeats)
        for bad in [0, -5, 0.4, Double.nan, -Double.infinity] {
            let typed = EscalationEditing.settingMaxDuration(bad, in: unlimited)
            XCTAssertEqual(typed?.tier3?.maxDurationSeconds, 1, "a time limit of \(bad)")
            XCTAssertEqual(RuleSetCodec.problems(in: rule(alert: hero, typed)), [], "\(bad)")
        }
        XCTAssertEqual(EscalationEditing.settingMaxDuration(.infinity, in: unlimited)?.tier3?.maxDurationSeconds,
                       Double.greatestFiniteMagnitude, "a file cannot hold infinity")
        for bad in [0, -1, Int.min] {
            let typed = EscalationEditing.settingMaxRepeats(bad, in: unlimited)
            XCTAssertEqual(typed?.tier3?.maxRepeats, 1, "a repeat limit of \(bad)")
            XCTAssertEqual(RuleSetCodec.problems(in: rule(alert: hero, typed)), [], "\(bad)")
        }
        // A number that needs no clamping is written as typed, and only into
        // the limit that was typed in.
        let timed = EscalationEditing.settingMaxDuration(90, in: unlimited)
        XCTAssertEqual(timed?.tier3?.maxDurationSeconds, 90)
        XCTAssertNil(timed?.tier3?.maxRepeats, "the other limit stays as no limit")
        let counted = EscalationEditing.settingMaxRepeats(3, in: unlimited)
        XCTAssertEqual(counted?.tier3?.maxRepeats, 3)
        XCTAssertNil(counted?.tier3?.maxDurationSeconds)
        XCTAssertEqual(EscalationEditing.settingMaxDuration(1, in: unlimited)?.tier3?.maxDurationSeconds, 1,
                       "one second is allowed")
        XCTAssertEqual(EscalationEditing.settingMaxDuration(2.5, in: unlimited)?.tier3?.maxDurationSeconds, 2.5)
    }

    func testAValueNobodyEditedIsNeverRewritten() {
        // Hand-written, and out of range for what the controls write.
        let odd = Escalation(tier2: PanelAlert(delaySeconds: 0), tier3: RepeatAlert(action: hero, intervalSeconds: -5,
                                                                                     maxRepeats: 0, maxDurationSeconds: 0.5),
                             tier4: FinalAlert(afterSeconds: 0.25, action: .alert(hero)))
        XCTAssertEqual(EscalationEditing.settingDelay(0, in: odd), odd, "set to what it already is")
        XCTAssertEqual(EscalationEditing.settingInterval(-5, in: odd), odd)
        XCTAssertEqual(EscalationEditing.settingMaxRepeats(0, in: odd), odd)
        XCTAssertEqual(EscalationEditing.settingMaxDuration(0.5, in: odd), odd)
        XCTAssertEqual(EscalationEditing.settingFinalDelay(0.25, in: odd), odd)
        // And editing one of them leaves the others as they were, odd or not.
        XCTAssertEqual(EscalationEditing.settingDelay(20, in: odd)?.tier3, odd.tier3)
        XCTAssertEqual(EscalationEditing.settingDelay(20, in: odd)?.tier4, odd.tier4)
    }

    /// `ladder` with one field put back, so that what a control changed is
    /// exactly that field.
    private func restoring(_ result: Escalation?, from original: Escalation,
                           _ put: (inout Escalation, Escalation) -> Void) -> Escalation? {
        guard var changed = result else { return nil }
        put(&changed, original)
        return changed
    }

    func testEachSetterChangesOnlyItsOwnFieldInEveryOddLadder() throws {
        let ladders = oddLadders().map(\.1) + [
            Escalation(tier2: PanelAlert(delaySeconds: 0), tier3: RepeatAlert(action: .silent, intervalSeconds: -5, maxRepeats: -1,
                                                                               maxDurationSeconds: 1e300),
                       tier4: FinalAlert(afterSeconds: 1e300, action: .shortcut(name: ""))),
            Escalation(tier2: PanelAlert(delaySeconds: 3.5), tier3: RepeatAlert(action: spoken, maxRepeats: nil, maxDurationSeconds: nil),
                       tier4: FinalAlert(afterSeconds: -2, action: .alert(.silent))),
        ]
        for original in ladders {
            let tag = "\(original)"
            XCTAssertEqual(restoring(EscalationEditing.settingDelay(33, in: original), from: original) { $0.tier2 = $1.tier2 },
                           original, "delay: \(tag)")
            XCTAssertEqual(restoring(EscalationEditing.settingInterval(33, in: original), from: original) { $0.tier3?.intervalSeconds = $1.tier3?.intervalSeconds ?? 0 },
                           original, "interval: \(tag)")
            XCTAssertEqual(restoring(EscalationEditing.settingMaxRepeats(33, in: original), from: original) { $0.tier3?.maxRepeats = $1.tier3?.maxRepeats },
                           original, "max repeats: \(tag)")
            XCTAssertEqual(restoring(EscalationEditing.settingMaxDuration(33, in: original), from: original) { $0.tier3?.maxDurationSeconds = $1.tier3?.maxDurationSeconds },
                           original, "max duration: \(tag)")
            XCTAssertEqual(restoring(EscalationEditing.settingRepeatAction(glass, in: original), from: original) { $0.tier3?.action = $1.tier3?.action ?? .silent },
                           original, "repeat action: \(tag)")
            XCTAssertEqual(restoring(EscalationEditing.settingFinalDelay(33, in: original), from: original) { $0.tier4?.afterSeconds = $1.tier4?.afterSeconds ?? 0 },
                           original, "tier 4 delay: \(tag)")
            XCTAssertEqual(restoring(EscalationEditing.settingFinalAlert(glass, in: original), from: original) { $0.tier4?.action = $1.tier4?.action ?? .alert(.silent) },
                           original, "tier 4 alert: \(tag)")
            XCTAssertEqual(restoring(EscalationEditing.settingShortcutName("Page me", in: original), from: original) { $0.tier4?.action = $1.tier4?.action ?? .alert(.silent) },
                           original, "Shortcut name: \(tag)")
            for limit in [EscalationEditing.Limit.repeats, .duration] {
                for noLimit in [true, false] {
                    let result = EscalationEditing.settingNoLimit(noLimit, on: limit, in: original, setAside: SetAside())
                    let other = restoring(result.escalation, from: original) {
                        switch limit {
                        case .repeats: $0.tier3?.maxRepeats = $1.tier3?.maxRepeats
                        case .duration: $0.tier3?.maxDurationSeconds = $1.tier3?.maxDurationSeconds
                        }
                    }
                    XCTAssertEqual(other, original, "no limit \(noLimit) on \(limit): \(tag)")
                }
            }
        }
    }

    func testASetterSetsItsFieldAndAFieldOutsideItsTierChangesNothing() {
        let ladder = Escalation(tier2: PanelAlert(), tier3: RepeatAlert(action: hero), tier4: FinalAlert(action: .alert(hero)))
        XCTAssertEqual(EscalationEditing.settingDelay(33, in: ladder)?.tier2?.delaySeconds, 33)
        XCTAssertEqual(EscalationEditing.settingInterval(33, in: ladder)?.tier3?.intervalSeconds, 33)
        XCTAssertEqual(EscalationEditing.settingMaxRepeats(33, in: ladder)?.tier3?.maxRepeats, 33)
        XCTAssertEqual(EscalationEditing.settingMaxDuration(33, in: ladder)?.tier3?.maxDurationSeconds, 33)
        XCTAssertEqual(EscalationEditing.settingRepeatAction(glass, in: ladder)?.tier3?.action, glass)
        XCTAssertEqual(EscalationEditing.settingFinalDelay(33, in: ladder)?.tier4?.afterSeconds, 33)
        XCTAssertEqual(EscalationEditing.settingFinalAlert(spoken, in: ladder)?.tier4?.action, .alert(spoken))
        XCTAssertEqual(EscalationEditing.settingShortcutName("x", in: ladder), ladder, "tier 4 is an alert, not a Shortcut")
        let shortcut = Escalation(tier4: page)
        XCTAssertEqual(EscalationEditing.settingShortcutName("Other", in: shortcut)?.tier4?.action, .shortcut(name: "Other"))
        XCTAssertEqual(EscalationEditing.settingFinalAlert(glass, in: shortcut), shortcut, "tier 4 is a Shortcut, not an alert")
        XCTAssertEqual(EscalationEditing.settingShortcutName("", in: shortcut)?.tier4?.action, .shortcut(name: ""),
                       "a blank name is typed, and reported as a problem, not refused")
        XCTAssertNil(EscalationEditing.settingDelay(33, in: nil))
        XCTAssertEqual(EscalationEditing.settingMaxDuration(33, in: Escalation(tier3: RepeatAlert(action: hero, maxDurationSeconds: nil)))?
            .tier3?.maxDurationSeconds, 33, "typing a number asks for the limit")
    }

    func testTheSetAsideValuesAreIndependent() {
        var aside = SetAside()
        aside.tier3Alert = AlertEditing.SetAside(speech: SpeechAction(voiceIdentifier: daniel))
        XCTAssertEqual(aside.tier4Alert, AlertEditing.SetAside(), "tier 4's does not see tier 3's")
        aside.tier4Alert = AlertEditing.SetAside(sound: ("Hero", 6))
        XCTAssertNil(aside.tier3Alert.sound, "and tier 3's does not see tier 4's")
        XCTAssertNotEqual(aside.tier3Alert, aside.tier4Alert)
        // The limits, the alert and the name each have a slot of their own.
        aside.maxRepeats = 7
        XCTAssertNil(aside.maxDurationSeconds)
        aside.maxDurationSeconds = 90
        aside.finalAlert = glass
        aside.shortcutName = "Page me"
        XCTAssertEqual(aside.maxRepeats, 7)
        XCTAssertNil(aside.tier2)
        XCTAssertFalse(aside.holdsLadder)
        aside.tier3 = RepeatAlert(action: hero)
        XCTAssertTrue(aside.holdsLadder)
    }

    func testGoingOnAndOffThroughTheEditorKeepsTheLimitsAndOnlyThem() {
        // Tier 3 off and on, with a limit ticked to "no limit" in between,
        // restores the tier as it was left, not as it was first written.
        let ladder = Escalation(tier3: RepeatAlert(action: hero, intervalSeconds: 30, maxRepeats: 5, maxDurationSeconds: 60))
        let free = EscalationEditing.settingNoLimit(true, on: .duration, in: ladder, setAside: SetAside())
        let off = EscalationEditing.settingTier3(false, in: free.escalation, setAside: free.setAside, firstAlert: hero,
                                                 defaultSound: "Glass")
        let on = EscalationEditing.settingTier3(true, in: off.escalation, setAside: off.setAside, firstAlert: hero,
                                                defaultSound: "Glass")
        XCTAssertEqual(on.escalation?.tier3, RepeatAlert(action: hero, intervalSeconds: 30, maxRepeats: 5, maxDurationSeconds: nil))
        let limited = EscalationEditing.settingNoLimit(false, on: .duration, in: on.escalation, setAside: on.setAside)
        XCTAssertEqual(limited.escalation?.tier3?.maxDurationSeconds, 60, "the number is still there")
    }

    func testTypedNumbersParseOnlyWhenTheyAreNumbers() {
        XCTAssertEqual(EscalationEditing.parseSeconds("30"), 30)
        XCTAssertEqual(EscalationEditing.parseSeconds(" 2.5 "), 2.5)
        XCTAssertEqual(EscalationEditing.parseSeconds("-3"), -3, "parsed as typed; the setter clamps")
        for text in ["", " ", "abc", "1,5", "nan", "inf", "-inf", "1e999"] {
            XCTAssertNil(EscalationEditing.parseSeconds(text), "\"\(text)\" writes nothing")
        }
        XCTAssertEqual(EscalationEditing.parseCount("20"), 20)
        XCTAssertEqual(EscalationEditing.parseCount(" 7\n"), 7)
        for text in ["", "2.5", "x", "9999999999999999999999"] {
            XCTAssertNil(EscalationEditing.parseCount(text), "\"\(text)\" writes nothing")
        }
    }
}
