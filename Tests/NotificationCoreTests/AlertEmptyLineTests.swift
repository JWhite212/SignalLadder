import XCTest
@testable import NotificationCore

/// A spoken alert whose template fills in to no words for a notification, as
/// `{body}` does on a banner with one line of text, said nothing and was
/// recorded as spoken. It is now an alert that could not speak: the fallback
/// sound plays, or in a sound-and-speech alert the sound alone. Fixtures are
/// invented text (§10.1).
final class AlertEmptyLineTests: XCTestCase {
    private func banner(title: String = "Prod is down", body: String = "") -> CapturedNotification {
        CapturedNotification(
            timestamp: Date(timeIntervalSince1970: 1_790_000_000), appNameGuess: "Microsoft Teams",
            title: title, subtitle: "", body: body, rawText: "Microsoft Teams, \(title), \(body)",
            subrole: "AXNotificationCenterBanner")
    }

    private var calls: [String] = []

    /// Players that play every sound and speak every line, recording each call.
    private func run(_ alert: AlertAction, for notification: CapturedNotification) -> AlertOutcome {
        AlertActionRunner.run(
            alert, for: notification,
            playSound: { name, gain in
                self.calls.append("sound \(name) \(gain)")
                return .played(sound: name, gainDB: gain, outputSilent: false)
            },
            speak: { text, speech in
                self.calls.append("speak \(text)")
                return .spoke(text: text, voice: speech.voiceIdentifier, gainDB: speech.gainDB, outputSilent: false)
            },
            playAndSpeak: { name, gain, text, speech in
                self.calls.append("both \(name) \(text)")
                return .playedAndSpoke(sound: name, soundGainDB: gain, text: text, voice: speech.voiceIdentifier,
                                       speechGainDB: speech.gainDB, outputSilent: false)
            })
    }

    private func speech(_ template: String) -> SpeechAction {
        SpeechAction(voiceIdentifier: "some.voice", template: template, gainDB: -3)
    }

    private var fallback: String { AlertActionRunner.fallbackSound }

    // MARK: - Speech alone

    func testBodyOnABannerWithNoBodyPlaysTheFallbackAndSaysWhy() {
        XCTAssertEqual(run(.speak(speech("{body}")), for: banner()),
                       .playedFallback(sound: fallback, gainDB: -3, reason: InspectorRowText.nothingToSay,
                                       couldNotSpeak: true, outputSilent: false))
        XCTAssertEqual(calls, ["sound \(fallback) -3.0"], "an empty line is not handed to the speech player")
    }

    func testALineOfOnlySpacesCountsAsEmpty() {
        XCTAssertEqual(run(.speak(speech(" {body} ")), for: banner()),
                       .playedFallback(sound: fallback, gainDB: -3, reason: InspectorRowText.nothingToSay,
                                       couldNotSpeak: true, outputSilent: false))
    }

    func testALineWithWordsIsStillSpoken() {
        let outcome = run(.speak(speech("{body}")), for: banner(body: "Disk is full"))
        XCTAssertEqual(outcome, .spoke(text: "Disk is full", voice: "some.voice", gainDB: -3, outputSilent: false))
        XCTAssertEqual(calls, ["speak Disk is full"])
    }

    func testALineOfOnlyPunctuationIsLeftAloneBecauseItIsAudible() {
        // ": " renders audible speech (15,509 frames measured), so only a line
        // that isBlank is empty.
        let outcome = run(.speak(speech("{title}: {body}")), for: banner(title: "", body: ""))
        XCTAssertEqual(outcome, .spoke(text: ": ", voice: "some.voice", gainDB: -3, outputSilent: false))
    }

    // MARK: - Sound and speech

    func testASoundAndSpeechAlertWithAnEmptyLinePlaysItsSoundAlone() {
        let alert = AlertAction.soundAndSpeak(soundName: "Glass", soundGainDB: 4, speech: speech("{body}"))
        XCTAssertEqual(run(alert, for: banner()),
                       .playedButNotSpoken(sound: "Glass", gainDB: 4, reason: InspectorRowText.nothingToSay,
                                           outputSilent: false))
        XCTAssertEqual(calls, ["sound Glass 4.0"], "the sound plays, and no fallback is added to it")
    }

    func testASoundAndSpeechAlertWithWordsStillPlaysAndSpeaks() {
        let alert = AlertAction.soundAndSpeak(soundName: "Glass", soundGainDB: 4, speech: speech("{body}"))
        XCTAssertEqual(run(alert, for: banner(body: "Disk is full")),
                       .playedAndSpoke(sound: "Glass", soundGainDB: 4, text: "Disk is full", voice: "some.voice",
                                       speechGainDB: -3, outputSilent: false))
    }

    func testASoundAndSpeechAlertWhoseSoundIsMissingAndLineIsEmptyPlaysTheFallback() {
        let outcome = AlertActionRunner.run(
            .soundAndSpeak(soundName: "Klaxon", soundGainDB: 2, speech: speech("{body}")), for: banner(),
            playSound: { name, gain in
                name == "Klaxon" ? .failed("sound \"Klaxon\" was not found")
                    : .played(sound: name, gainDB: gain, outputSilent: false)
            },
            speak: { _, _ in XCTFail("nothing to speak"); return .failed("unexpected") },
            playAndSpeak: { _, _, _, _ in XCTFail("nothing to speak"); return .failed("unexpected") })
        XCTAssertEqual(outcome, .playedFallback(sound: fallback, gainDB: 2, reason: "sound \"Klaxon\" was not found",
                                                couldNotSpeak: false, outputSilent: false))
    }
}
