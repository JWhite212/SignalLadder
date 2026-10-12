import XCTest
@testable import NotificationCore

/// Speech in the rule format (M3d Task 1). Fixtures are invented text, never
/// captured content (§10.1).
final class SpeechAlertTests: XCTestCase {
    private func notification(app: String = "Microsoft Teams", title: String = "Priya mentioned you",
                              body: String = "Can you look at the rollback?") -> CapturedNotification {
        CapturedNotification(timestamp: Date(timeIntervalSince1970: 1_757_000_000),
                             appNameGuess: app, title: title, subtitle: "", body: body,
                             rawText: "\(app), \(title), \(body)", subrole: "AXNotificationCenterBanner")
    }

    private let daniel = "com.apple.voice.compact.en-GB.Daniel"
    private let teams = #""condition": {"field": "app", "op": "equals", "value": "Microsoft Teams"}"#
    private func file(version: Int = 3, _ rules: String) -> Data {
        Data("{\"version\": \(version), \"rules\": [\(rules)]}".utf8)
    }
    private func rule(_ alert: AlertAction?) -> Rule {
        Rule(name: "a", condition: .field(.app, .equals, "x"), alert: alert)
    }

    // MARK: - The spoken line

    func testTheDefaultTemplateSaysTheAppAndTitle() {
        XCTAssertEqual(SpeechAction(voiceIdentifier: daniel).rendered(for: notification()),
                       "Microsoft Teams: Priya mentioned you")
    }

    func testEveryPlaceholderIsFilled() {
        let speech = SpeechAction(voiceIdentifier: daniel, template: "{title} in {app}. {body}")
        XCTAssertEqual(speech.rendered(for: notification()),
                       "Priya mentioned you in Microsoft Teams. Can you look at the rollback?")
    }

    func testTextFromTheNotificationIsNotItselfTreatedAsATemplate() {
        // One pass: a title that happens to contain "{body}" is said as written.
        let speech = SpeechAction(voiceIdentifier: daniel, template: "{title}")
        XCTAssertEqual(speech.rendered(for: notification(title: "Deploy {body} failed", body: "secret")),
                       "Deploy {body} failed")
    }

    func testAnUnknownPlaceholderIsLeftAsWritten() {
        let speech = SpeechAction(voiceIdentifier: daniel, template: "{app} {sender}")
        XCTAssertEqual(speech.rendered(for: notification()), "Microsoft Teams {sender}")
    }

    func testAnUnclosedBraceIsSaidOnceAsWritten() {
        // Found in review: the text before an unclosed brace was said twice.
        XCTAssertEqual(SpeechAction(voiceIdentifier: daniel, template: "New message from {app").rendered(for: notification()),
                       "New message from {app")
        XCTAssertEqual(SpeechAction(voiceIdentifier: daniel, template: "{app}: {title").rendered(for: notification()),
                       "Microsoft Teams: {title")
    }

    func testALongLineIsCappedWithAnEllipsis() {
        // "A 40-second recitation of a Teams thread is not an alert" (§5.9).
        let long = String(repeating: "word ", count: 200)
        let line = SpeechAction(voiceIdentifier: daniel, template: "{body}").rendered(for: notification(body: long))
        XCTAssertEqual(line.count, SpeechAction.maximumLength)
        XCTAssertTrue(line.hasSuffix("…"), line)
    }

    func testAShortLineIsUntouched() {
        let line = SpeechAction(voiceIdentifier: daniel, template: "{app}").rendered(for: notification())
        XCTAssertEqual(line, "Microsoft Teams")
    }

    // MARK: - The file format

