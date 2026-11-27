// Sources/NotificationCore/SoundChecks.swift
import Foundation

/// What a check's press does (sound editor plan, Ruling 12).
///
/// Said apart from `SoundEdit` because one press is not an edit: Undo goes back
/// through the history and makes no edit of its own, and which presses are on
/// offer is the window's to say, as it knows whether there is anything to undo.
public enum SoundFix: Equatable, Sendable {
    /// An edit to make to the recipe, which goes through the history as any
    /// other edit does and can be undone.
    case edit(SoundEdit)
    /// Go back one step.
    case undo
}

/// One thing the checks have to say about a sound, and the press that mends it.
public struct SoundFinding: Equatable, Sendable {
    /// What is the matter. In the order a window lists them: the two that stop a
    /// save first, because they are what has to be dealt with, then the advice in
    /// the order a sound is heard.
    public enum Kind: CaseIterable, Sendable {
        /// The whole result is below the silence floor.
        case nothingToHear
        /// The result is over 30 seconds.
        case tooLong
        /// It reaches half its peak in the first few milliseconds of being heard.
        case startsAbruptly
        /// It is under half a second.
        case tooShort
        /// A long stretch below the silence floor before it is heard.
        case silenceAtStart
        /// A long stretch below the silence floor after it is last heard.
        case silenceAtEnd
        /// A run of samples at full scale.
        case clipping
    }

    public let kind: Kind
    /// How many frames the finding is about, for the sentence that says it: the
    /// length of the whole result for `tooShort` and `tooLong`, the length of the
    /// silence for the two silences, and nil for the rest, which are about no
    /// length.
    public let frames: Int?
    /// The press that mends it, or nil when nothing a press could do would.
    public let fix: SoundFix?

    public init(kind: Kind, frames: Int?, fix: SoundFix?) {
        self.kind = kind
        self.frames = frames
        self.fix = fix
    }

    /// Whether Save is off while this stands: a sound that cannot be played or
    /// that is longer than the player plays. The others are advice.
    public var blocksSaving: Bool { kind == .nothingToHear || kind == .tooLong }
}

/// The seven checks of a sound the editor makes (sound editor plan, Ruling 12),
/// made of the samples of the result as last rendered. A check advises, and the
/// two that cannot be advised past, stop a save.
///
/// Every threshold is a named constant in `Limits`, and nowhere else: they are
/// provisional (O4), taken from summaries of standards and papers, and are set
/// by ear before release.
public enum SoundChecks {
    /// The figures the checks use. Times are in seconds and are made frames
    /// through `SampleBuffer.frames(seconds:)`, so that a boundary is one frame
    /// and reads the same everywhere.
    public enum Limits {
        /// A sound that reaches `abruptFractionOfPeak` of its peak in less than
        /// this, counted from where it is first heard, starts abruptly.
        public static let abruptWithinSeconds = 0.010
        public static let abruptFractionOfPeak: Float = 0.5
        /// How much of the start the press fades in.
        public static let abruptFadeSeconds = 0.030
        /// A sound shorter than this is too short.
        public static let shortestSeconds = 0.5
        /// What the press for too short makes of it: this many plays, this far apart.
        public static let shortRepeatTimes = 3
        public static let shortRepeatGapSeconds = 0.3
        /// Silence before a sound is heard, or after it, of more than this is reported.
        public static let leadingSilenceSeconds = 0.1
        public static let trailingSilenceSeconds = 0.25
        /// This many samples in a row in one channel at full scale are clipping.
        public static let clippedRunLength = 3
        /// A sample at or past this is at full scale. One step below 1.0 of a 16-bit
        /// file, so that the largest a 16-bit sound can be counts as it should.
        public static let clippedLevel: Float = 1 - 1 / 32768

        public static var abruptFrames: Int { SampleBuffer.frames(seconds: abruptWithinSeconds) }
        public static var abruptFadeFrames: Int { SampleBuffer.frames(seconds: abruptFadeSeconds) }
        public static var shortestFrames: Int { SampleBuffer.frames(seconds: shortestSeconds) }
        public static var shortRepeatGapFrames: Int { SampleBuffer.frames(seconds: shortRepeatGapSeconds) }
        public static var leadingSilenceFrames: Int { SampleBuffer.frames(seconds: leadingSilenceSeconds) }
        public static var trailingSilenceFrames: Int { SampleBuffer.frames(seconds: trailingSilenceSeconds) }
        /// The longest a result may be and be saved: what the player plays.
        public static var longestFrames: Int { SoundRecipe.savableFrames }
    }

