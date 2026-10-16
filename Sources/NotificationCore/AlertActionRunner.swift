// Sources/NotificationCore/AlertActionRunner.swift
import Foundation

/// Sets off an alert through the players the app injects, and says what
/// happened. The one path every tier's alert takes: tier 1 from
/// `CapturePipeline`, a tier 3 repeat and a tier 4 final alert from
/// `EscalationCoordinator` (M4 plan, ruling 7). A new alert cutting off one
/// still playing is `AlertPlayer`'s doing, the same for all of them, so
/// nothing here tracks who is playing.
public enum AlertActionRunner {
    /// What plays when a rule's own alert would make no sound at all. One of the
    /// sounds in `/System/Library/Sounds`, which every Mac has, so it is not
    /// missing for the reason a rule's own sound may be.
    ///
    /// A rule whose sound or voice cannot be played stays in effect, with a
    /// warning (`RuleWarnings`), rather than being refused. Refused, it let the
    /// rules below it take its matches, and a silent catch-all beneath it kept
    /// the page quiet (finding of 2026-10-16). In effect, it must still sound.
    public static let fallbackSound = "Sosumi"

    public static func run(_ alert: AlertAction, for notification: CapturedNotification,
                           playSound: CapturePipeline.SoundPlayer,
                           speak: CapturePipeline.SpeechPlayer,
                           playAndSpeak: CapturePipeline.SoundAndSpeechPlayer) -> AlertOutcome {
        switch alert {
        case .silent:
            return .silentByRule
        case .sound(let name, let gainDB):
            return orFallback(playSound(name, gainDB), gainDB: gainDB, playSound: playSound)
        case .speak(let speech):
            return orFallback(speak(speech.rendered(for: notification), speech), gainDB: speech.gainDB,
                              playSound: playSound)
        case .soundAndSpeak(let name, let gainDB, let speech):
            return orFallback(playAndSpeak(name, gainDB, speech.rendered(for: notification), speech), gainDB: gainDB,
                              playSound: playSound)
        }
    }

    /// The outcome as it was, unless it made no sound at all: then the fallback,
    /// at the alert's own gain, and an outcome that says first what the rule's
    /// alert met and then what played in its place. Half an alert is a sound, and
    /// its outcome already says which half failed, so it is left as it is. Speech
    /// whose voice is gone is never said in another voice, which would be someone
    /// else's voice instead of a report (`AlertPlayer.installedVoice`): a sound
    /// plays instead, and the row says why. A fallback that cannot play either,
    /// as when the output itself fails, leaves the failure the rule's alert met.
    private static func orFallback(_ outcome: AlertOutcome, gainDB: Double,
                                   playSound: CapturePipeline.SoundPlayer) -> AlertOutcome {
        let reason: String
        let couldNotSpeak: Bool
        switch outcome {
        case .failed(let failure): (reason, couldNotSpeak) = (failure, false)
        case .couldNotSpeak(let failure): (reason, couldNotSpeak) = (failure, true)
        case .played, .spoke, .playedAndSpoke, .playedButNotSpoken, .spokeButNotPlayed, .playedFallback,
             .silentByRule, .noAlertSet, .snoozed, .joinedEscalation:
            return outcome
        }
        guard case .played(let sound, let fallbackGainDB, let silent) = playSound(fallbackSound, gainDB) else {
            return outcome
        }
        return .playedFallback(sound: sound, gainDB: fallbackGainDB, reason: reason, couldNotSpeak: couldNotSpeak,
                               outputSilent: silent)
    }
}
