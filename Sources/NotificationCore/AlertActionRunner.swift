// Sources/NotificationCore/AlertActionRunner.swift
import Foundation

/// Sets off an alert through the players the app injects, and says what
/// happened. The one path every tier's alert takes: tier 1 from
/// `CapturePipeline`, a tier 3 repeat and a tier 4 final alert from
/// `EscalationCoordinator` (M4 plan, ruling 7). A new alert cutting off one
/// still playing is `AlertPlayer`'s doing, the same for all of them, so
/// nothing here tracks who is playing.
public enum AlertActionRunner {
    public static func run(_ alert: AlertAction, for notification: CapturedNotification,
                           playSound: CapturePipeline.SoundPlayer,
                           speak: CapturePipeline.SpeechPlayer,
                           playAndSpeak: CapturePipeline.SoundAndSpeechPlayer) -> AlertOutcome {
        switch alert {
        case .silent: return .silentByRule
        case .sound(let name, let gainDB): return playSound(name, gainDB)
        case .speak(let speech): return speak(speech.rendered(for: notification), speech)
        case .soundAndSpeak(let name, let gainDB, let speech):
            return playAndSpeak(name, gainDB, speech.rendered(for: notification), speech)
        }
    }
}