    /// What there is to say about `samples`, which are what a recipe renders to,
    /// in the order of `SoundFinding.Kind`. Each press is an edit of frames of
    /// those samples, so it applies to the recipe they were rendered from.
    ///
    /// What cannot be heard is told only that, and that it is too long if it is:
    /// advice about the start, the end and the length of a sound that is not
    /// there would be noise. "Heard" is the player's own measure, a sample above
    /// `Loudness.silenceFloorDBFS` in either channel, so that a sound the check
    /// passes is one the player plays.
    public static func findings(in samples: SampleBuffer) -> [SoundFinding] {
        let frames = samples.frameCount
        var found: [SoundFinding] = []

        let audible = Loudness.isAudible(peak: samples.peak)
        if !audible {
            found.append(SoundFinding(kind: .nothingToHear, frames: nil, fix: .undo))
        }
        if frames > Limits.longestFrames {
            // Exactly the first 30 seconds, and not moved to a quiet point as a selection's edges are:
            // moving it later would leave the result over the limit it is over.
            found.append(SoundFinding(kind: .tooLong, frames: frames,
                                      fix: .edit(.trim(0..<Limits.longestFrames))))
        }
        guard audible, let first = firstHeard(in: samples), let last = lastHeard(in: samples) else { return found }

        // A fade of 30 ms from where it is first heard, and not from the first frame: a sound that
        // begins with a stretch of silence that is not long enough to report is as abrupt as any.
        let rise = framesToReach(Limits.abruptFractionOfPeak * samples.peak, from: first, in: samples)
        if rise < Limits.abruptFrames {
            found.append(SoundFinding(kind: .startsAbruptly, frames: rise,
                                      fix: .edit(.fadeIn(first..<min(first + Limits.abruptFadeFrames, frames)))))
        }
        if frames < Limits.shortestFrames {
            found.append(SoundFinding(kind: .tooShort, frames: frames,
                                      fix: .edit(.repeatSelection(0..<frames, times: Limits.shortRepeatTimes,
                                                                  gapFrames: Limits.shortRepeatGapFrames))))
        }
        if first > Limits.leadingSilenceFrames {
            found.append(SoundFinding(kind: .silenceAtStart, frames: first, fix: .edit(.trim(first..<frames))))
        }
        let trailing = frames - 1 - last
        if trailing > Limits.trailingSilenceFrames {
            found.append(SoundFinding(kind: .silenceAtEnd, frames: trailing, fix: .edit(.trim(0..<(last + 1)))))
        }
        if isClipped(samples) {
            // No press: the damage is in the sound itself, and the sentence says to start from a cleaner copy.
            found.append(SoundFinding(kind: .clipping, frames: nil, fix: nil))
        }
        return found
    }

    // MARK: - Reading the samples

    /// Whether any channel has a sample above the silence floor at `frame`.
    private static func isHeard(_ samples: SampleBuffer, at frame: Int) -> Bool {
        samples.channels.contains { Loudness.isAudible(peak: abs($0[frame])) }
    }

    /// The first frame that is heard, or nil when none is.
    private static func firstHeard(in samples: SampleBuffer) -> Int? {
        (0..<samples.frameCount).first { isHeard(samples, at: $0) }
    }

    /// The last frame that is heard, or nil when none is.
    private static func lastHeard(in samples: SampleBuffer) -> Int? {
        stride(from: samples.frameCount - 1, through: 0, by: -1).first { isHeard(samples, at: $0) }
    }

    /// How many frames after `start` the first sample at or above `level` in
    /// either channel comes. The sound's peak is a level it reaches, so there is
    /// always one, and a sound that is never that loud, which only a sample that
    /// is not a number could make, is as far away as its end.
    private static func framesToReach(_ level: Float, from start: Int, in samples: SampleBuffer) -> Int {
        for frame in start..<samples.frameCount where samples.channels.contains(where: { abs($0[frame]) >= level }) {
            return frame - start
        }
        return samples.frameCount - start
    }

    /// Whether any channel has `Limits.clippedRunLength` samples in a row at full scale.
    private static func isClipped(_ samples: SampleBuffer) -> Bool {
        for channel in samples.channels {
            var run = 0
            for sample in channel {
                run = abs(sample) >= Limits.clippedLevel ? run + 1 : 0
                if run >= Limits.clippedRunLength { return true }
            }
        }
        return false
    }
}
