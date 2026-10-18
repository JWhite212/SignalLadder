import XCTest
@testable import NotificationCore

/// An alert that would make no sound at all, because the sound or the voice
/// its rule names cannot be found or played, plays the fallback sound in its
/// place, and says so. Fixtures are invented text (§10.1).
final class AlertFallbackTests: XCTestCase {
    private let notification = CapturedNotification(
        timestamp: Date(timeIntervalSince1970: 1_790_000_000), appNameGuess: "Microsoft Teams",
        title: "#prod-payments", subtitle: "", body: "Placeholder body text",
        rawText: "Microsoft Teams, #prod-payments, Placeholder body text",
        subrole: "AXNotificationCenterBanner")

    private let speech = SpeechAction(voiceIdentifier: "gone.voice", template: "{app}: {title}", gainDB: -3)
    private var calls: [String] = []

    /// The players a Mac with `missing` gone would give: a sound that is not
    /// there fails, as the player says it does, and speech fails for a voice
    /// that is not there. Every call is recorded.
    private func run(_ alert: AlertAction, missing: Set<String> = [], outputSilent: Bool = false) -> AlertOutcome {
        AlertActionRunner.run(
            alert, for: notification,
            playSound: { name, gain in
                self.calls.append("sound \(name) \(gain)")
                return missing.contains(name) ? .failed("sound \"\(name)\" was not found")
                    : .played(sound: name, gainDB: gain, outputSilent: outputSilent)
            },
            speak: { text, speech in
                self.calls.append("speak \(speech.voiceIdentifier)")
                return missing.contains(speech.voiceIdentifier)
                    ? .couldNotSpeak("voice \"\(speech.voiceIdentifier)\" is not installed")
                    : .spoke(text: text, voice: speech.voiceIdentifier, gainDB: speech.gainDB, outputSilent: outputSilent)
            },
            playAndSpeak: { name, gain, text, speech in
                self.calls.append("both \(name) \(speech.voiceIdentifier)")
                switch (missing.contains(name), missing.contains(speech.voiceIdentifier)) {
                case (false, false):
                    return .playedAndSpoke(sound: name, soundGainDB: gain, text: text, voice: speech.voiceIdentifier,
                                           speechGainDB: speech.gainDB, outputSilent: outputSilent)
                case (false, true):
                    return .playedButNotSpoken(sound: name, gainDB: gain, reason: "voice is not installed",
                                               outputSilent: outputSilent)
                case (true, false):
                    return .spokeButNotPlayed(text: text, voice: speech.voiceIdentifier, gainDB: speech.gainDB,
                                              reason: "sound was not found", outputSilent: outputSilent)
                case (true, true):
                    return .failed("sound \"\(name)\" was not found, and could not speak: voice is not installed")
                }
            })
    }

    private var fallback: String { AlertActionRunner.fallbackSound }

    // MARK: - When the fallback plays

    func testTheFallbackIsOneOfTheMacsOwnSounds() {
        // One of the sounds in /System/Library/Sounds, which every Mac has, so
        // a fallback is never missing for the reason the rule's sound was.
        let macSounds: Set<String> = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping",
                                      "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
        XCTAssertTrue(macSounds.contains(fallback), fallback)
    }

    func testASoundThatIsMissingPlaysTheFallbackAtTheRulesGainAndSaysWhy() {
        XCTAssertEqual(run(.sound(name: "Klaxon", gainDB: 6), missing: ["Klaxon"]),
                       .playedFallback(sound: fallback, gainDB: 6, reason: "sound \"Klaxon\" was not found",
                                       couldNotSpeak: false, outputSilent: false))
        XCTAssertEqual(calls, ["sound Klaxon 6.0", "sound \(fallback) 6.0"], "the rule's sound is tried first")
    }

    func testSpeechWhoseVoiceIsMissingPlaysTheFallbackAtTheSpeechGainAndNeverAnotherVoice() {
        XCTAssertEqual(run(.speak(speech), missing: ["gone.voice"]),
                       .playedFallback(sound: fallback, gainDB: -3, reason: "voice \"gone.voice\" is not installed",
                                       couldNotSpeak: true, outputSilent: false))
        XCTAssertEqual(calls, ["speak gone.voice", "sound \(fallback) -3.0"],
                       "the line is not said in someone else's voice: a sound plays instead")
    }

