import XCTest
@testable import NotificationCore

/// The rule editor's alert controls, as state transitions.
final class AlertEditingTests: XCTestCase {
    private let daniel = "com.apple.voice.compact.en-GB.Daniel"
    private let custom = SpeechAction(voiceIdentifier: "com.apple.voice.enhanced.en-GB.Malcolm", template: "{title}",
                                      rate: 0.6, pitchMultiplier: 1.1, gainDB: -4)

    private func choose(_ kind: AlertEditing.Kind, _ alert: AlertAction?, setAside: AlertEditing.SetAside = .init())
        -> (alert: AlertAction?, setAside: AlertEditing.SetAside) {
        AlertEditing.choosing(kind, from: alert, setAside: setAside, defaultSound: "Glass", defaultVoice: daniel)
    }

    func testEachAlertShowsAsItsKind() {
        XCTAssertEqual(AlertEditing.kind(of: nil), .none)
        XCTAssertEqual(AlertEditing.kind(of: .silent), .silent)
        XCTAssertEqual(AlertEditing.kind(of: .sound(name: "Glass", gainDB: 0)), .sound)
        XCTAssertEqual(AlertEditing.kind(of: .soundAndSpeak(soundName: "Glass", soundGainDB: 0, speech: custom)), .sound,
                       "a sound with speech is Sound with Also speak it on")
        XCTAssertEqual(AlertEditing.kind(of: .speak(custom)), .speech)
    }

    func testChoosingSpeechTheFirstTimeGivesAVoice() {
        let (alert, _) = choose(.speech, nil)
        XCTAssertEqual(alert, .speak(SpeechAction(voiceIdentifier: daniel)))
        XCTAssertFalse(alert?.speech?.voiceIdentifier.isEmpty ?? true, "never an empty voice, which would be a problem at load")
    }

    func testChoosingSoundTheFirstTimeGivesTheDefaultSound() {
        XCTAssertEqual(choose(.sound, nil).alert, .sound(name: "Glass", gainDB: 0))
    }

    func testChoosingTheKindAlreadyShownChangesNothing() {
        let both = AlertAction.soundAndSpeak(soundName: "Hero", soundGainDB: 3, speech: custom)
        XCTAssertEqual(choose(.sound, both).alert, both)
        XCTAssertEqual(choose(.speech, .speak(custom)).alert, .speak(custom))
    }

    func testSpeechSetAsideComesBackWhenChosenAgain() {
        let away = choose(.silent, .speak(custom))
        XCTAssertEqual(away.alert, .silent)
        let back = choose(.speech, away.alert, setAside: away.setAside)
        XCTAssertEqual(back.alert, .speak(custom), "what the user set up is not lost")
    }

    func testSwitchingAlsoSpeakOffAndOnRestoresTheSpeech() {
        let both = AlertAction.soundAndSpeak(soundName: "Hero", soundGainDB: 3, speech: custom)
        let off = AlertEditing.settingAlsoSpeak(false, on: both, setAside: .init(), defaultVoice: daniel)
        XCTAssertEqual(off.alert, .sound(name: "Hero", gainDB: 3))
        let on = AlertEditing.settingAlsoSpeak(true, on: off.alert, setAside: off.setAside, defaultVoice: daniel)
        XCTAssertEqual(on.alert, both)
    }

    func testAlsoSpeakOnASoundWithNothingRememberedUsesTheDefaultVoice() {
        let on = AlertEditing.settingAlsoSpeak(true, on: .sound(name: "Glass", gainDB: 0), setAside: .init(), defaultVoice: daniel)
        XCTAssertEqual(on.alert, .soundAndSpeak(soundName: "Glass", soundGainDB: 0, speech: SpeechAction(voiceIdentifier: daniel)))
    }

    func testFromSpeechToSoundTheSpeechIsRemembered() {
        let sound = choose(.sound, .speak(custom))
        XCTAssertEqual(sound.alert, .sound(name: "Glass", gainDB: 0))
        let on = AlertEditing.settingAlsoSpeak(true, on: sound.alert, setAside: sound.setAside, defaultVoice: daniel)
        XCTAssertEqual(on.alert?.speech, custom)
    }

    func testASoundSetAsideComesBackWhenChosenAgain() {
        // Found in review: a trip through Speech replaced Hero at +6 dB with
        // Glass at 0 dB, without a word.
        for away in [AlertEditing.Kind.speech, .silent, .none] {
            let there = choose(away, .sound(name: "Hero", gainDB: 6))
            let back = choose(.sound, there.alert, setAside: there.setAside)
            XCTAssertEqual(back.alert, .sound(name: "Hero", gainDB: 6), "via \(away)")
        }
    }

    func testFromSoundWithSpeechToSpeechAndBackKeepsTheSound() {
        let both = AlertAction.soundAndSpeak(soundName: "Hero", soundGainDB: 6, speech: custom)
        let speech = choose(.speech, both)
        XCTAssertEqual(speech.alert, .speak(custom))
        let back = choose(.sound, speech.alert, setAside: speech.setAside)
        XCTAssertEqual(back.alert, .sound(name: "Hero", gainDB: 6))
    }

    func testTheSoundCanBeChangedWithOrWithoutSpeech() {
        XCTAssertEqual(AlertEditing.replacingSound(in: .sound(name: "Glass", gainDB: 0), name: "Hero"), .sound(name: "Hero", gainDB: 0))
        XCTAssertEqual(AlertEditing.replacingSound(in: .soundAndSpeak(soundName: "Glass", soundGainDB: 0, speech: custom), gainDB: 6),
                       .soundAndSpeak(soundName: "Glass", soundGainDB: 6, speech: custom))
        XCTAssertEqual(AlertEditing.replacingSound(in: .speak(custom), name: "Hero"), .speak(custom))
    }

