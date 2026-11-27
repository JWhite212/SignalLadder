import XCTest
@testable import NotificationCore

/// The two decisions behind Edit Sound… beside Add Sound… (sound editor plan, Ruling 9 and Task 9): when it is offered, and what
/// an alert comes to when the sound it was opened from has been saved under a new name.
final class EditSoundTests: XCTestCase {
    private let speech = SpeechAction(voiceIdentifier: "voice", template: "{title}")

    // MARK: - Whether a save replaced a sound

    func testASaveUnderANameThatWasAmongTheSoundsReplacedOneWhateverTheCase() {
        XCTAssertTrue(AlertEditing.savedSoundReplaces("Alarm", among: ["Glass", "Alarm"]))
        XCTAssertTrue(AlertEditing.savedSoundReplaces("alarm", among: ["Glass", "ALARM"]))
    }

    func testASaveUnderANameNothingHadReplacedNothing() {
        XCTAssertFalse(AlertEditing.savedSoundReplaces("Alarm 2", among: ["Glass", "Alarm"]))
        XCTAssertFalse(AlertEditing.savedSoundReplaces("Alarm", among: []))
    }

    // MARK: - When it is offered

    func testItIsOfferedForASoundThatIsThere() {
        XCTAssertTrue(AlertEditing.canEditSound(named: "Alarm", among: ["Glass", "Alarm"]))
    }

    func testItIsOfferedWhateverTheCaseOfTheNameTheRuleHas() {
        XCTAssertTrue(AlertEditing.canEditSound(named: "alarm", among: ["Alarm"]))
        XCTAssertTrue(AlertEditing.canEditSound(named: "ALARM", among: ["alarm"]))
    }

    func testItIsOffForASoundThatIsNotFound() {
        XCTAssertFalse(AlertEditing.canEditSound(named: "Gone", among: ["Glass", "Alarm"]))
        XCTAssertFalse(AlertEditing.canEditSound(named: "Alarm", among: []))
    }

    func testItIsOffForABlankNameAndForAnotherSoundWithTheSameStart() {
        XCTAssertFalse(AlertEditing.canEditSound(named: "", among: ["", "Alarm"]))
        XCTAssertFalse(AlertEditing.canEditSound(named: "Alarm", among: ["Alarm 2", "Alar"]))
    }

    // MARK: - What the alert comes to

    func testAnAlertThatStillNamesTheSoundIsGivenTheNewOneWithItsGain() {
        XCTAssertEqual(AlertEditing.naming(saved: "Alarm 2", in: .sound(name: "Alarm", gainDB: 4), replacing: "Alarm"),
                       .sound(name: "Alarm 2", gainDB: 4))
    }

    func testASoundThenSpeechAlertKeepsItsSpeechAndGain() {
        XCTAssertEqual(AlertEditing.naming(saved: "Alarm 2", in: .soundAndSpeak(soundName: "Alarm", soundGainDB: -3, speech: speech),
                                           replacing: "Alarm"),
                       .soundAndSpeak(soundName: "Alarm 2", soundGainDB: -3, speech: speech))
    }

    func testTheSoundIsFoundIgnoringCase() {
        XCTAssertEqual(AlertEditing.naming(saved: "Alarm 2", in: .sound(name: "alarm", gainDB: 0), replacing: "Alarm"),
                       .sound(name: "Alarm 2", gainDB: 0))
    }

    func testAnAlertThatNamesAnotherSoundByNowIsLeftAlone() {
        let changed = AlertAction.sound(name: "Glass", gainDB: 0)
        XCTAssertEqual(AlertEditing.naming(saved: "Alarm 2", in: changed, replacing: "Alarm"), changed,
                       "the window was open while the rule was changed, and the change is not undone")
    }

    func testAnAlertThatNoLongerPlaysASoundIsLeftAlone() {
        for alert in [nil, AlertAction.silent, .speak(speech)] {
            XCTAssertEqual(AlertEditing.naming(saved: "Alarm 2", in: alert, replacing: "Alarm"), alert)
        }
    }
}
