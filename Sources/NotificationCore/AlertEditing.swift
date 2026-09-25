// Sources/NotificationCore/AlertEditing.swift
import Foundation

/// How the rule editor's alert controls change a rule's alert, as pure
/// functions. Kept out of the view so every transition is tested, and so the
/// view cannot lose what the user typed: speech set up and then switched off
/// comes back when it is switched on again.
public enum AlertEditing {
    public enum Kind: Hashable, Sendable { case none, silent, sound, speech }

    /// Sound covers a sound alone and a sound with speech after it, which the
    /// editor shows as Sound with "Also speak it" on.
    public static func kind(of alert: AlertAction?) -> Kind {
        switch alert {
        case nil: return .none
        case .silent: return .silent
        case .sound, .soundAndSpeak: return .sound
        case .speak: return .speech
        }
    }

    /// The alert after choosing `kind`, and the speech to remember. Speech a
    /// choice sets aside is remembered, so choosing it again restores it.
    public static func choosing(_ kind: Kind, from alert: AlertAction?, remembered: SpeechAction?,
                                defaultSound: String, defaultVoice: String) -> (alert: AlertAction?, remembered: SpeechAction?) {
        let keep = alert?.speech ?? remembered
        switch kind {
        case .none:
            return (nil, keep)
        case .silent:
            return (.silent, keep)
        case .sound:
            switch alert {
            case .sound, .soundAndSpeak: return (alert, remembered)
            default: return (.sound(name: defaultSound, gainDB: 0), keep)
            }
        case .speech:
            if case .speak = alert { return (alert, remembered) }
            return (.speak(keep ?? SpeechAction(voiceIdentifier: defaultVoice)), keep)
        }
    }

    /// "Also speak it", on a sound: adds the remembered speech, or new speech
    /// in the default voice; switched off, sets the speech aside.
    public static func settingAlsoSpeak(_ on: Bool, on alert: AlertAction?, remembered: SpeechAction?,
                                        defaultVoice: String) -> (alert: AlertAction?, remembered: SpeechAction?) {
        switch (on, alert) {
        case (true, .sound(let name, let gainDB)?):
            return (.soundAndSpeak(soundName: name, soundGainDB: gainDB,
                                   speech: remembered ?? SpeechAction(voiceIdentifier: defaultVoice)), remembered)
        case (false, .soundAndSpeak(let name, let gainDB, let speech)?):
            return (.sound(name: name, gainDB: gainDB), speech)
        default:
            return (alert, remembered)
        }
    }

    /// The same alert with a different sound or sound gain; unchanged when it
    /// has no sound.
    public static func replacingSound(in alert: AlertAction?, name: String? = nil, gainDB: Double? = nil) -> AlertAction? {
        switch alert {
        case .sound(let oldName, let oldGain)?:
            return .sound(name: name ?? oldName, gainDB: gainDB ?? oldGain)
        case .soundAndSpeak(let oldName, let oldGain, let speech)?:
            return .soundAndSpeak(soundName: name ?? oldName, soundGainDB: gainDB ?? oldGain, speech: speech)
        default:
            return alert
        }
    }

    /// The same alert with different speech; unchanged when it does not speak.
    public static func replacingSpeech(in alert: AlertAction?, with speech: SpeechAction) -> AlertAction? {
        switch alert {
        case .speak?: return .speak(speech)
        case .soundAndSpeak(let name, let gainDB, _)?: return .soundAndSpeak(soundName: name, soundGainDB: gainDB, speech: speech)
        default: return alert
        }
    }

    /// What Test Speech says: the rule's template, filled from a made-up
    /// notification, so trying a voice never reads out a real one.
    public static let sampleNotification = CapturedNotification(
        timestamp: Date(timeIntervalSince1970: 0), appNameGuess: "Microsoft Teams",
        title: "Priya mentioned you in Incident Bridge", subtitle: "",
        body: "Can you look at the rollback plan before we page the database team?",
        rawText: "", subrole: "AXNotificationCenterBanner")
}
