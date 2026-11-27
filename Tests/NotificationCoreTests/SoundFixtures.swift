import XCTest
@testable import NotificationCore

/// What the sound editor's recipe tests are built from: a source, a recipe of
/// pieces of it, and the gain at a frame of the result.
enum SoundFixtures {
    static func source(_ frames: Int = 1000, digest: String = "digest-1") -> SoundRecipe.Source {
        SoundRecipe.Source(name: "source.wav", frames: frames, digest: digest)!
    }

    /// The whole of a source of `frames` frames, untouched.
    static func whole(_ frames: Int = 1000) -> SoundRecipe {
        try! SoundRecipe(wholeOf: source(frames))
    }

    /// A recipe of these pieces of a source of `frames` frames.
    static func recipe(_ segments: [SoundSegment], frames: Int = 10_000) -> SoundRecipe {
        try! SoundRecipe(source: source(frames), segments: segments)
    }

    static func clip(_ start: Int, _ end: Int, gain: Double = 0, fades: [SoundFade] = []) -> SoundSegment {
        .clip(start: start, end: end, gainDB: gain, fades: fades)
    }

    /// The multiplier a recipe gives the frame `frame` of its result.
    static func gain(_ recipe: SoundRecipe, at frame: Int) -> Float {
        var position = 0
        for segment in recipe.segments {
            if frame < position + segment.frames { return segment.gain(atPieceFrame: frame - position) }
            position += segment.frames
        }
        return 0
    }

    /// What an edit was refused for, or nil when it was made.
    static func refusal(_ edit: SoundEdit, _ recipe: SoundRecipe, file: StaticString = #filePath,
                        line: UInt = #line) -> SoundEditRefusal? {
        do {
            _ = try edit.applied(to: recipe)
            return nil
        } catch let refusal as SoundEditRefusal {
            return refusal
        } catch {
            XCTFail("\(error)", file: file, line: line)
            return nil
        }
    }
}