    func testTheSpeechCanBeChangedAloneOrAfterASound() {
        let other = SpeechAction(voiceIdentifier: daniel, template: "{app}")
        XCTAssertEqual(AlertEditing.replacingSpeech(in: .speak(custom), with: other), .speak(other))
        XCTAssertEqual(AlertEditing.replacingSpeech(in: .soundAndSpeak(soundName: "Glass", soundGainDB: 0, speech: custom), with: other),
                       .soundAndSpeak(soundName: "Glass", soundGainDB: 0, speech: other))
        XCTAssertEqual(AlertEditing.replacingSpeech(in: .sound(name: "Glass", gainDB: 0), with: other), .sound(name: "Glass", gainDB: 0))
    }

    func testTestSpeechSaysAMadeUpNotification() {
        let line = SpeechAction(voiceIdentifier: daniel).rendered(for: AlertEditing.sampleNotification)
        XCTAssertEqual(line, "Microsoft Teams: Priya mentioned you in Incident Bridge")
    }

    func testGainsReadWithATrueMinus() {
        XCTAssertEqual(EditorText.gainText(0), "0 dB")
        XCTAssertEqual(EditorText.gainText(6), "+6 dB")
        XCTAssertEqual(EditorText.gainText(-12), "−12 dB")
    }

    func testTheTemplateHelpNamesEveryPlaceholder() {
        for name in SpeechAction.placeholders {
            XCTAssertTrue(EditorText.speechTemplateHelp.contains("{\(name)}"), name)
        }
    }
    // MARK: - Which kinds a picker shows

    func testTheFirstAlertOffersAllFourKindsAndALaterStepOnlySoundAndSpeech() {
        XCTAssertEqual(AlertEditing.offeredKinds(for: .first), [.none, .silent, .sound, .speech])
        XCTAssertEqual(AlertEditing.offeredKinds(for: .repeating), [.sound, .speech])
        XCTAssertEqual(AlertEditing.offeredKinds(for: .final), [.sound, .speech])
        XCTAssertEqual(AlertEditing.segmentOrder, [.none, .silent, .sound, .speech])
    }

    func testAPickerShowsWhatIsOfferedAndWhateverTheAlertAlreadyIsInOrder() {
        let all: [AlertEditing.Kind] = [.none, .silent, .sound, .speech]
        let later: [AlertEditing.Kind] = [.sound, .speech]
        XCTAssertEqual(AlertEditing.shownKinds(offering: all, for: nil), all)
        XCTAssertEqual(AlertEditing.shownKinds(offering: later, for: .sound(name: "Glass", gainDB: 0)), [.sound, .speech])
        XCTAssertEqual(AlertEditing.shownKinds(offering: later, for: .speak(custom)), [.sound, .speech])
        // A hand-written later step that is silent keeps its own segment, so the
        // selection has a tag: a picker whose selection has none selects nothing.
        XCTAssertEqual(AlertEditing.shownKinds(offering: later, for: .silent), [.silent, .sound, .speech])
        XCTAssertEqual(AlertEditing.shownKinds(offering: later, for: nil), [.none, .sound, .speech])
        XCTAssertEqual(AlertEditing.shownKinds(offering: later,
                                               for: .soundAndSpeak(soundName: "Glass", soundGainDB: 0, speech: custom)),
                       [.sound, .speech], "a sound with speech is Sound")
        XCTAssertEqual(AlertEditing.shownKinds(offering: [], for: .speak(custom)), [.speech])
        XCTAssertEqual(AlertEditing.shownKinds(offering: [], for: nil), [.none])
        XCTAssertEqual(AlertEditing.shownKinds(offering: all.reversed(), for: nil), all, "the order is the picker's, not the caller's")
        XCTAssertEqual(AlertEditing.shownKinds(offering: [.speech, .sound, .sound], for: .silent), [.silent, .sound, .speech],
                       "and nothing is shown twice")
    }

    func testWhateverIsSelectedAlwaysHasASegment() {
        let alerts: [AlertAction?] = [nil, .silent, .sound(name: "Glass", gainDB: 0), .speak(custom),
                                      .soundAndSpeak(soundName: "Glass", soundGainDB: 0, speech: custom)]
        for role in [AlertEditing.Role.first, .repeating, .final] {
            for alert in alerts {
                let shown = AlertEditing.shownKinds(offering: AlertEditing.offeredKinds(for: role), for: alert)
                XCTAssertTrue(shown.contains(AlertEditing.kind(of: alert)), "\(role) holding \(String(describing: alert))")
            }
        }
    }

    // MARK: - Test Shortcut's notification

    func testTheShortcutTestNotificationHasFourNonEmptyFieldsThatEachSayItIsATest() {
        let note = AlertEditing.shortcutTestNotification
        for (name, field) in [("app", note.appNameGuess), ("title", note.title), ("subtitle", note.subtitle), ("body", note.body)] {
            XCTAssertFalse(field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name)
            XCTAssertTrue(field.lowercased().contains("test"), "\(name) says plainly that it is a test: \(field)")
        }
    }

    func testTheShortcutTestNotificationUsesNoneOfTheSamplesWords() {
        func words(_ note: CapturedNotification) -> Set<String> {
            let text = [note.appNameGuess, note.title, note.subtitle, note.body].joined(separator: " ")
            return Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        }
        let shared = words(AlertEditing.sampleNotification).intersection(words(AlertEditing.shortcutTestNotification))
        XCTAssertEqual(shared, [], "it must not read like the sample's incident")
        XCTAssertNotEqual(AlertEditing.shortcutTestNotification, AlertEditing.sampleNotification)
    }
}
