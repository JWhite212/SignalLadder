import XCTest
@testable import NotificationCore

/// The one path every tier's alert takes (M4 plan, ruling 7). Fixtures are
/// invented text (§10.1).
final class AlertActionRunnerTests: XCTestCase {
    private let notification = CapturedNotification(
        timestamp: Date(timeIntervalSince1970: 1_790_000_000), appNameGuess: "Microsoft Teams",
        title: "Alex Example mentioned you", subtitle: "", body: "Placeholder body text",
        rawText: "Microsoft Teams, Alex Example mentioned you, Placeholder body text",
        subrole: "AXNotificationCenterBanner")

    private var calls: [String] = []

    private func run(_ alert: AlertAction) -> AlertOutcome {
        AlertActionRunner.run(alert, for: notification,
                              playSound: { name, gain in self.calls.append("sound \(name) \(gain)")
                                  return .played(sound: name, gainDB: gain, outputSilent: false) },
                              speak: { text, speech in self.calls.append("speak \(text) \(speech.voiceIdentifier)")
                                  return .spoke(text: text, voice: speech.voiceIdentifier, gainDB: 0, outputSilent: false) },
                              playAndSpeak: { name, gain, text, _ in self.calls.append("both \(name) \(gain) \(text)")
                                  return .played(sound: name, gainDB: gain, outputSilent: false) })
    }

    private let speech = SpeechAction(voiceIdentifier: "v", template: "{app}: {title}")

    func testASoundPlaysAtItsGain() {
        XCTAssertEqual(run(.sound(name: "Glass", gainDB: 6)), .played(sound: "Glass", gainDB: 6, outputSilent: false))
        XCTAssertEqual(calls, ["sound Glass 6.0"])
    }

    func testSpeechSaysTheLineRenderedFromTheNotification() {
        XCTAssertEqual(run(.speak(speech)),
                       .spoke(text: "Microsoft Teams: Alex Example mentioned you", voice: "v", gainDB: 0, outputSilent: false))
        XCTAssertEqual(calls, ["speak Microsoft Teams: Alex Example mentioned you v"])
    }

    func testASoundAndSpeechIsOneAlert() {
        _ = run(.soundAndSpeak(soundName: "Hero", soundGainDB: -3, speech: speech))
        XCTAssertEqual(calls, ["both Hero -3.0 Microsoft Teams: Alex Example mentioned you"])
    }

    func testSilentPlaysNothing() {
        XCTAssertEqual(run(.silent), .silentByRule)
        XCTAssertEqual(calls, [])
    }
}
