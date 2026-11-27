// Sources/NotificationCore/SoundEdit.swift
import Foundation

/// Why an edit was not made. Each is a thing the window says, in words that live
/// in `SoundEditorText`; none changes the recipe.
public enum SoundEditRefusal: Error, Equatable, Sendable {
    /// The source is longer than a recipe may hold (Ruling 18). No sound that
    /// long can have been added; one put in the folder by hand is refused with
    /// its length.
    case sourceTooLong(frames: Int)
    /// The edit would take the result past 120 seconds (Ruling 11), carrying the
    /// length it would have been.
    case tooLong(frames: Int)
    /// The edit would leave nothing: deleting the whole result, or trimming to
    /// an empty selection (Ruling 18).
    case wouldLeaveNothing
    /// The edit works on a selection and there is none.
    case emptySelection
    /// The selection reaches before the start of the result or past its end.
    case selectionOutsideSound
    /// The edit would leave more pieces than a recipe may hold.
    case tooManyPieces
    /// The pieces to paste are of a different sound than the recipe is of.
    case excerptFromAnotherSound
    /// The gain is not a number, or the piece would end up beyond 60 decibels.
    case gainOutOfRange
    /// A repeat is of at least two plays and at most `SoundEdit.mostPlays`.
    case playsOutOfRange
    /// A gap between plays is negative, or longer than the longest result.
    case gapOutOfRange
}

/// Every edit the window can make, each a pure function from one recipe to the
/// next (Ruling 2).
///
/// A selection is a range of frames of the result as it is now. Where it begins
/// and ends is the model's to decide, moved to a quiet point beforehand
/// (Ruling 4), so an edit is arithmetic on the recipe and nothing else.
///
/// An edit that would break the recipe is refused and changes nothing:
/// - one that would leave nothing, or run past 120 seconds (Rulings 11 and 18);
/// - one that would leave more pieces than a recipe holds.
public enum SoundEdit: Equatable, Sendable {
    /// Keep the selection and drop the rest.
    case trim(Range<Int>)
    /// Take the selection out; what was after it moves up.
    case delete(Range<Int>)
    /// As `delete`. Its own case so the history and the menu can tell them
    /// apart; the copy it keeps is taken first, with `SoundRecipe.excerpt`.
    case cut(Range<Int>)
    /// Put the pieces in place of the selection, or at a point when the range is
    /// empty.
    case paste(SoundExcerpt, replacing: Range<Int>)
    /// Play the selection twice, the copy straight after it.
    case duplicate(Range<Int>)
    /// Ramp the selection up from silence, over its whole length.
    case fadeIn(Range<Int>)
    /// Ramp the selection down to silence, over its whole length.
    case fadeOut(Range<Int>)
    /// Raise or lower the selection by this many decibels. Only against the
    /// rest of the sound: how loud a sound plays is the player's (Ruling 16).
    case gain(Range<Int>, dB: Double)
    /// Play the selection `times` times in all, `gapFrames` of silence between
    /// each play and the next. The result is the selection `times` times, and
    /// `times - 1` gaps, in the selection's place.
    case repeatSelection(Range<Int>, times: Int, gapFrames: Int)

    /// The most plays a repeat may ask for.
    public static let mostPlays = 1000

