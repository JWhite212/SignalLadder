import XCTest
@testable import NotificationCore

/// What the app says it did about a match. The wording is the product here:
/// it must never let "played" stand for "heard", or silence stand for a
/// decision nobody made.
final class AlertOutcomeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_757_000_000)

    // MARK: - Row wording

    func testPlayedNamesTheSoundAndOnlyANonDefaultGain() {
        XCTAssertEqual(InspectorRowText.alert(.played(sound: "Glass", gainDB: 0, outputSilent: false)), "Played Glass")
        XCTAssertEqual(InspectorRowText.alert(.played(sound: "Glass", gainDB: 6, outputSilent: false)), "Played Glass (+6 dB)")
        XCTAssertEqual(InspectorRowText.alert(.played(sound: "Glass", gainDB: -3.5, outputSilent: false)), "Played Glass (−3.5 dB)")
        XCTAssertEqual(InspectorRowText.alert(.played(sound: "Glass", gainDB: -40, outputSilent: false)), "Played Glass (−40 dB)")
        XCTAssertEqual(InspectorRowText.alert(.played(sound: "Glass", gainDB: -0.0, outputSilent: false)), "Played Glass",
                       "negative zero is still the default")
    }

    func testPlayedIntoASilentOutputSaysSoRatherThanImplyingItWasHeard() {
        XCTAssertEqual(InspectorRowText.alert(.played(sound: "Glass", gainDB: 6, outputSilent: true)),
                       "Played Glass (+6 dB) — but the Mac's sound output was muted or at zero volume")
    }

    // MARK: - Spoken alerts

    func testSpokenAlertsNameTheVoiceAndOnlyANonDefaultGain() {
        XCTAssertEqual(InspectorRowText.alert(.spoke(text: "Teams: hi", voice: "Daniel", gainDB: 0, outputSilent: false)),
                       "Spoke (Daniel)")
        XCTAssertEqual(InspectorRowText.alert(.spoke(text: "Teams: hi", voice: "Daniel", gainDB: -3, outputSilent: false)),
                       "Spoke (Daniel, −3 dB)")
        XCTAssertEqual(InspectorRowText.alert(.playedAndSpoke(sound: "Glass", soundGainDB: 6, text: "Teams: hi", voice: "Daniel",
                                                              speechGainDB: 0, outputSilent: false)),
                       "Played Glass (+6 dB) and spoke (Daniel)")
    }

    func testEachPartialFailureSaysWhichHalfFailed() {
        XCTAssertEqual(InspectorRowText.alert(.couldNotSpeak("voice \"x\" is not installed")),
                       "Could not speak: voice \"x\" is not installed")
        XCTAssertEqual(InspectorRowText.alert(.playedButNotSpoken(sound: "Glass", gainDB: 0, reason: "voice \"x\" is not installed", outputSilent: false)),
                       "Played Glass, but could not speak: voice \"x\" is not installed")
        XCTAssertEqual(InspectorRowText.alert(.spokeButNotPlayed(text: "hi", voice: "Daniel", gainDB: 0, reason: "sound \"Glas\" was not found", outputSilent: false)),
                       "Spoke (Daniel), but could not play: sound \"Glas\" was not found")
    }

    func testSpokenIntoASilentOutputSaysSo() {
        XCTAssertEqual(InspectorRowText.alert(.spoke(text: "hi", voice: "Daniel", gainDB: 0, outputSilent: true)),
                       "Spoke (Daniel) — but the Mac's sound output was muted or at zero volume")
    }

    func testTheRowAndMenuWordingNeverIncludeWhatWasSpoken() {
        // The menu is seen at a glance, in meetings, on shared screens.
        let said = "Priya: the payments database password is in the vault"
        let outcomes: [AlertOutcome] = [
            .spoke(text: said, voice: "Daniel", gainDB: 0, outputSilent: false),
            .spoke(text: said, voice: "Daniel", gainDB: 0, outputSilent: true),
            .playedAndSpoke(sound: "Glass", soundGainDB: 0, text: said, voice: "Daniel", speechGainDB: 0, outputSilent: false),
            .spokeButNotPlayed(text: said, voice: "Daniel", gainDB: 0, reason: "x", outputSilent: false),
        ]
        for outcome in outcomes {
            XCTAssertFalse(InspectorRowText.alert(outcome).contains("payments"), InspectorRowText.alert(outcome))
            let menu = AlertMenuText.lines(lastMatch: .init(ruleName: "R", at: t0, alert: outcome),
                                           unresolvedFailure: .init(ruleName: "R", at: t0, alert: outcome),
                                           anyRulePlaysSound: true, outputSilent: false, time: { _ in "09:00" })
            XCTAssertFalse(menu.joined().contains("payments"), menu.joined())
            XCTAssertEqual(outcome.spokenText, said, "the Inspector can still show it")
        }
    }

    func testSpeechThatCouldNotBeHeardNeedsAttention() {
        XCTAssertTrue(AlertOutcome.couldNotSpeak("x").needsAttention)
        XCTAssertTrue(AlertOutcome.playedButNotSpoken(sound: "Glass", gainDB: 0, reason: "x", outputSilent: false).needsAttention)
        XCTAssertTrue(AlertOutcome.spokeButNotPlayed(text: "x", voice: "D", gainDB: 0, reason: "x", outputSilent: false).needsAttention)
        XCTAssertTrue(AlertOutcome.spoke(text: "x", voice: "D", gainDB: 0, outputSilent: true).needsAttention)
        XCTAssertFalse(AlertOutcome.spoke(text: "x", voice: "D", gainDB: 0, outputSilent: false).needsAttention)
        XCTAssertFalse(AlertOutcome.playedAndSpoke(sound: "G", soundGainDB: 0, text: "x", voice: "D", speechGainDB: 0,
                                                   outputSilent: false).needsAttention)
    }

    func testNoAlertAndSilentByRuleReadDifferently() {
        XCTAssertEqual(InspectorRowText.alert(.silentByRule), "Silent by rule")
        XCTAssertEqual(InspectorRowText.alert(.noAlertSet), "Silent — this rule has no alert")
    }

    func testAMatchASnoozeHeldSaysSoNeedsNoAttentionAndSaidNothing() {
        XCTAssertEqual(InspectorRowText.alert(.snoozed), "Snoozed — no alert")
        XCTAssertFalse(AlertOutcome.snoozed.needsAttention, "the snooze doing what it was asked is not a problem")
        XCTAssertNil(AlertOutcome.snoozed.spokenText, "nothing was said")
    }

    func testAFailureSaysWhy() {
        XCTAssertEqual(InspectorRowText.alert(.failed("sound \"Glas\" was not found")),
                       "Could not play: sound \"Glas\" was not found")
    }

    func testARowWithNoOutcomeHasNoAlertLine() {
        let row = InspectorEntry(captured: CapturedNotification(timestamp: t0, appNameGuess: "Teams", title: "t",
                                                                subtitle: "", body: "b", rawText: "Teams, t, b",
                                                                subrole: "AXNotificationCenterBanner"),
                                 context: ContextSnapshot(date: t0, recentCountForApp: 1),
                                 suppressedRepeatCount: 0, annotation: nil, preview: nil)
        XCTAssertNil(InspectorRowText.alert(row))
    }

    // MARK: - What needs attention

    func testOnlyAFailureOrAnUnheardSoundNeedsAttention() {
        XCTAssertTrue(AlertOutcome.failed("x").needsAttention)
        XCTAssertTrue(AlertOutcome.played(sound: "Glass", gainDB: 0, outputSilent: true).needsAttention)
        XCTAssertFalse(AlertOutcome.played(sound: "Glass", gainDB: 0, outputSilent: false).needsAttention)
        XCTAssertFalse(AlertOutcome.silentByRule.needsAttention, "silence the user chose is not a problem")
        XCTAssertFalse(AlertOutcome.noAlertSet.needsAttention)
    }

    // MARK: - What was heard (M5 plan, Ruling 14, O11a)

    /// One name for each case of `AlertOutcome`, held here because the enum
    /// carries values and cannot list its own cases. `kind(of:)` switches over
    /// it with no default, so a case added to `AlertOutcome` stops this file
    /// compiling until it is named here, and `testEveryCaseIsClassified...`
    /// then fails until a variant of it is in `classified`, with the answer
    /// `wasHeard` should give.
    private enum Kind: CaseIterable {
        case played, spoke, playedAndSpoke, playedButNotSpoken, spokeButNotPlayed
        case failed, couldNotSpeak, silentByRule, noAlertSet, snoozed
    }

    private func kind(of outcome: AlertOutcome) -> Kind {
        switch outcome {
        case .played: return .played
        case .spoke: return .spoke
        case .playedAndSpoke: return .playedAndSpoke
        case .playedButNotSpoken: return .playedButNotSpoken
        case .spokeButNotPlayed: return .spokeButNotPlayed
        case .failed: return .failed
        case .couldNotSpeak: return .couldNotSpeak
        case .silentByRule: return .silentByRule
        case .noAlertSet: return .noAlertSet
        case .snoozed: return .snoozed
        }
    }

    /// Whether the outcome says the output was silent: nil for a case that
    /// carries no such fact. The cases that carry it are the ones that must be
    /// classified in both variants.
    private func outputSilent(_ outcome: AlertOutcome) -> Bool? {
        switch outcome {
        case .played(_, _, let silent), .spoke(_, _, _, let silent), .playedAndSpoke(_, _, _, _, _, let silent),
             .playedButNotSpoken(_, _, _, let silent), .spokeButNotPlayed(_, _, _, _, let silent):
            return silent
        case .failed, .couldNotSpeak, .silentByRule, .noAlertSet, .snoozed:
            return nil
        }
    }

    /// One variant of one case, and whether it is proof that something was
    /// heard. A struct and a function, not an array of tuples, so that each
    /// outcome is typed where it is written and the older compiler CI uses on
    /// macOS 15 has nothing to infer.
    private struct Variant {
        let outcome: AlertOutcome
        let heard: Bool
    }

    private func variant(_ outcome: AlertOutcome, heard: Bool) -> Variant {
        Variant(outcome: outcome, heard: heard)
    }

    /// Every case, each variant of the output's state included: not reported
    /// silent, which is `outputSilent: false` and covers an output the device
    /// could not describe, and reported silent.
    private var classified: [Variant] {
        func spoke(_ silent: Bool) -> AlertOutcome {
            AlertOutcome.spoke(text: "x", voice: "Daniel", gainDB: 0, outputSilent: silent)
        }
        func both(_ silent: Bool) -> AlertOutcome {
            AlertOutcome.playedAndSpoke(sound: "Glass", soundGainDB: 0, text: "x", voice: "Daniel", speechGainDB: 0,
                                        outputSilent: silent)
        }
        func playedNotSpoken(_ silent: Bool) -> AlertOutcome {
            AlertOutcome.playedButNotSpoken(sound: "Glass", gainDB: 0, reason: "x", outputSilent: silent)
        }
        func spokeNotPlayed(_ silent: Bool) -> AlertOutcome {
            AlertOutcome.spokeButNotPlayed(text: "x", voice: "Daniel", gainDB: 0, reason: "x", outputSilent: silent)
        }
        return [
            variant(AlertOutcome.played(sound: "Glass", gainDB: 0, outputSilent: false), heard: true),
            variant(AlertOutcome.played(sound: "Glass", gainDB: 0, outputSilent: true), heard: false),
            variant(spoke(false), heard: true),
            variant(spoke(true), heard: false),
            variant(both(false), heard: true),
            variant(both(true), heard: false),
            variant(playedNotSpoken(false), heard: false),
            variant(playedNotSpoken(true), heard: false),
            variant(spokeNotPlayed(false), heard: false),
            variant(spokeNotPlayed(true), heard: false),
            variant(AlertOutcome.failed("sound \"Glass\" was not found"), heard: false),
            variant(AlertOutcome.couldNotSpeak("voice \"x\" is not installed"), heard: false),
            variant(AlertOutcome.silentByRule, heard: false),
            variant(AlertOutcome.noAlertSet, heard: false),
            variant(AlertOutcome.snoozed, heard: false),
        ]
    }

    func testOnlyASoundOrSpeechThatPlayedIntoAnOutputNotReportedSilentWasHeard() {
        for variant in classified {
            XCTAssertEqual(variant.outcome.wasHeard, variant.heard, "\(variant.outcome)")
        }
        XCTAssertEqual(classified.filter { $0.heard }.count, 3,
                       "the sound, the speech and both, each into an output not reported silent, and nothing else")
    }

    func testEveryCaseIsClassifiedAndEveryCaseThatCarriesTheOutputsStateInBothVariants() {
        XCTAssertEqual(Set(classified.map { kind(of: $0.outcome) }), Set(Kind.allCases),
                       "a case with no variant here has not been classified")
        let bothVariants: Set<Bool?> = [false, true]
        for kind in Kind.allCases {
            let variants = classified.filter { self.kind(of: $0.outcome) == kind }.map { outputSilent($0.outcome) }
            if variants.contains(where: { $0 != nil }) {
                XCTAssertEqual(Set(variants), bothVariants, "\(kind): both the not-silent and the silent variant")
            } else {
                XCTAssertEqual(variants.count, 1, "\(kind) carries no output state, so one is enough")
            }
        }
    }

    func testAHalfHeardAlertIsNotHeardWhateverTheOutputWas() {
        // Each is half heard, and needsAttention flags each, so neither is
        // proof that what the next match needs will be heard.
        for silent in [false, true] {
            let halves: [AlertOutcome] = [
                .playedButNotSpoken(sound: "Glass", gainDB: 0, reason: "voice \"x\" is not installed", outputSilent: silent),
                .spokeButNotPlayed(text: "x", voice: "Daniel", gainDB: 0, reason: "sound \"Glas\" was not found",
                                   outputSilent: silent),
            ]
            for half in halves {
                XCTAssertFalse(half.wasHeard, "\(half)")
                XCTAssertTrue(half.needsAttention, "\(half)")
            }
        }
    }

    func testSilenceAndASnoozeAreNeitherHeardNorAProblem() {
        // What needsAttention's being false could not prove: a silent alert, no
        // alert and a held match are not warnings and are not proof either.
        for outcome in [AlertOutcome.silentByRule, .noAlertSet, .snoozed] {
            XCTAssertFalse(outcome.needsAttention, "\(outcome)")
            XCTAssertFalse(outcome.wasHeard, "\(outcome)")
        }
    }

    func testAnAlertThatWasHeardNeverNeedsAttention() {
        for variant in classified where variant.heard {
            XCTAssertFalse(variant.outcome.needsAttention, "\(variant.outcome)")
        }
    }

    // MARK: - Which rules make a noise

    func testOnlyAnEnabledRuleWithASoundAlertsAloud() {
        let condition = RuleCondition.field(.app, .equals, "Teams")
        XCTAssertTrue(Rule(name: "a", condition: condition, alert: .sound(name: "Glass", gainDB: 0)).alertsAloud)
        XCTAssertFalse(Rule(name: "b", condition: condition, isEnabled: false, alert: .sound(name: "Glass", gainDB: 0)).alertsAloud)
        XCTAssertFalse(Rule(name: "c", condition: condition, alert: .silent).alertsAloud)
        XCTAssertFalse(Rule(name: "d", condition: condition, alert: nil).alertsAloud)
    }

    // MARK: - Menu lines

    private func match(_ rule: String, at offset: TimeInterval, _ alert: AlertOutcome) -> CapturePipeline.LastMatch {
        .init(ruleName: rule, at: t0.addingTimeInterval(offset), alert: alert)
    }

    private func lines(last: CapturePipeline.LastMatch? = nil, failure: CapturePipeline.LastMatch? = nil,
                       anyRulePlaysSound: Bool = true, outputSilent: Bool = false) -> [String] {
        AlertMenuText.lines(lastMatch: last, unresolvedFailure: failure, anyRulePlaysSound: anyRulePlaysSound,
                            outputSilent: outputSilent, time: { "+\(Int($0.timeIntervalSince(self.t0)))" })
    }

    func testNothingToSayIsNoLines() {
        XCTAssertEqual(lines(), [])
    }

    func testTheLastMatchSaysWhatWasDone() {
        XCTAssertEqual(lines(last: match("On call", at: 5, .played(sound: "Glass", gainDB: 0, outputSilent: false))),
                       ["Last match: On call at +5 — Played Glass"])
    }

    func testALastMatchThatNeedsAttentionIsMarked() {
        XCTAssertEqual(lines(last: match("On call", at: 5, .played(sound: "Glass", gainDB: 0, outputSilent: true))),
                       ["⚠︎ Last match: On call at +5 — Played Glass — but the Mac's sound output was muted or at zero volume"])
    }

    func testTheLastMatchLineSaysAMatchWasHeldInTheSnoozesWordsAndIsNotMarked() {
        XCTAssertEqual(lines(last: match("On call", at: 5, .snoozed)),
                       ["Last match: On call at +5 — held while snoozed"],
                       "the row's own words would put a second dash in a line that has one")
        XCTAssertEqual(lines(last: match("On call", at: 5, .snoozed)),
                       ["Last match: On call at +5 — \(SnoozeText.heldStem)"], "from the snooze's constant")
    }

    func testAMatchASnoozeHeldDoesNotHideAnOlderFailureInTheMenu() {
        let failed = match("On call", at: 5, .failed("sound \"Glas\" was not found"))
        XCTAssertEqual(lines(last: match("Weather", at: 9, .snoozed), failure: failed), [
            "⚠︎ On call at +5: Could not play: sound \"Glas\" was not found",
            "Last match: Weather at +9 — held while snoozed",
        ])
    }

    func testAFailureThatIsTheLastMatchIsSaidOnce() {
        let failed = match("On call", at: 5, .failed("sound \"Glas\" was not found"))
        XCTAssertEqual(lines(last: failed, failure: failed),
                       ["⚠︎ Last match: On call at +5 — Could not play: sound \"Glas\" was not found"])
    }

    func testAnOlderFailureComesFirstAndSurvivesALaterQuietMatch() {
        let failed = match("On call", at: 5, .failed("sound \"Glas\" was not found"))
        XCTAssertEqual(lines(last: match("Weather", at: 9, .silentByRule), failure: failed), [
            "⚠︎ On call at +5: Could not play: sound \"Glas\" was not found",
            "Last match: Weather at +9 — Silent by rule",
        ])
    }

    func testASilentOutputIsWarnedAboutOnlyWhenARuleWouldPlaySound() {
        XCTAssertEqual(lines(anyRulePlaysSound: true, outputSilent: true), [AlertMenuText.outputSilentWarning])
        XCTAssertEqual(lines(anyRulePlaysSound: false, outputSilent: true), [],
                       "with no sounding rules, silence is what the user has chosen")
    }

    func testWarningsComeBeforeTheLastMatch() {
        let failed = match("On call", at: 5, .failed("x"))
        let result = lines(last: match("Weather", at: 9, .noAlertSet), failure: failed, outputSilent: true)
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result[0].hasPrefix("⚠︎ On call"))
        XCTAssertEqual(result[1], AlertMenuText.outputSilentWarning)
        XCTAssertTrue(result[2].hasPrefix("Last match: Weather"))
    }
}
