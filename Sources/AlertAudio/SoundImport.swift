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
/// a copy that fails part way leaves nothing a rule could name. Giving the
/// checked copy its name is `SoundInstall`'s, which saving an edited sound
/// calls too: a sound it replaces is set aside first and put back if the new
/// one cannot take its place, so a failure never costs the user the sound they
/// had, and `recoverSetAsideSounds` finishes a replace the app stopped.
public struct SoundImport {
    public enum Refusal: Error, Equatable, Sendable, CustomStringConvertible {
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
        /// The sound it would replace cannot be set aside under a name that
        /// says what it was, so it is not replaced: set aside any other way,
        /// a stop at the wrong moment could not put it back.
        case cannotSetAside(String)
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
            case .cannotSetAside(let name):
                return "Your sound \(name) has too long a name to be replaced safely. Give it a shorter name in your sounds folder, then add this again."
            case .couldNotCopy(let reason): return "The sound could not be added: \(reason)"
            }
        }
    }

    /// The same limit playing has, so nothing is added that would not play.
    public static let maximumSeconds: Double = 30
    /// Far above thirty seconds of any format read here, and small enough to
    /// hold in memory once while it is copied.
    public static let maximumBytes = 64 * 1_048_576

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
    static let staleAfter = SoundInstall.staleAfter
    static let stagedPrefix = SoundInstall.addingPrefix
    static let asidePrefix = SoundInstall.asidePrefix

    public let library: SoundLibrary
    /// The rename that gives the checked copy its name, handed to
    /// `SoundInstall`. A test makes it fail.
    var move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }

    public init(library: SoundLibrary) {
        self.library = library
    }

    /// Copies `source` into the user's sounds folder and returns the name a
    /// rule would say. Refuses with `.alreadyExists` when the user has a sound
    /// of that name and `replacing` is false; nothing is changed then.
    public func add(_ source: URL, replacing: Bool = false) -> Result<String, Refusal> {
        switch stage(source, replacing: replacing) {
        case .failure(let refusal): return .failure(refusal)
        case .success(let staging): return install(staging, replacing: replacing)
        }
    }

    /// Makes the user's sounds folder if it is not there, and returns it.
    @discardableResult
    public func makeFolder() throws -> URL {
        try FileManager.default.createDirectory(at: library.customDirectory, withIntermediateDirectories: true)
        return library.customDirectory
    }

    // MARK: - The steps

    /// The slow half of an add, which may run anywhere: reads the chosen
    /// file, which for a file kept in the cloud waits for it to arrive, copies
    /// it to a hidden name the library does not list, and decodes and measures
    /// that copy. It gives nothing a name and moves nothing a rule can name,
    /// so it cannot disturb an alert, and a look at the folder while it runs
    /// finds the folder as it was.
    public func stage(_ chosen: URL, replacing: Bool = false) -> Result<Staging, Refusal> {
        do {
            return .success(try stageCopy(of: chosen, replacing: replacing))
        } catch let refusal as Refusal {
            return .failure(refusal)
        } catch {
            return .failure(.couldNotCopy(error.localizedDescription))
        }
    }

    /// The quick half: gives a staged copy its name, setting aside what it
    /// replaces. A few renames in one folder, done where the rules are loaded,
    /// so that it and `recoverSetAsideSounds` never run at once.
    public func install(_ staging: Staging, replacing: Bool = false) -> Result<String, Refusal> {
        guard case .staged(let staged) = staging else {
            if case .alreadyThere(let name) = staging { return .success(name) }
            return .failure(.notAFile)
        }
        var installer = SoundInstall(library: library)
        installer.move = move
        return installer.install(staged.file, as: staged.name, replacing: replacing)
    }

    /// What `stage` made: a checked copy waiting for its name, or the word
    /// that the file chosen is one already in the folder.
    public enum Staging: Equatable, Sendable {
        case staged(Staged)
        case alreadyThere(String)
    }

    public struct Staged: Equatable, Sendable {
        /// The hidden, checked copy.
        public let file: URL
        /// The name a rule would say.
        public let name: String
        /// The file's type, lower case.
        public let type: String
        /// What ties the copy to the sounds set aside for it.
        public let attempt: String
    }

    private func stageCopy(of chosen: URL, replacing: Bool) throws -> Staging {
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
        if existing.contains(where: { $0.resolvingSymlinksInPath().path == source.path }) { return .alreadyThere(name) }
        // Asked here too, before the file is read, so that the question of
        // replacing comes at once and not after a long copy.
        if !existing.isEmpty && !replacing { throw Refusal.alreadyExists(existing[0].deletingPathExtension().lastPathComponent) }

        try makeFolder()
        Self.removeStaleStagedCopies(in: folder)
        // Hidden, so the library does not list it while it is being checked,
        // and with the type the file has, which the decoder goes by.
        let attempt = UUID().uuidString
        let staged = folder.appendingPathComponent("\(Self.stagedPrefix)\(attempt).\(type)")
        do {
            // Read whole and not mapped: a mapped file that is cut short
            // while it is copied stops the app, and the size is bounded.
            let bytes = try Data(contentsOf: source)
            guard bytes.count <= Self.maximumBytes else { throw Refusal.tooLarge }
            try bytes.write(to: staged, options: .withoutOverwriting)
            try Self.check(staged)
        } catch let refusal as Refusal {
            try? files.removeItem(at: staged)
            throw refusal
        } catch {
            try? files.removeItem(at: staged)
            throw Refusal.couldNotCopy(error.localizedDescription)
        }
        return .staged(Staged(file: staged, name: name, type: type, attempt: attempt))
    }

    /// Finishes a replace the app stopped in the middle of, so that a sound
    /// is never left hidden with no name a rule can find it by. `SoundInstall`
    /// does it, and says how.
    @discardableResult
    public func recoverSetAsideSounds() -> [String] {
        SoundInstall(library: library).recoverSetAsideSounds()
    }

    static func asideName(for fileName: String, attempt: String, newType: String) -> String {
        SoundInstall.asideName(for: fileName, attempt: attempt, newType: newType)
    }

    static func setAside(_ hiddenName: String) -> (attempt: String, newType: String, fileName: String)? {
        SoundInstall.setAside(hiddenName)
    }

    /// Removes staged copies a crash left in the folder, as `SoundInstall`
    /// says, for saving's as well as adding's.
    static func removeStaleStagedCopies(in folder: URL, now: Date = Date()) {
        SoundInstall.removeStaleStagedCopies(in: folder, now: now)
    }

    /// The name a rule would say for `file`, or nil when it has none that is
    /// safe to give a file in the folder.
    static func soundName(for file: URL) -> String? {
        SoundInstall.soundName(for: file)
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
