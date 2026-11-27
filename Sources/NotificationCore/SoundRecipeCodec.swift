// Sources/NotificationCore/SoundRecipeCodec.swift
import Foundation

/// Reads and writes a recipe file: `{"version": 1, "source": {…}, "segments":
/// […], "rendered": {…}}`.
///
/// It is `RuleSetCodec`'s counterpart for a sound (Ruling 1): versioned, unknown
/// keys refused at every level, and a newer version reported as needing a newer
/// SignalLadder and not read in part. Pure — bytes in, a recipe out. The file
/// itself is read and written by `AlertAudio`, because `NotificationCore` may
/// not touch the file system (`PurityTests`).
///
/// A recipe that cannot be read changes nothing about what plays: the sound it
/// was made for is a plain file, and the editor opens it as a new source.
/// So nothing here ever stops a sound, and a refusal is only ever a reason the
/// edits cannot be reopened.
///
/// The file also says how long the sound it rendered is and a digest of it
/// (Ruling 10), so that a sound replaced outside the editor is not taken for
/// the one the recipe made. The length is always the recipe's, so it is not held
/// twice: the file carries it for a reader that wants to compare before decoding
/// anything, and `decode` refuses a file whose two lengths differ.
public enum SoundRecipeCodec {
    public static let currentVersion = 1

    /// A recipe, and the digest of the file it rendered. The length of that file
    /// is the recipe's.
    public struct Stored: Equatable, Sendable {
        public let recipe: SoundRecipe
        public let renderedDigest: String

        public init(recipe: SoundRecipe, renderedDigest: String) {
            self.recipe = recipe
            self.renderedDigest = renderedDigest
        }

        /// The length in frames of the file the recipe rendered.
        public var renderedFrames: Int { recipe.frameCount }
    }

    /// Failures that leave no recipe.
    public enum FileError: Error, Equatable, Sendable {
        case unreadable(String)
        /// Written by a newer SignalLadder than this one.
        case unsupportedVersion(Int)
    }

