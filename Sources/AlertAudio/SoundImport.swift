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
/// a copy that fails part way leaves nothing a rule could name. A sound it
/// replaces is set aside first and put back if the new one cannot take its
/// place, so a failure never costs the user the sound they had.
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
            case .tooLarge: return "The file is too large. A sound may be up to \(SoundImport.maximumBytes / 1_048_576) MB."
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

    /// The decoded size above which a file is refused unread: what a
    /// compressed file could otherwise make the app allocate.
    static let maximumDecodedBytes: Int64 = 256 * 1_048_576
    /// How old a staged copy must be before it is taken for one a crash left.
    static let staleAfter: TimeInterval = 600
    static let stagedPrefix = ".adding-"
    static let asidePrefix = ".replacing-"

    public let library: SoundLibrary
    /// The rename that gives the checked copy its name. A test makes it fail.
    var move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }

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

        // The type is the file's own, which the decoder goes by. The name is
        // the one the user chose it under, which for a link is the link's.
        let type = source.pathExtension.lowercased()
        guard SoundLibrary.extensions.contains(type) else { throw Refusal.unsupportedType(type) }
        guard let name = Self.soundName(for: chosen) else { throw Refusal.badName }
        guard let size = values?.fileSize, size <= Self.maximumBytes else { throw Refusal.tooLarge }

        if let system = library.systemName(matching: name) { throw Refusal.systemSound(system) }

        let folder = library.customDirectory.resolvingSymlinksInPath()
        let existing = library.customFiles(named: name)
        // The file chosen is one already in the folder: it is there, and is
        // not to be copied over itself.
        if existing.contains(where: { $0.resolvingSymlinksInPath().path == source.path }) { return name }
        if !existing.isEmpty && !replacing { throw Refusal.alreadyExists(existing[0].deletingPathExtension().lastPathComponent) }

        try makeFolder()
        Self.removeStaleStagedCopies(in: folder)
        // Hidden, so the library does not list it while it is being checked,
        // and with the type the file has, which the decoder goes by.
        let staged = folder.appendingPathComponent("\(Self.stagedPrefix)\(UUID().uuidString).\(type)")
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

        // The sounds it replaces are set aside under hidden names, not
        // deleted, until the new one has its name; if it cannot be given it,
        // each is put back.
        let destination = folder.appendingPathComponent("\(name).\(type)")
        var aside: [(original: URL, hidden: URL)] = []
        do {
            for old in existing {
                let hidden = folder.appendingPathComponent(
                    "\(Self.asidePrefix)\(UUID().uuidString).\(old.pathExtension)")
                try files.moveItem(at: old, to: hidden)
                aside.append((old, hidden))
            }
            try move(staged, destination)
        } catch {
            for pair in aside.reversed() { try? files.moveItem(at: pair.hidden, to: pair.original) }
            throw Refusal.couldNotCopy(error.localizedDescription)
        }
        for pair in aside { try? files.removeItem(at: pair.hidden) }
        return name
    }

    /// Removes staged copies a crash left in the folder. Only names this type
    /// gives, and only ones old enough not to be another add under way.
    static func removeStaleStagedCopies(in folder: URL, now: Date = Date()) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.lastPathComponent.hasPrefix(stagedPrefix) {
            guard let changed = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(changed) > staleAfter else { continue }
            try? FileManager.default.removeItem(at: file)
        }
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
            let decodedBytes = file.length * Int64(file.processingFormat.channelCount) * 4
            guard decodedBytes <= maximumDecodedBytes else { throw Refusal.tooLarge }
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