    /// The recipe after this edit.
    public func applied(to recipe: SoundRecipe) throws -> SoundRecipe {
        switch self {
        case .trim(let range):
            // An empty selection keeps nothing, which `made` refuses as leaving nothing.
            try Self.checkBounds(range, in: recipe)
            return try Self.made(from: recipe, [recipe.partition(range).inside])

        case .delete(let range), .cut(let range):
            try Self.checkSelection(range, in: recipe)
            let parts = recipe.partition(range)
            return try Self.made(from: recipe, [parts.before, parts.after])

        case .paste(let excerpt, let range):
            try Self.checkBounds(range, in: recipe)
            guard excerpt.sourceDigest == recipe.source.digest else { throw SoundEditRefusal.excerptFromAnotherSound }
            try Self.checkLength(recipe.frameCount - range.count + excerpt.frameCount)
            let parts = recipe.partition(range)
            return try Self.made(from: recipe, [parts.before, excerpt.segments, parts.after])

        case .duplicate(let range):
            try Self.checkSelection(range, in: recipe)
            try Self.checkLength(recipe.frameCount + range.count)
            let parts = recipe.partition(range)
            return try Self.made(from: recipe, [parts.before, parts.inside, parts.inside, parts.after])

        case .fadeIn(let range):
            return try Self.faded(recipe, range, kind: .fadeIn)

        case .fadeOut(let range):
            return try Self.faded(recipe, range, kind: .fadeOut)

        case .gain(let range, let dB):
            try Self.checkSelection(range, in: recipe)
            guard dB.isFinite, abs(dB) <= SoundRecipe.maximumGainDB else { throw SoundEditRefusal.gainOutOfRange }
            let parts = recipe.partition(range)
            let changed = try parts.inside.map { segment -> SoundSegment in
                guard case .clip(let start, let end, let gainDB, let fades) = segment else { return segment }
                let total = SoundRecipe.rounded(gainDB: gainDB + dB)
                guard abs(total) <= SoundRecipe.maximumGainDB else { throw SoundEditRefusal.gainOutOfRange }
                return .clip(start: start, end: end, gainDB: total, fades: fades)
            }
            return try Self.made(from: recipe, [parts.before, changed, parts.after])

        case .repeatSelection(let range, let times, let gapFrames):
            try Self.checkSelection(range, in: recipe)
            guard (2...Self.mostPlays).contains(times) else { throw SoundEditRefusal.playsOutOfRange }
            guard (0...SoundRecipe.maximumFrames).contains(gapFrames) else { throw SoundEditRefusal.gapOutOfRange }
            // Counted before anything is built, so a request for a very long
            // result is refused without making it.
            try Self.checkLength(recipe.frameCount - range.count + times * range.count + (times - 1) * gapFrames)
            let parts = recipe.partition(range)
            // Pieces are counted too, for the same reason: a repeat of a
            // selection of many pieces, many times, is not built to be refused.
            guard parts.before.count + parts.after.count + times * parts.inside.count + (times - 1)
                <= SoundRecipe.maximumSegments else { throw SoundEditRefusal.tooManyPieces }
            var plays: [SoundSegment] = []
            for play in 0..<times {
                if play > 0, gapFrames > 0 { plays.append(.silence(frames: gapFrames)) }
                plays.append(contentsOf: parts.inside)
            }
            return try Self.made(from: recipe, [parts.before, plays, parts.after])
        }
    }

    // MARK: - Shared checks

    /// A selection that is inside the result, empty or not.
    static func checkBounds(_ range: Range<Int>, in recipe: SoundRecipe) throws {
        guard range.lowerBound >= 0, range.upperBound <= recipe.frameCount else {
            throw SoundEditRefusal.selectionOutsideSound
        }
    }

    /// A selection that is inside the result and has something in it.
    static func checkSelection(_ range: Range<Int>, in recipe: SoundRecipe) throws {
        try checkBounds(range, in: recipe)
        guard !range.isEmpty else { throw SoundEditRefusal.emptySelection }
    }

    /// A length a result may have: something, and no more than the longest.
    private static func checkLength(_ frames: Int) throws {
        guard frames >= 1 else { throw SoundEditRefusal.wouldLeaveNothing }
        guard frames <= SoundRecipe.maximumFrames else { throw SoundEditRefusal.tooLong(frames: frames) }
    }

    /// The recipe the pieces make, in order, with the checks that cannot be made
    /// before they are: that something is left, how long it is and how many
    /// pieces it has.
    private static func made(from recipe: SoundRecipe, _ parts: [[SoundSegment]]) throws -> SoundRecipe {
        let segments = parts.flatMap { $0 }
        try checkLength(segments.reduce(0) { $0 + $1.frames })
        let result = SoundRecipe(source: recipe.source, canonicalSegments: segments)
        guard result.segments.count <= SoundRecipe.maximumSegments else { throw SoundEditRefusal.tooManyPieces }
        return result
    }

    /// A fade over the whole selection. Each piece in it is under the one fade,
    /// at the place in it that the piece begins: a selection that runs across a
    /// join is one fade and not two. Silence in the selection is still part of
    /// the fade, and takes no fade of its own.
    private static func faded(_ recipe: SoundRecipe, _ range: Range<Int>, kind: SoundFade.Kind) throws -> SoundRecipe {
        try checkSelection(range, in: recipe)
        let parts = recipe.partition(range)
        var offset = 0
        let faded = parts.inside.map { segment -> SoundSegment in
            defer { offset += segment.frames }
            guard case .clip(let start, let end, let gainDB, let fades) = segment else { return segment }
            return .clip(start: start, end: end, gainDB: gainDB,
                         fades: fades + [SoundFade(kind: kind, frames: range.count, into: offset)])
        }
        return try made(from: recipe, [parts.before, faded, parts.after])
    }
}
