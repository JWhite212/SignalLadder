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