    /// Stable output: sorted keys and pretty printing, as the rules file has.
    public static func encode(_ stored: Stored) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Wire(stored))
    }

    /// The version is read before anything else is. A newer file may shape
    /// everything differently, and reading it as today's would give a list of
    /// misleading faults in place of the one true fact: this file is newer than
    /// this app.
    public static func decode(_ data: Data) throws -> Stored {
        let decoder = JSONDecoder()
        let version: Int
        do {
            version = try decoder.decode(VersionProbe.self, from: data).version
        } catch {
            throw FileError.unreadable(RuleSetCodec.describe(error))
        }
        guard version <= currentVersion else { throw FileError.unsupportedVersion(version) }
        guard version >= 1 else { throw FileError.unreadable("\"version\" must be 1 or higher, found \(version)") }

        let wire: Wire
        do {
            wire = try decoder.decode(Wire.self, from: data)
        } catch {
            throw FileError.unreadable(RuleSetCodec.describe(error))
        }
        return try wire.stored()
    }

    // MARK: - Wire shape

    private struct VersionProbe: Decodable {
        let version: Int
    }

    private struct Wire: Codable {
        let version: Int
        let source: SourceWire
        let segments: [SegmentWire]
        let rendered: RenderedWire

        private enum Key: String, CodingKey, CaseIterable { case version, source, segments, rendered }

        init(_ stored: Stored) {
            version = SoundRecipeCodec.currentVersion
            source = SourceWire(stored.recipe.source)
            segments = stored.recipe.segments.map(SegmentWire.init)
            rendered = RenderedWire(frames: stored.renderedFrames, digest: stored.renderedDigest)
        }

        init(from decoder: Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: Key.allCases.map(\.rawValue), in: "a recipe")
            let container = try decoder.container(keyedBy: Key.self)
            version = try container.decode(Int.self, forKey: .version)
            source = try container.decode(SourceWire.self, forKey: .source)
            segments = try container.decode([SegmentWire].self, forKey: .segments)
            rendered = try container.decode(RenderedWire.self, forKey: .rendered)
        }

        /// What the file says, as a recipe, or why it cannot be one.
        func stored() throws -> Stored {
            guard let source = SoundRecipe.Source(name: source.name, frames: source.frames, digest: source.digest) else {
                throw FileError.unreadable("its source has no name, no digest or no frames")
            }
            let recipe: SoundRecipe
            do {
                recipe = try SoundRecipe(source: source, segments: segments.map(\.segment))
            } catch {
                throw FileError.unreadable("\(error)")
            }
            guard !rendered.digest.isBlank else { throw FileError.unreadable("the rendered sound has no digest") }
            guard rendered.frames == recipe.frameCount else {
                throw FileError.unreadable(
                    "it says the rendered sound is \(rendered.frames) frames long, but its pieces make \(recipe.frameCount)")
            }
            return Stored(recipe: recipe, renderedDigest: rendered.digest)
        }
    }

    private struct SourceWire: Codable {
        let name: String
        let frames: Int
        let digest: String

        private enum Key: String, CodingKey, CaseIterable { case name, frames, digest }

        init(_ source: SoundRecipe.Source) {
            name = source.name
            frames = source.frames
            digest = source.digest
        }

        init(from decoder: Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: Key.allCases.map(\.rawValue), in: "\"source\"")
            let container = try decoder.container(keyedBy: Key.self)
            name = try container.decode(String.self, forKey: .name)
            frames = try container.decode(Int.self, forKey: .frames)
            digest = try container.decode(String.self, forKey: .digest)
        }
    }

    private struct RenderedWire: Codable {
        let frames: Int
        let digest: String

        private enum Key: String, CodingKey, CaseIterable { case frames, digest }

        init(frames: Int, digest: String) {
            self.frames = frames
            self.digest = digest
        }

        init(from decoder: Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: Key.allCases.map(\.rawValue), in: "\"rendered\"")
            let container = try decoder.container(keyedBy: Key.self)
            frames = try container.decode(Int.self, forKey: .frames)
            digest = try container.decode(String.self, forKey: .digest)
        }
    }

    /// `{"type": "clip", "start": 0, "end": 480, "gainDB": 0, "fades": []}` or
    /// `{"type": "silence", "frames": 480}`.
    private struct SegmentWire: Codable {
        let segment: SoundSegment

        private enum Key: String, CodingKey, CaseIterable { case type, start, end, gainDB, fades, frames }

        init(_ segment: SoundSegment) { self.segment = segment }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            switch try container.decode(String.self, forKey: .type) {
            case "clip":
                try rejectUnknownKeys(decoder, allowed: ["type", "start", "end", "gainDB", "fades"], in: "a clip")
                segment = .clip(start: try container.decode(Int.self, forKey: .start),
                                end: try container.decode(Int.self, forKey: .end),
                                gainDB: try container.decode(Double.self, forKey: .gainDB),
                                fades: try container.decode([FadeWire].self, forKey: .fades).map(\.fade))
            case "silence":
                try rejectUnknownKeys(decoder, allowed: ["type", "frames"], in: "a silence")
                segment = .silence(frames: try container.decode(Int.self, forKey: .frames))
            case let other:
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "unknown piece type \"\(other)\" — expected \"clip\" or \"silence\""))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            switch segment {
            case .clip(let start, let end, let gainDB, let fades):
                try container.encode("clip", forKey: .type)
                try container.encode(start, forKey: .start)
                try container.encode(end, forKey: .end)
                try container.encode(gainDB, forKey: .gainDB)
                try container.encode(fades.map(FadeWire.init), forKey: .fades)
            case .silence(let frames):
                try container.encode("silence", forKey: .type)
                try container.encode(frames, forKey: .frames)
            }
        }
    }

    /// `{"kind": "in", "frames": 480, "into": 0}`.
    private struct FadeWire: Codable {
        let fade: SoundFade

        private enum Key: String, CodingKey, CaseIterable { case kind, frames, into }

        init(_ fade: SoundFade) { self.fade = fade }

        init(from decoder: Decoder) throws {
            try rejectUnknownKeys(decoder, allowed: Key.allCases.map(\.rawValue), in: "a fade")
            let container = try decoder.container(keyedBy: Key.self)
            let name = try container.decode(String.self, forKey: .kind)
            guard let kind = SoundFade.Kind(rawValue: name) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "unknown fade kind \"\(name)\" — expected \"in\" or \"out\""))
            }
            fade = SoundFade(kind: kind, frames: try container.decode(Int.self, forKey: .frames),
                             into: try container.decode(Int.self, forKey: .into))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            try container.encode(fade.kind.rawValue, forKey: .kind)
            try container.encode(fade.frames, forKey: .frames)
            try container.encode(fade.into, forKey: .into)
        }
    }
}