    func testASoundAndSpeechThatCanDoNeitherPlaysTheFallback() {
        let outcome = run(.soundAndSpeak(soundName: "Klaxon", soundGainDB: 2, speech: speech),
                          missing: ["Klaxon", "gone.voice"])
        XCTAssertEqual(outcome, .playedFallback(
            sound: fallback, gainDB: 2,
            reason: "sound \"Klaxon\" was not found, and could not speak: voice is not installed",
            couldNotSpeak: false, outputSilent: false))
        XCTAssertEqual(calls, ["both Klaxon gone.voice", "sound \(fallback) 2.0"])
    }

    func testTheFallbackIntoASilentOutputSaysSo() {
        XCTAssertEqual(run(.sound(name: "Klaxon", gainDB: 0), missing: ["Klaxon"], outputSilent: true),
                       .playedFallback(sound: fallback, gainDB: 0, reason: "sound \"Klaxon\" was not found",
                                       couldNotSpeak: false, outputSilent: true))
    }

    // MARK: - When it does not

    func testAnAlertThatMadeASoundIsLeftAsItIs() {
        // Half an alert is still a sound, and its outcome already says which
        // half failed: the fallback is for an alert that made none.
        XCTAssertEqual(run(.sound(name: "Glass", gainDB: 0)), .played(sound: "Glass", gainDB: 0, outputSilent: false))
        XCTAssertEqual(run(.soundAndSpeak(soundName: "Glass", soundGainDB: 0, speech: speech), missing: ["gone.voice"]),
                       .playedButNotSpoken(sound: "Glass", gainDB: 0, reason: "voice is not installed", outputSilent: false))
        XCTAssertEqual(run(.soundAndSpeak(soundName: "Klaxon", soundGainDB: 0, speech: speech), missing: ["Klaxon"]),
                       .spokeButNotPlayed(text: "Microsoft Teams: #prod-payments", voice: "gone.voice", gainDB: -3,
                                          reason: "sound was not found", outputSilent: false))
        XCTAssertEqual(calls, ["sound Glass 0.0", "both Glass gone.voice", "both Klaxon gone.voice"],
                       "and no fallback is tried")
    }

    func testASilentRulePlaysNothingAtAll() {
        XCTAssertEqual(run(.silent), .silentByRule)
        XCTAssertEqual(calls, [])
    }

    func testAFallbackThatCannotPlayEitherLeavesTheRulesOwnFailure() {
        // The output itself failing fails the fallback too, and the failure
        // the rule's own alert met is the one to report.
        XCTAssertEqual(run(.sound(name: "Klaxon", gainDB: 0), missing: ["Klaxon", fallback]),
                       .failed("sound \"Klaxon\" was not found"))
        XCTAssertEqual(run(.speak(speech), missing: ["gone.voice", fallback]),
                       .couldNotSpeak("voice \"gone.voice\" is not installed"))
    }

    // MARK: - What the row and the menu say

    func testTheLineSaysWhatCouldNotHappenFirstThenWhatPlayedInItsPlace() {
        XCTAssertEqual(InspectorRowText.alert(.playedFallback(sound: "Sosumi", gainDB: 0, reason: "sound \"Klaxon\" was not found",
                                                              couldNotSpeak: false, outputSilent: false)),
                       "Could not play: sound \"Klaxon\" was not found; played Sosumi in its place")
        XCTAssertEqual(InspectorRowText.alert(.playedFallback(sound: "Sosumi", gainDB: -3, reason: "voice \"x\" is not installed",
                                                              couldNotSpeak: true, outputSilent: false)),
                       "Could not speak: voice \"x\" is not installed; played Sosumi (−3 dB) in its place")
        XCTAssertEqual(InspectorRowText.alert(.playedFallback(sound: "Sosumi", gainDB: 0, reason: "r",
                                                              couldNotSpeak: false, outputSilent: true)),
                       "Could not play: r; played Sosumi in its place — but the Mac's sound output was muted or at zero volume")
    }

    func testAFallbackNeedsAttentionIsNotEvidenceTheRulesAlertWasHeardAndSaidNothing() {
        // Not heard, as half an alert is not: what the next match of a burst
        // needs is the rule's own alert, and this is no evidence that it will
        // be heard, so a match that joins plays rather than stays silent.
        for silent in [false, true] {
            let outcome = AlertOutcome.playedFallback(sound: "Sosumi", gainDB: 0, reason: "r", couldNotSpeak: true,
                                                      outputSilent: silent)
            XCTAssertTrue(outcome.needsAttention)
            XCTAssertFalse(outcome.wasHeard)
            XCTAssertNil(outcome.spokenText)
            XCTAssertTrue(outcome.tookThePlayer, "the fallback is what is playing")
            XCTAssertEqual(InspectorRowText.symbol(outcome), "exclamationmark.triangle")
        }
    }
}

