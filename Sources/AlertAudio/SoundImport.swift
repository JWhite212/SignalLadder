// Sources/AlertAudio/SoundImport.swift
import AVFoundation
import Foundation
import NotificationCore

/// Adds a sound the user chose to their own sounds folder.
///
/// The one place the app writes into that folder, so everything a file must
/// be is checked here, and before it is given its name: a file that is not
/// audio, is silent or runs too long would otherwise sit in the folder under
/// an audio name and be warned about by every rule that came to name it.
///
/// The bytes are copied, never linked, to a hidden name the library does not
/// list, and it is that copy that is checked and then renamed. So what was
/// checked is what is kept, whatever happens to the chosen file meanwhile, and
/// a copy that fails part way leaves nothing a rule could name.
public struct SoundImport {
    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case notAFile
        case unsupportedType(String)
        case badName
        case tooLarge
        case unreadable(String)
        case silent
        case tooLong
        /// macOS has a sound of this name, and a file of the user's would
        /// take its place for every rule that names it, the fallback included.
        case systemSound(String)
        /// The user already has a sound of this name. Not a failure: the
        /// question to ask before `add(_:replacing: true)`.
        case alreadyExists(String)
        case couldNotCopy(String)

        public var description: String {
            switch self {
            case .notAFile: return "That is not a file."
            case .unsupportedType(let type):
                let wanted = SoundImport.typesSentence
                return type.isEmpty ? "A sound must be one of \(wanted)."
                                    : "A .\(type) file cannot be used. A sound must be one of \(wanted)."
            case .badName: return "The file's name cannot be used as a sound's name. Rename it and add it again."
            case .tooLarge: return "The file is larger than \(SoundImport.maximumBytes / 1_048_576) MB."
            case .unreadable(let reason): return "The file could not be read as audio: \(reason)"
            case .silent: return "The file is silent."
            case .tooLong: return "The sound is longer than \(Int(SoundImport.maximumSeconds)) seconds."
            case .systemSound(let name):
                return "macOS has a sound called \(name). Rename the file and add it again."
            case .alreadyExists(let name): return "You already have a sound called \(name)."
            case .couldNotCopy(let reason): return "The sound could not be added: \(reason)"
            }
        }
    }

    /// The same limit playing has, so nothing is added that would not play.
    public static let maximumSeconds: Double = 30
    /// Far above thirty seconds of any format read here, and small enough to
    /// hold in memory once while it is copied.
    public static let maximumBytes = 64 * 1_048_576
    static let maximumNameLength = 100

    /// The file types a sound may be, in the order they are said.
    public static var fileExtensions: [String] { SoundLibrary.extensions.sorted() }

    static var typesSentence: String {
        let types = fileExtensions.map { ".\($0)" }
        return types.dropLast().joined(separator: ", ") + " or " + (types.last ?? "")
    }

    public let library: SoundLibrary

    public init(library: SoundLibrary) {
        self.library = library
    }

    /// Copies `source` into the user's sounds folder and returns the name a
    /// rule would say. Refuses with `.alreadyExists` when the user has a sound
    /// of that name and `replacing` is false; nothing is changed then.
    public func add(_ source: URL, replacing: Bool = false) -> Result<String, Refusal> {
        do {
            return .success(try copyIn(source, replacing: replacing))
        } catch let refusal as Refusal {
            return .failure(refusal)
        } catch {
            return .failure(.couldNotCopy(error.localizedDescription))
        }
    }

    /// Makes the user's sounds folder if it is not there, and returns it.
    @discardableResult
    public func makeFolder() throws -> URL {
        try FileManager.default.createDirectory(at: library.customDirectory, withIntermediateDirectories: true)
        return library.customDirectory
    }

    // MARK: - The steps

    private func copyIn(_ chosen: URL, replacing: Bool) throws -> String {
        let files = FileManager.default
        let source = chosen.resolvingSymlinksInPath()
        let values = try? source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else { throw Refusal.notAFile }

        let type = source.pathExtension.lowercased()
        guard SoundLibrary.extensions.contains(type) else { throw Refusal.unsupportedType(type) }
        guard let name = Self.soundName(for: source) else { throw Refusal.badName }
        guard let size = values?.fileSize, size <= Self.maximumBytes else { throw Refusal.tooLarge }

        if let system = library.systemName(matching: name) { throw Refusal.systemSound(system) }

        let folder = library.customDirectory.resolvingSymlinksInPath()
        let existing = library.customFiles(named: name)
        // The file chosen is one already in the folder: it is there, and is
        // not to be copied over itself.
        if existing.contains(where: { $0.resolvingSymlinksInPath().path == source.path }) { return name }
        if !existing.isEmpty && !replacing { throw Refusal.alreadyExists(existing[0].deletingPathExtension().lastPathComponent) }

        try makeFolder()
        // Hidden, so the library does not list it while it is being checked,
        // and with the type the file has, which the decoder goes by.
        let staged = folder.appendingPathComponent(".adding-\(UUID().uuidString).\(type)")
        defer { try? files.removeItem(at: staged) }
        do {
            let bytes = try Data(contentsOf: source, options: .mappedIfSafe)
            guard bytes.count <= Self.maximumBytes else { throw Refusal.tooLarge }
            try bytes.write(to: staged, options: .withoutOverwriting)
        } catch let refusal as Refusal {
            throw refusal
        } catch {
            throw Refusal.couldNotCopy(error.localizedDescription)
        }
        try Self.check(staged)

        let destination = folder.appendingPathComponent("\(name).\(type)")
        do {
            for old in existing { try files.removeItem(at: old) }
            try files.moveItem(at: staged, to: destination)
        } catch {
            throw Refusal.couldNotCopy(error.localizedDescription)
        }
        return name
    }

    /// The name a rule would say for `file`, or nil when it has none that is
    /// safe to give a file in the folder.
    static func soundName(for file: URL) -> String? {
        let name = file.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= maximumNameLength, !name.hasPrefix(".") else { return nil }
        let unsafe = CharacterSet(charactersIn: "/:\\").union(.controlCharacters).union(.newlines)
        guard name.unicodeScalars.allSatisfy({ !unsafe.contains($0) }) else { return nil }
        return name
    }

    /// Decodes the whole file, as playing does, and refuses what would not
    /// play: not audio, empty, too long or silent.
    static func check(_ url: URL) throws {
        let buffer: AVAudioPCMBuffer
        do {
            let file = try AVAudioFile(forReading: url)
            guard Double(file.length) <= maximumSeconds * file.processingFormat.sampleRate else { throw Refusal.tooLong }
            guard file.length > 0,
                  let read = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                              frameCapacity: AVAudioFrameCount(file.length)) else {
                throw Refusal.unreadable("it is empty")
            }
            try file.read(into: read)
            buffer = read
        } catch let refusal as Refusal {
            throw refusal
        } catch {
            throw Refusal.unreadable(error.localizedDescription)
        }
        guard let channels = buffer.floatChannelData else { throw Refusal.unreadable("its format cannot be converted") }
        var peak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(samples[i])) }
        }
        guard Loudness.appliedGainDB(forPeak: peak, ruleGainDB: 0) != nil else { throw Refusal.silent }
    }
}