    func testASpokenAlertDecodesWithItsDefaults() throws {
        let (rules, problems) = try RuleSetCodec.decode(file(#"{"name": "a", \#(teams), "alert": {"speak": {"voice": "\#(daniel)"}}}"#))
        XCTAssertEqual(problems, [])
        XCTAssertEqual(rules.first?.alert, .speak(SpeechAction(voiceIdentifier: daniel)))
        XCTAssertEqual(rules.first?.alert?.speech?.template, "{app}: {title}")
    }

    func testASoundAndASpokenLineDecodeTogether() throws {
        let json = #"{"name": "a", \#(teams), "alert": {"sound": "Glass", "gainDB": 3, "speak": {"voice": "\#(daniel)", "template": "{title}", "rate": 0.6, "pitch": 1.2, "gainDB": -6}}}"#
        let (rules, problems) = try RuleSetCodec.decode(file(json))
        XCTAssertEqual(problems, [])
        XCTAssertEqual(rules.first?.alert,
                       .soundAndSpeak(soundName: "Glass", soundGainDB: 3,
                                      speech: SpeechAction(voiceIdentifier: daniel, template: "{title}", rate: 0.6,
                                                           pitchMultiplier: 1.2, gainDB: -6)))
    }

    func testEverySpokenShapeRoundTrips() throws {
        let rules = [rule(.speak(SpeechAction(voiceIdentifier: daniel, template: "{app}", rate: 0.4, pitchMultiplier: 0.9, gainDB: -2))),
                     Rule(name: "b", condition: .field(.app, .equals, "y"),
                          alert: .soundAndSpeak(soundName: "Hero", soundGainDB: -3, speech: SpeechAction(voiceIdentifier: daniel))),
                     Rule(name: "c", condition: .field(.app, .equals, "z"), alert: .sound(name: "Glass", gainDB: 0))]
        let encoded = try RuleSetCodec.encode(rules)
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains(#""version" : 3"#))
        XCTAssertEqual(try RuleSetCodec.decode(encoded).rules, rules)
    }

    func testAMisspeltKeyInsideSpeakIsRejectedByName() throws {
        let (_, problems) = try RuleSetCodec.decode(file(#"{"name": "a", \#(teams), "alert": {"speak": {"voice": "\#(daniel)", "templte": "{app}"}}}"#))
        XCTAssertTrue(problems.first?.reason.contains("unknown key \"templte\"") ?? false, "\(problems)")
    }

    func testAGainWithNoSoundIsRejectedRatherThanGuessedAt() throws {
        // Beside "speak", a top-level gainDB would be a sound's level with no
        // sound to apply it to — most likely meant for the speech.
        let (_, problems) = try RuleSetCodec.decode(file(#"{"name": "a", \#(teams), "alert": {"gainDB": 6, "speak": {"voice": "\#(daniel)"}}}"#))
        XCTAssertTrue(problems.first?.reason.contains("no sound") ?? false, "\(problems)")
    }

    func testAnAlertWithNeitherSoundNorSpeechIsRejected() throws {
        let (_, problems) = try RuleSetCodec.decode(file(#"{"name": "a", \#(teams), "alert": {"gainDB": 6}}"#))
        XCTAssertTrue(problems.first?.reason.contains("\"sound\", \"speak\" or both") ?? false, "\(problems)")
    }

    func testAWordThatIsNotSilentNamesEveryShape() throws {
        let (_, problems) = try RuleSetCodec.decode(file(#"{"name": "a", \#(teams), "alert": "loud"}"#))
        let reason = problems.first?.reason ?? ""
        XCTAssertTrue(reason.contains("\"silent\"") && reason.contains("{\"sound\"") && reason.contains("{\"speak\""), reason)
    }

    // MARK: - Versions

    func testSpeechInAVersion2FileIsRefusedNamingTheFix() throws {
        let (rules, problems) = try RuleSetCodec.decode(file(version: 2, #"{"name": "Pager", \#(teams), "alert": {"speak": {"voice": "\#(daniel)"}}}"#))
        XCTAssertEqual(rules, [])
        XCTAssertTrue(problems.first?.reason.contains("speech needs \"version\": 3") ?? false, "\(problems)")
    }

    func testSpeechInAVersion1FileNamesTheVersionItActuallyNeeds() throws {
        let (_, problems) = try RuleSetCodec.decode(file(version: 1, #"{"name": "Pager", \#(teams), "alert": {"speak": {"voice": "\#(daniel)"}}}"#))
        let reason = problems.first?.reason ?? ""
        XCTAssertTrue(reason.contains("\"version\": 3"), reason)
        XCTAssertFalse(reason.contains("\"version\": 2"), "one version message, the right one: \(reason)")
    }

    func testFilesAreWrittenAtTheLowestVersionThatHoldsThem() {
        XCTAssertEqual(RuleSetCodec.version(for: [rule(nil)]), 1)
        XCTAssertEqual(RuleSetCodec.version(for: [rule(.sound(name: "Glass", gainDB: 0))]), 2)
        XCTAssertEqual(RuleSetCodec.version(for: [rule(.sound(name: "Glass", gainDB: 0)), rule(.speak(SpeechAction(voiceIdentifier: daniel)))]), 3)
        XCTAssertEqual(RuleSetCodec.version(for: [rule(.soundAndSpeak(soundName: "Glass", soundGainDB: 0, speech: SpeechAction(voiceIdentifier: daniel)))]), 3)
    }

    func testAVersion3FileIsUnderstood() throws {
        XCTAssertEqual(RuleSetCodec.currentVersion, 5)
        XCTAssertNoThrow(try RuleSetCodec.decode(file(version: 3, #"{"name": "a", \#(teams)}"#)))
    }

    // MARK: - Validation

    func testAnEmptyVoiceOrTemplateIsAProblem() {
        XCTAssertTrue(RuleSetCodec.problems(in: rule(.speak(SpeechAction(voiceIdentifier: " ")))).contains("its spoken alert names no voice"))
        XCTAssertTrue(RuleSetCodec.problems(in: rule(.speak(SpeechAction(voiceIdentifier: daniel, template: "  ")))).contains("its spoken template is empty"))
    }

    func testAnUnknownPlaceholderIsAProblemNamingIt() {
        let problems = RuleSetCodec.problems(in: rule(.speak(SpeechAction(voiceIdentifier: daniel, template: "{app}: {sender}"))))
        XCTAssertEqual(problems, ["its spoken template has {sender}, which is not a placeholder — use {app}, {title} or {body}"])
    }

    func testAnUnclosedBraceIsAProblem() {
        XCTAssertEqual(RuleSetCodec.problems(in: rule(.speak(SpeechAction(voiceIdentifier: daniel, template: "Alert: {app")))),
                       ["its spoken template has a \"{\" that is never closed"])
        XCTAssertEqual(RuleSetCodec.problems(in: rule(.speak(SpeechAction(voiceIdentifier: daniel, template: "{app} } {title}")))), [],
                       "a stray closing brace is only text")
    }

    func testOutOfRangeRateAndPitchAreReportedAsWritten() {
        XCTAssertEqual(RuleSetCodec.problems(in: rule(.speak(SpeechAction(voiceIdentifier: daniel, rate: 1.1)))),
                       ["speech rate 1.1 is outside 0…1"])
        XCTAssertEqual(RuleSetCodec.problems(in: rule(.speak(SpeechAction(voiceIdentifier: daniel, pitchMultiplier: 0.3)))),
                       ["speech pitch 0.3 is outside 0.5…2"])
    }

    func testRatePitchAndGainAreBounded() {
        XCTAssertFalse(RuleSetCodec.problems(in: rule(.speak(SpeechAction(voiceIdentifier: daniel, rate: 1.5)))).isEmpty)
        XCTAssertFalse(RuleSetCodec.problems(in: rule(.speak(SpeechAction(voiceIdentifier: daniel, pitchMultiplier: 0.2)))).isEmpty)
        XCTAssertFalse(RuleSetCodec.problems(in: rule(.speak(SpeechAction(voiceIdentifier: daniel, gainDB: 20)))).isEmpty)
        XCTAssertEqual(RuleSetCodec.problems(in: rule(.speak(SpeechAction(voiceIdentifier: daniel, rate: 1, pitchMultiplier: 2, gainDB: 12)))), [])
        XCTAssertEqual(RuleSetCodec.problems(in: rule(.speak(SpeechAction(voiceIdentifier: daniel, rate: 0, pitchMultiplier: 0.5, gainDB: -40)))), [])
    }

    func testASoundAndSpeechRuleHasBothHalvesChecked() {
        let problems = RuleSetCodec.problems(in: rule(.soundAndSpeak(soundName: " ", soundGainDB: 40,
                                                                   speech: SpeechAction(voiceIdentifier: daniel, template: ""))))
        XCTAssertTrue(problems.contains("its alert names no sound"), "\(problems)")
        XCTAssertTrue(problems.contains { $0.hasPrefix("gainDB 40 is outside") }, "\(problems)")
        XCTAssertTrue(problems.contains("its spoken template is empty"), "\(problems)")
    }

    // MARK: - Voices and sounds that do not exist

    func testAVoiceThatIsNotInstalledIsReportedAtLoadByName() {
        let (rules, status) = RuleStoreStatus.load(
            file(#"{"name": "Pager", \#(teams), "alert": {"speak": {"voice": "com.example.gone"}}}"#),
            availableSounds: ["Glass"], unplayable: nil, availableVoices: [daniel])
        XCTAssertEqual(rules, [])
        let detail = status.detail.first ?? ""
        XCTAssertTrue(detail.hasPrefix("Rule 1 (\"Pager\")") && detail.contains("voice \"com.example.gone\" is not installed"), detail)
    }

    func testAnInstalledVoiceLoads() {
        let (rules, status) = RuleStoreStatus.load(
            file(#"{"name": "Pager", \#(teams), "alert": {"speak": {"voice": "\#(daniel)"}}}"#),
            availableSounds: ["Glass"], unplayable: nil, availableVoices: [daniel])
        XCTAssertEqual(rules.count, 1)
        XCTAssertFalse(status.isProblem)
    }

    func testTheSoundOfASoundAndSpeechRuleIsCheckedToo() {
        // The check once matched `.sound` alone, and would have waved through
        // a misspelt sound on a rule that also speaks.
        let (rules, status) = RuleStoreStatus.load(
            file(#"{"name": "Pager", \#(teams), "alert": {"sound": "Glas", "speak": {"voice": "\#(daniel)"}}}"#),
            availableSounds: ["Glass"], unplayable: nil, availableVoices: [daniel])
        XCTAssertEqual(rules, [])
        XCTAssertTrue(status.detail.first?.contains("sound \"Glas\" was not found") ?? false, "\(status.detail)")
    }

    // MARK: - What alerts aloud

    func testEveryAudibleAlertAlertsAloud() {
        XCTAssertTrue(rule(.sound(name: "Glass", gainDB: 0)).alertsAloud)
        XCTAssertTrue(rule(.speak(SpeechAction(voiceIdentifier: daniel))).alertsAloud)
        XCTAssertTrue(rule(.soundAndSpeak(soundName: "Glass", soundGainDB: 0, speech: SpeechAction(voiceIdentifier: daniel))).alertsAloud)
        XCTAssertFalse(rule(.silent).alertsAloud)
        XCTAssertFalse(rule(nil).alertsAloud)
        var off = rule(.speak(SpeechAction(voiceIdentifier: daniel)))
        off.isEnabled = false
        XCTAssertFalse(off.alertsAloud)
    }
}
