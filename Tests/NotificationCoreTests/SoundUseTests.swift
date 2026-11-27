import XCTest
@testable import NotificationCore

/// Which rules name a sound, so that saving over one can say how many it changes
/// (sound editor plan, Ruling 9).
final class SoundUseTests: XCTestCase {
    private let speech = SpeechAction(voiceIdentifier: "voice", template: "{title}")

    private func rule(_ name: String, enabled: Bool = true, alert: AlertAction? = nil, escalation: Escalation? = nil) -> Rule {
        Rule(name: name, condition: .field(.app, .equals, name), isEnabled: enabled, alert: alert, escalation: escalation)
    }

    private func names(_ sound: String, in rules: [Rule]) -> [String] {
        SoundUse.rules(naming: sound, in: rules).map(\.name)
    }

    func testARuleWhoseFirstAlertPlaysTheSoundNamesIt() {
        let rules = [rule("A", alert: .sound(name: "Alarm", gainDB: 0)), rule("B", alert: .sound(name: "Glass", gainDB: 0))]
        XCTAssertEqual(names("Alarm", in: rules), ["A"])
        XCTAssertEqual(SoundUse.count(naming: "Alarm", in: rules), 1)
    }

    func testASoundThenSpeechAlertNamesItAndSpeechAloneDoesNot() {
        let rules = [rule("Both", alert: .soundAndSpeak(soundName: "Alarm", soundGainDB: 3, speech: speech)),
                     rule("Speech", alert: .speak(speech)), rule("Quiet", alert: .silent), rule("None")]
        XCTAssertEqual(names("Alarm", in: rules), ["Both"])
    }

    func testARepeatAndAFinalAlertNameItToo() {
        let repeats = Escalation(tier3: RepeatAlert(action: .sound(name: "Alarm", gainDB: 0)))
        let final = Escalation(tier4: FinalAlert(action: .alert(.soundAndSpeak(soundName: "Alarm", soundGainDB: 0, speech: speech))))
        let panel = Escalation(tier2: PanelAlert())
        let rules = [rule("Repeats", escalation: repeats), rule("Final", escalation: final), rule("Panel", escalation: panel)]
        XCTAssertEqual(names("Alarm", in: rules), ["Repeats", "Final"])
    }

    func testAShortcutAtTheEndNamesNoSound() {
        let rules = [rule("Phone", escalation: Escalation(tier4: FinalAlert(action: .shortcut(name: "Alarm"))))]
        XCTAssertEqual(names("Alarm", in: rules), [])
    }

    func testARuleThatNamesItInSeveralPlacesIsCountedOnce() {
        let ladder = Escalation(tier3: RepeatAlert(action: .sound(name: "Alarm", gainDB: 0)),
                                tier4: FinalAlert(action: .alert(.sound(name: "Alarm", gainDB: 6))))
        let rules = [rule("All", alert: .sound(name: "Alarm", gainDB: 0), escalation: ladder)]
        XCTAssertEqual(names("Alarm", in: rules), ["All"])
        XCTAssertEqual(SoundUse.count(naming: "Alarm", in: rules), 1)
    }

    func testARuleThatIsSwitchedOffStillNamesItBecauseSwitchingItOnWouldPlayIt() {
        let rules = [rule("Off", enabled: false, alert: .sound(name: "Alarm", gainDB: 0))]
        XCTAssertEqual(names("Alarm", in: rules), ["Off"])
    }

    func testNamesAreComparedIgnoringCaseAsTheLibraryComparesThem() {
        let rules = [rule("A", alert: .sound(name: "alarm", gainDB: 0)), rule("B", alert: .sound(name: "ALARM", gainDB: 0))]
        XCTAssertEqual(names("Alarm", in: rules), ["A", "B"])
    }

    func testAnotherSoundWithTheSameStartIsNotTheSound() {
        let rules = [rule("A", alert: .sound(name: "Alarm 2", gainDB: 0)), rule("B", alert: .sound(name: "Alar", gainDB: 0))]
        XCTAssertEqual(names("Alarm", in: rules), [])
        XCTAssertEqual(SoundUse.count(naming: "Alarm", in: rules), 0)
    }

    func testTheRulesComeInTheOrderTheyAreInAndNoRulesNameNothing() {
        let rules = (1...4).map { rule("R\($0)", alert: .sound(name: "Alarm", gainDB: 0)) }
        XCTAssertEqual(names("Alarm", in: rules), ["R1", "R2", "R3", "R4"])
        XCTAssertEqual(names("Alarm", in: []), [])
    }

    func testABlankNameIsNamedByNoRule() {
        XCTAssertEqual(names("", in: [rule("A", alert: .sound(name: "", gainDB: 0))]), [])
    }
}
