// Sources/NotificationCore/SoundRecipe.swift
import Foundation

/// A fade across a piece of a sound. Shaped so that a fade which runs across a
/// cut is still one fade (sound editor plan, Ruling 2).
///
/// A fade belongs to the material and not to the timeline: `frames` is its whole
/// length, and `into` is how many of those frames came before this piece's first
/// frame. A fade in over a second, laid across two pieces that were not
/// neighbours in the source, is the same fade on each, the second with `into`
/// at the length of the first. Cut a piece out of the middle of a fade and the
/// part after the cut goes on from where it would have been, so putting the cut
/// piece back puts the one fade back (the two merge, see `SoundRecipe`).
///
/// A fade always covers the whole piece it is on: an edit that fades part of a
/// piece first cuts the piece at the edges of the part. So `into` plus the
/// piece's length never passes `frames`.
public struct SoundFade: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case fadeIn = "in"
        case fadeOut = "out"
    }

    public let kind: Kind
    /// The length of the whole fade, in frames. At least 1.
    public let frames: Int
    /// How many frames of the fade lie before the piece's first frame.
    public let into: Int

    public init(kind: Kind, frames: Int, into: Int) {
        self.kind = kind
        self.frames = frames
        self.into = into
    }

    /// The multiplier on the frame `frame` frames into the piece this fade is
    /// on. A fade in starts at exactly 0 and a fade out ends at exactly 0, so a
    /// sound that begins with one begins at silence. Linear in amplitude. 1 for
    /// a frame the fade does not reach, which no valid piece has.
    public func gain(atPieceFrame frame: Int) -> Float {
        let index = into + frame
        guard frames > 0, index >= 0, index < frames else { return 1 }
        switch kind {
        case .fadeIn: return Float(index) / Float(frames)
        case .fadeOut: return Float(frames - 1 - index) / Float(frames)
        }
    }

    /// The order a piece keeps its fades in, so that two pieces with the same
    /// fades have them in the same order whatever order they were made in.
    static func precedes(_ lhs: SoundFade, _ rhs: SoundFade) -> Bool {
        if lhs.kind != rhs.kind { return lhs.kind == .fadeIn }
        if lhs.frames != rhs.frames { return lhs.frames < rhs.frames }
        return lhs.into < rhs.into
    }
}

/// One piece of a recipe: a stretch of the source, or a stretch of silence.
///
/// Positions are whole frames at 48 kHz (Ruling 3). The type itself is a plain
/// value; what makes a list of them sound is `SoundRecipe`, which is the only
/// thing that holds one and refuses a list that is not.
public enum SoundSegment: Equatable, Sendable {
    /// Frames `start` up to but not including `end` of the source, at `gainDB`
    /// decibels, under each of `fades`.
    case clip(start: Int, end: Int, gainDB: Double, fades: [SoundFade])
    case silence(frames: Int)

    /// How many frames this piece plays for.
    public var frames: Int {
        switch self {
        case .clip(let start, let end, _, _): return end - start
        case .silence(let frames): return frames
        }
    }

    /// The multiplier on the frame `frame` frames into this piece: its gain
    /// and every fade it is under, multiplied. 0 for silence. This is the one
    /// definition of what a piece does to the source, so a render and a test
    /// cannot read it differently.
    public func gain(atPieceFrame frame: Int) -> Float {
        switch self {
        case .silence:
            return 0
        case .clip(_, _, let gainDB, let fades):
            var gain = Float(pow(10, gainDB / 20))
            for fade in fades { gain *= fade.gain(atPieceFrame: frame) }
            return gain
        }
    }

    /// The part of this piece from frame `range.lowerBound` to
    /// `range.upperBound` of it. `range` must lie inside the piece and not be
    /// empty. The fades are kept as they were across the piece: a piece that
    /// loses its front gains that much `into`, so the part that is left is
    /// under the same fade at the same place in it.
    func slice(_ range: Range<Int>) -> SoundSegment {
        switch self {
        case .silence:
            return .silence(frames: range.count)
        case .clip(let start, _, let gainDB, let fades):
            return .clip(start: start + range.lowerBound, end: start + range.upperBound, gainDB: gainDB,
                         fades: fades.map { SoundFade(kind: $0.kind, frames: $0.frames, into: $0.into + range.lowerBound) })
        }
    }
}

/// How a sound was made from its source: an ordered list of pieces of it.
///
/// This is the whole of an edit (Ruling 2). It is not a log of what was done: it
/// is what the result is, so nothing in it can point at something an earlier edit
/// removed, and undo is a stack of these small values with no audio in them.
///
/// The list is sound by construction. No piece is empty, every piece lies inside
/// the source, no fade reaches past its piece, the whole is at most
/// `maximumFrames` long and has at most `maximumSegments` pieces, and neighbours
/// that are one piece cut in two are one piece. `segments` can be read and not
/// set; the one public way to make a list is `init(source:segments:)`, which
/// refuses one that breaks any of that and puts one that can be read two ways
/// into one form, and the edits in `SoundEdit` keep to it by construction.
public struct SoundRecipe: Equatable, Sendable {
    /// What a recipe is made from: the stored copy of the sound it started as.
    public struct Source: Equatable, Sendable {
        /// The name of the stored copy, which is what finds it again.
        public let name: String
        /// Its length in frames at 48 kHz, once decoded.
        public let frames: Int
        /// A digest of the stored copy's bytes, to tell it from another.
        public let digest: String

