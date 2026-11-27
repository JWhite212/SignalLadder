// Sources/NotificationCore/WaveformKeys.swift
import Foundation

/// A key the waveform answers to (sound editor plan, Ruling 13).
public enum WaveformKey: Equatable, Sendable {
    case space, left, right, home, end
}

/// What a key came to, for the window to act on.
public enum WaveformKeyOutcome: Equatable, Sendable {
    /// Play, or stop if it is playing. Nothing moved.
    case togglePlayback
    /// The playhead, and perhaps the selection and the view, moved.
    case moved
}

/// What each key does to the waveform's positions. The view says only which key it was and whether Shift was held,
/// so every case is a test and none is a line of the view.
public enum WaveformKeys {
    /// Space plays and stops. The arrows move the playhead by a step of what is shown, and Home and End go to the
    /// ends of the sound. With `extending`, which is Shift, a move selects from where it began, and without it a
    /// move clears the selection. The view is moved to keep the playhead in sight.
    public static func apply(_ key: WaveformKey, extending: Bool, timeline: inout SoundTimeline,
                             viewport: inout WaveformViewport) -> WaveformKeyOutcome {
        let target: Int
        switch key {
        case .space: return .togglePlayback
        case .left: target = timeline.playhead - viewport.stepFrames
        case .right: target = timeline.playhead + viewport.stepFrames
        case .home: target = 0
        case .end: target = timeline.length
        }
        timeline.moveHead(to: target, extending: extending)
        viewport.reveal(timeline.playhead)
        return .moved
    }

    /// Whether a key that is held down is answered again each time it repeats. The arrows are, so that holding one
    /// walks the playhead along. Space is not: it would play and stop at the rate keys repeat, and where it came to
    /// rest would be down to how long it was held. Home and End go where they went the first time.
    public static func takesRepeat(_ key: WaveformKey) -> Bool {
        switch key {
        case .left, .right: return true
        case .space, .home, .end: return false
        }
    }
}
