// Sources/NotificationCore/AlertEditing.swift
import Foundation

/// How the rule editor's alert controls change a rule's alert, as pure
/// functions. Kept out of the view so every transition is tested, and so the
/// view cannot lose what the user chose: speech or a sound set aside comes
/// back when it is chosen again.
public enum AlertEditing {
    public enum Kind: Hashable, Sendable { case none, silent, sound, speech }

    /// Which alert of a rule an editor is for. What the editor says about the
    /// alert, and which kinds it offers, follow the role.
    public enum Role: Equatable, Sendable {
        /// The alert that plays when a notification matches (tier 1).
        case first
        /// The alert a ladder repeats (tier 3).
        case repeating
        /// The alert a ladder ends on (tier 4).
        case final
    }

    /// The order the picker's segments are shown in, whichever are offered.
    public static let segmentOrder: [Kind] = [.none, .silent, .sound, .speech]

    /// The kinds an alert's picker offers. The first alert offers all four.
    /// A later step offers Sound and Speech only: No Alert and Silent belong
    /// to tier 1, since a later step with no action is that step switched off
    /// and a silent one is refused when the rules load.
    public static func offeredKinds(for role: Role) -> [Kind] {
        switch role {
        case .first: return segmentOrder
        case .repeating, .final: return [.sound, .speech]
        }
    }

    /// The segments a picker shows: those offered, and the kind the alert
    /// already is, whether or not it is offered, in `segmentOrder`. A picker
    /// whose selection has no segment selects nothing, so a hand-written
    /// later step that holds a silent alert still shows a Silent segment.
    public static func shownKinds(offering offered: [Kind], for alert: AlertAction?) -> [Kind] {
        let held = kind(of: alert)
        return segmentOrder.filter { offered.contains($0) || $0 == held }
    }

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

    /// What a choice sets aside, so choosing back restores it rather than a
    /// default: the speech, and the sound with its gain.
    public struct SetAside: Equatable, Sendable {
        public var speech: SpeechAction?
        public var sound: (name: String, gainDB: Double)?

        public init(speech: SpeechAction? = nil, sound: (name: String, gainDB: Double)? = nil) {
            self.speech = speech
            self.sound = sound
        }

        public static func == (a: SetAside, b: SetAside) -> Bool {
            a.speech == b.speech && a.sound?.name == b.sound?.name && a.sound?.gainDB == b.sound?.gainDB
        }

        /// Adds what `alert` holds, keeping what was set aside before.
        func keeping(_ alert: AlertAction?) -> SetAside {
            var kept = self
            if let speech = alert?.speech { kept.speech = speech }
            switch alert {
            case .sound(let name, let gainDB)?, .soundAndSpeak(let name, let gainDB, _)?: kept.sound = (name, gainDB)
            default: break
            }
            return kept
        }
    }

    /// The alert after choosing `kind`, and what is now set aside.
    public static func choosing(_ kind: Kind, from alert: AlertAction?, setAside: SetAside,
                                defaultSound: String, defaultVoice: String) -> (alert: AlertAction?, setAside: SetAside) {
        let kept = setAside.keeping(alert)
        switch kind {
        case .none:
            return (nil, kept)
        case .silent:
            return (.silent, kept)
        case .sound:
            switch alert {
            case .sound, .soundAndSpeak: return (alert, setAside)
            default:
                let sound = kept.sound ?? (defaultSound, 0)
                return (.sound(name: sound.name, gainDB: sound.gainDB), kept)
            }
        case .speech:
            if case .speak = alert { return (alert, setAside) }
            return (.speak(kept.speech ?? SpeechAction(voiceIdentifier: defaultVoice)), kept)
        }
    }

    /// "Also speak it", on a sound: adds the speech set aside, or new speech
    /// in the default voice; switched off, sets the speech aside.
    public static func settingAlsoSpeak(_ on: Bool, on alert: AlertAction?, setAside: SetAside,
                                        defaultVoice: String) -> (alert: AlertAction?, setAside: SetAside) {
        switch (on, alert) {
        case (true, .sound(let name, let gainDB)?):
            return (.soundAndSpeak(soundName: name, soundGainDB: gainDB,
                                   speech: setAside.speech ?? SpeechAction(voiceIdentifier: defaultVoice)), setAside)
        case (false, .soundAndSpeak(let name, let gainDB, let speech)?):
            var kept = setAside
            kept.speech = speech
            return (.sound(name: name, gainDB: gainDB), kept)
        default:
            return (alert, setAside)
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

    /// What Test Shortcut hands a Shortcut: the four fields a Shortcut reads,
    /// each saying plainly that it is a test. Not `sampleNotification`, which
    /// reads like a real incident: a Shortcut that messages a colleague would
    /// deliver it as one. None of its words are the sample's.
    public static let shortcutTestNotification = CapturedNotification(
        timestamp: Date(timeIntervalSince1970: 0), appNameGuess: "SignalLadder (test)",
        title: "TEST: not a real notification", subtitle: "Sent by Test Shortcut",
        body: "This is only a test of your Shortcut. No notification arrived.",
        rawText: "", subrole: "AXNotificationCenterBanner")
}