        /// nil for a source with no name, no digest or no frames: there would
        /// be nothing to find, to tell apart or to play.
        public init?(name: String, frames: Int, digest: String) {
            guard !name.isBlank, !digest.isBlank, frames >= 1 else { return nil }
            self.name = name
            self.frames = frames
            self.digest = digest
        }
    }

    /// Why a list of pieces is not a recipe. Said in plain sentences, since the
    /// one place a person meets them is a recipe file that cannot be read.
    public enum Fault: Error, Equatable, Sendable, CustomStringConvertible {
        case sourceTooLong(frames: Int)
        case noPieces
        case tooManyPieces(count: Int)
        case emptyPiece(index: Int)
        case pieceOutsideSource(index: Int)
        case badFade(index: Int)
        case badGain(index: Int)
        case tooLong(frames: Int)

        public var description: String {
            switch self {
            case .sourceTooLong(let frames):
                return "the source is \(frames) frames long, over the \(SoundRecipe.maximumFrames) a recipe may hold"
            case .noPieces:
                return "there are no pieces, so nothing would play"
            case .tooManyPieces(let count):
                return "there are \(count) pieces, over the \(SoundRecipe.maximumSegments) a recipe may hold"
            case .emptyPiece(let index):
                return "piece \(index + 1) is empty"
            case .pieceOutsideSource(let index):
                return "piece \(index + 1) is not inside the source"
            case .badFade(let index):
                return "piece \(index + 1) has a fade that starts before itself or runs past its own length"
            case .badGain(let index):
                return "piece \(index + 1) has a gain that is not a number, or is beyond \(Int(SoundRecipe.maximumGainDB)) decibels"
            case .tooLong(let frames):
                return "the result is \(frames) frames long, over the \(SoundRecipe.maximumFrames) a recipe may hold"
            }
        }
    }

    /// The longest a result may run while it is edited: 120 seconds (Ruling
    /// 11), which bounds the memory a render takes.
    public static let maximumFrames = 120 * SampleBuffer.sampleRate

    /// The longest a result may be and still be saved: 30 seconds, as long as
    /// the player plays (Ruling 11).
    public static let savableFrames = 30 * SampleBuffer.sampleRate

    /// The most pieces a recipe may hold. Far more than editing a sound by hand
    /// makes, and a bound on a repeat of a repeat of a very short selection.
    public static let maximumSegments = 4096

    /// The most gain, up or down, any piece may be given in total.
    public static let maximumGainDB: Double = 60

    /// Gain is kept to hundredths of a decibel, so that adding a gain and then
    /// taking it away gives back exactly the gain there was, and a gain that
    /// was undone by hand leaves no seam.
    static func rounded(gainDB: Double) -> Double { (gainDB * 100).rounded() / 100 }

    public let source: Source
    public private(set) var segments: [SoundSegment]

    /// Checks `segments` against everything a recipe holds and keeps them in
    /// the one form: gain in hundredths, fades in a fixed order, neighbours
    /// that are one piece cut in two made one again.
    public init(source: Source, segments: [SoundSegment]) throws {
        guard source.frames <= Self.maximumFrames else { throw Fault.sourceTooLong(frames: source.frames) }
        guard !segments.isEmpty else { throw Fault.noPieces }
        guard segments.count <= Self.maximumSegments else { throw Fault.tooManyPieces(count: segments.count) }
        var total = 0
        for (index, segment) in segments.enumerated() {
            switch segment {
            case .silence(let frames):
                guard frames >= 1 else { throw Fault.emptyPiece(index: index) }
            case .clip(let start, let end, let gainDB, let fades):
                guard end > start else { throw Fault.emptyPiece(index: index) }
                guard start >= 0, end <= source.frames else { throw Fault.pieceOutsideSource(index: index) }
                guard gainDB.isFinite, abs(gainDB) <= Self.maximumGainDB else { throw Fault.badGain(index: index) }
                // A file may hold any integer, so nothing here adds one that has not been bounded
                // first: the piece is inside the source, so `end - start` is small, and `frames` is
                // at least 1, so taking the piece from it cannot overflow either.
                for fade in fades
                where fade.frames < 1 || fade.into < 0 || fade.into > fade.frames - (end - start) {
                    throw Fault.badFade(index: index)
                }
            }
            // A silence may be any length a file says, so a total that passes the largest integer is
            // held there: it is over the longest a result may be all the same.
            let (sum, overflowed) = total.addingReportingOverflow(segment.frames)
            total = overflowed ? Int.max : sum
            guard total <= Self.maximumFrames else { throw Fault.tooLong(frames: total) }
        }
        self.source = source
        self.segments = Self.canonical(segments)
    }

