import Foundation
@testable import NotificationCore

extension CapturePipeline {
    /// A pipeline for a test, as the app builds one, with every input the test does not
    /// name doing nothing: no banner is the self-test, a sound plays, speech is not used,
    /// no escalation begins, no page is sounding, a snooze holds nothing and nothing joins. A test names only
    /// the inputs it is about, so an input added to `init` later is given its default
    /// here once and not at every construction (#155).
    static func forTest(
        isSelfTest: @escaping (String, [String]) -> Bool = { _, _ in false },
        playSound: @escaping SoundPlayer = { name, gain in .played(sound: name, gainDB: gain, outputSilent: false) },
        speak: @escaping SpeechPlayer = { _, _ in .couldNotSpeak("unused") },
        playAndSpeak: @escaping SoundAndSpeechPlayer = { _, _, _, _ in .couldNotSpeak("unused") },
        isPageSounding: @escaping () -> Bool = { false },
        beginEscalation: @escaping (Rule, CapturedNotification, UUID, AlertOutcome) -> Void = { _, _, _, _ in },
        holdForSnooze: @escaping (Rule) -> Bool = { _ in false },
        joinEscalation: @escaping (Rule, CapturedNotification) -> EscalationJoin? = { _, _ in nil },
        history: CaptureRingBuffer = CaptureRingBuffer()
    ) -> CapturePipeline {
        CapturePipeline(ownAppName: "SignalLadder", isSelfTest: isSelfTest, playSound: playSound, speak: speak,
                        playAndSpeak: playAndSpeak, isPageSounding: isPageSounding, beginEscalation: beginEscalation,
                        holdForSnooze: holdForSnooze, joinEscalation: joinEscalation, history: history)
    }
}