/// The fallback through the pipeline: a rule whose sound or voice is missing
/// stays in effect and still sounds, and the menu holds what went wrong until
/// a rule's own alert plays.
@MainActor
final class AlertFallbackWiringTests: XCTestCase {
    func testAFallbackHoldsTheMenusFailureUntilARulesOwnAlertPlays() throws {
        var outcomes: [String: AlertOutcome] = [:]
        let pipeline = CapturePipeline.forTest(
            playSound: { name, _ in outcomes[name] ?? .played(sound: name, gainDB: 0, outputSilent: false) })
        pipeline.setRules([
            Rule(name: "Broken", condition: .field(.title, .equals, "broken"), alert: .sound(name: "Klaxon", gainDB: 0)),
            Rule(name: "Fine", condition: .field(.title, .equals, "fine"), alert: .sound(name: "Glass", gainDB: 0)),
        ])
        outcomes["Klaxon"] = .failed("sound \"Klaxon\" was not found")
        func post(_ title: String, at seconds: TimeInterval) {
            pipeline.process(RawCapture(timestamp: Date(timeIntervalSince1970: 1_790_000_000) + seconds,
                                        rawText: "Example Chat, \(title)", subrole: "AXNotificationCenterBanner"),
                             textChildren: [title])
        }

        post("broken", at: 0)
        let held = try XCTUnwrap(pipeline.unresolvedAlertFailure, "held as a failure, as a failed alert is")
        XCTAssertEqual(held.ruleName, "Broken")
        XCTAssertEqual(held.alert, .playedFallback(sound: AlertActionRunner.fallbackSound, gainDB: 0,
                                                   reason: "sound \"Klaxon\" was not found", couldNotSpeak: false,
                                                   outputSilent: false))
        post("fine", at: 5)
        XCTAssertNil(pipeline.unresolvedAlertFailure, "and cleared by a rule's own sound that played")
    }

    /// The README's own pair of rules, on a Mac where the voice the first names
    /// has gone: the rule stays in effect, so the catch-all beneath it cannot
    /// take its match and keep it quiet.
    func testAMissingVoiceNoLongerLetsASilentRuleBelowSwallowThePage() throws {
        let file = Data(#"""
            {"version": 3, "rules": [
              {"name": "Production incidents",
               "condition": {"and": [{"field": "app", "op": "equals", "value": "Microsoft Teams"},
                                     {"field": "title", "op": "matches", "value": "#prod-*"}]},
               "alert": {"speak": {"voice": "com.apple.voice.compact.en-GB.Daniel", "template": "{app}: {title}"}}},
              {"name": "Everything else from Teams",
               "condition": {"field": "app", "op": "equals", "value": "Microsoft Teams"},
               "alert": "silent"}]}
            """#.utf8)
        let (rules, status) = RuleStoreStatus.load(file)
        XCTAssertEqual(rules.map(\.name), ["Production incidents", "Everything else from Teams"], "both are in effect")
        XCTAssertEqual(status, .loaded(enabled: 2, disabled: 0))
        let check = RuleSetCodec.SoundCheck(available: ["Glass", "Sosumi"], unplayable: nil,
                                            voices: ["com.apple.voice.compact.en-US.Samantha"], shortcuts: nil)
        XCTAssertEqual(RuleWarnings.warnings(for: rules, sounds: check).map(\.ruleName), ["Production incidents"],
                       "and the one whose voice is gone is warned about")

        var played: [String] = []
        let pipeline = CapturePipeline.forTest(
            playSound: { name, gain in played.append(name); return .played(sound: name, gainDB: gain, outputSilent: false) },
            speak: { _, speech in .couldNotSpeak("voice \"\(speech.voiceIdentifier)\" is not installed") })
        pipeline.setRules(rules)
        pipeline.process(RawCapture(timestamp: Date(timeIntervalSince1970: 1_790_000_000),
                                    rawText: "Microsoft Teams, #prod-payments, Placeholder body text",
                                    subrole: "AXNotificationCenterBanner"),
                         textChildren: ["#prod-payments", "Placeholder body text"])

        let last = try XCTUnwrap(pipeline.lastMatch)
        XCTAssertEqual(last.ruleName, "Production incidents", "the page's own rule took it, not the catch-all")
        XCTAssertEqual(last.alert, .playedFallback(
            sound: AlertActionRunner.fallbackSound, gainDB: 0,
            reason: "voice \"com.apple.voice.compact.en-GB.Daniel\" is not installed", couldNotSpeak: true,
            outputSilent: false))
        XCTAssertEqual(played, [AlertActionRunner.fallbackSound], "and something sounded")
    }
}