    /// The recipe that is the whole source and nothing else: what a sound that
    /// was not made by the editor opens as, and what Reset to Original goes
    /// back to.
    public init(wholeOf source: Source) throws {
        guard source.frames <= Self.maximumFrames else { throw SoundEditRefusal.sourceTooLong(frames: source.frames) }
        self.source = source
        self.segments = [.clip(start: 0, end: source.frames, gainDB: 0, fades: [])]
    }

    /// Only for a list the caller has built by construction, as the edits do.
    init(source: Source, canonicalSegments: [SoundSegment]) {
        self.source = source
        self.segments = Self.canonical(canonicalSegments)
    }

    /// How many frames the result plays for.
    public var frameCount: Int { segments.reduce(0) { $0 + $1.frames } }

    public var duration: TimeInterval { SampleBuffer.seconds(frames: frameCount) }

    /// The whole source, as a recipe of the same source.
    public var original: SoundRecipe {
        SoundRecipe(source: source, canonicalSegments: [.clip(start: 0, end: source.frames, gainDB: 0, fades: [])])
    }

    /// Whether this is the source as it was, untouched.
    public var isOriginal: Bool { self == original }

    /// Whether the result is short enough to be saved (Ruling 11).
    public var canBeSaved: Bool { frameCount <= Self.savableFrames }

    // MARK: - Pieces

    /// The pieces that play from frame `range.lowerBound` to
    /// `range.upperBound` of the result, cut at the edges, for copying.
    ///
    /// - Throws: `SoundEditRefusal` when the range is empty or not inside the
    ///   result.
    public func excerpt(of range: Range<Int>) throws -> SoundExcerpt {
        try SoundEdit.checkSelection(range, in: self)
        return SoundExcerpt(sourceDigest: source.digest, segments: partition(range).inside)
    }

    /// The pieces before, inside and after `range`, with the pieces that
    /// straddle an edge cut in two. An empty `range` is a point: nothing is
    /// inside, and a piece that straddles it is cut there.
    func partition(_ range: Range<Int>) -> (before: [SoundSegment], inside: [SoundSegment], after: [SoundSegment]) {
        var before: [SoundSegment] = []
        var inside: [SoundSegment] = []
        var after: [SoundSegment] = []
        var position = 0
        for segment in segments {
            let length = segment.frames
            let end = position + length
            defer { position = end }
            if end <= range.lowerBound {
                before.append(segment)
            } else if position >= range.upperBound {
                after.append(segment)
            } else {
                let low = max(range.lowerBound, position) - position
                let high = min(range.upperBound, end) - position
                if low > 0 { before.append(segment.slice(0..<low)) }
                if high > low { inside.append(segment.slice(low..<high)) }
                if high < length { after.append(segment.slice(high..<length)) }
            }
        }
        return (before, inside, after)
    }

    // MARK: - One form

    /// Puts a list in its one form: gain in hundredths, fades in order,
    /// neighbours that are one piece cut in two made one.
    static func canonical(_ segments: [SoundSegment]) -> [SoundSegment] {
        var result: [SoundSegment] = []
        result.reserveCapacity(segments.count)
        for segment in segments {
            var piece = segment
            if case .clip(let start, let end, let gainDB, let fades) = segment {
                piece = .clip(start: start, end: end, gainDB: rounded(gainDB: gainDB),
                              fades: fades.sorted(by: SoundFade.precedes))
            }
            if let last = result.last, let joined = join(last, piece) {
                result[result.count - 1] = joined
            } else {
                result.append(piece)
            }
        }
        return result
    }

    /// One piece in place of two, when the two are one piece that was cut:
    /// silence beside silence, or two stretches of the source that meet, at the
    /// same gain, under fades that carry on from one to the other.
    private static func join(_ first: SoundSegment, _ second: SoundSegment) -> SoundSegment? {
        switch (first, second) {
        case (.silence(let a), .silence(let b)):
            return .silence(frames: a + b)
        case (.clip(let start, let middle, let gain, let fades), .clip(let next, let end, let nextGain, let nextFades)):
            guard middle == next, gain == nextGain, fades.count == nextFades.count else { return nil }
            for (fade, onward) in zip(fades, nextFades)
            where fade.kind != onward.kind || fade.frames != onward.frames || onward.into != fade.into + (middle - start) {
                return nil
            }
            return .clip(start: start, end: end, gainDB: gain, fades: fades)
        default:
            return nil
        }
    }
}

/// Pieces of a result, taken to be pasted. Only a value: a copy holds no audio,
/// as nothing in a recipe does.
public struct SoundExcerpt: Equatable, Sendable {
    /// The digest of the source the pieces are of, so that pieces of one sound
    /// are never pasted into another, where they would play something else.
    public let sourceDigest: String
    public let segments: [SoundSegment]

    init(sourceDigest: String, segments: [SoundSegment]) {
        self.sourceDigest = sourceDigest
        self.segments = segments
    }

    public var frameCount: Int { segments.reduce(0) { $0 + $1.frames } }
}
