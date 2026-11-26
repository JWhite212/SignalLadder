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
/// place, so a failure never costs the user the sound they had. The hidden
/// name it is set aside under says what it was called and which copy was to
/// replace it, so that if the app stops between the two, the next look at the
/// folder puts it back (`recoverSetAsideSounds`).
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
        defer { try? FileManager.default.removeItem(at: staged.file) }
        do {
            return .success(try giveName(to: staged, replacing: replacing))
        } catch let refusal as Refusal {
            return .failure(refusal)
        } catch {
            return .failure(.couldNotCopy(error.localizedDescription))
        }
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

    private func giveName(to staged: Staged, replacing: Bool) throws -> String {
        let files = FileManager.default
        let folder = library.customDirectory.resolvingSymlinksInPath()
        let (name, type, attempt) = (staged.name, staged.type, staged.attempt)
        // First, so that a sound a stopped replace left set aside is back
        // under its name before this add asks what is there. It leaves this
        // add's own staged copy alone: nothing is set aside for it yet.
        recoverSetAsideSounds()
        // Asked again: the folder may have changed while the copy was made.
        if let system = library.systemName(matching: name) { throw Refusal.systemSound(system) }
        let existing = library.customFiles(named: name)
        if !existing.isEmpty && !replacing { throw Refusal.alreadyExists(existing[0].deletingPathExtension().lastPathComponent) }

        // The sounds it replaces are set aside under hidden names, not
        // deleted, until the new one has its name; if it cannot be given it,
        // each is put back.
        let destination = folder.appendingPathComponent("\(name).\(type)")
        var aside: [(original: URL, hidden: URL)] = []
        // Asked of every one before any is moved, so a name too long for the
        // hidden name leaves the folder as it was.
        for old in existing where Self.asideName(for: old.lastPathComponent, attempt: attempt, newType: type).utf8.count > Self.longestFileName {
            throw Refusal.cannotSetAside(old.deletingPathExtension().lastPathComponent)
        }
        do {
            for old in existing {
                let hidden = folder.appendingPathComponent(
                    Self.asideName(for: old.lastPathComponent, attempt: attempt, newType: type))
                try files.moveItem(at: old, to: hidden)
                aside.append((old, hidden))
            }
            try move(staged.file, destination)
        } catch {
            for pair in aside.reversed() { try? files.moveItem(at: pair.hidden, to: pair.original) }
            throw Refusal.couldNotCopy(error.localizedDescription)
        }
        for pair in aside { try? files.removeItem(at: pair.hidden) }
        return name
    }

    /// The most bytes a file's name may have on the volumes macOS uses.
    static let longestFileName = 255

    /// The hidden name a sound is set aside under: the attempt that is
    /// replacing it, the type of the sound that is to take its place, then
    /// the file name it had, whole. The type is what lets a later look tell
    /// the new sound from any other file of the name.
    static func asideName(for fileName: String, attempt: String, newType: String) -> String {
        "\(asidePrefix)\(attempt)-\(newType)-\(fileName)"
    }

    /// What a set-aside name holds, or nil for a name that is not one of
    /// these, which is then left alone.
    static func setAside(_ hiddenName: String) -> (attempt: String, newType: String, fileName: String)? {
        guard hiddenName.hasPrefix(asidePrefix) else { return nil }
        let rest = hiddenName.dropFirst(asidePrefix.count)
        let attempt = String(rest.prefix(36))
        guard UUID(uuidString: attempt) != nil, rest.dropFirst(36).first == "-" else { return nil }
        let afterAttempt = rest.dropFirst(37)
        guard let dash = afterAttempt.firstIndex(of: "-") else { return nil }
        let newType = String(afterAttempt[..<dash])
        let fileName = String(afterAttempt[afterAttempt.index(after: dash)...])
        guard SoundLibrary.extensions.contains(newType),
              !fileName.isEmpty, !fileName.hasPrefix("."), !fileName.contains("/"),
              SoundLibrary.extensions.contains(URL(fileURLWithPath: fileName).pathExtension.lowercased()),
              soundName(for: URL(fileURLWithPath: fileName)) != nil else { return nil }
        return (attempt, newType, fileName)
    }

    /// Finishes a replace the app stopped in the middle of, so that a sound
    /// is never left hidden with no name a rule can find it by.
    ///
    /// A replace sets the old sounds aside, renames the checked copy into
    /// place, and then deletes the old ones. Stopped before the rename, its
    /// staged copy is still there: the old sounds go back under their names
    /// and the staged copy goes. Stopped after it, the staged copy is gone and
    /// a file of the sound's name and the new sound's type is there: only
    /// then, when both say the new sound arrived, are the old ones deleted.
    /// Anything else, such as an undoing that could not put one back, is not
    /// a finished replace, and a set-aside sound whose own file name is free
    /// is put back. One that can be neither proved replaced nor put back is
    /// left where it is, hidden: a file left over costs nothing, and a sound
    /// deleted on a guess cannot be had back. Returns the sound names it put back.
    @discardableResult
    public func recoverSetAsideSounds() -> [String] {
        let files = FileManager.default
        let folder = library.customDirectory.resolvingSymlinksInPath()
        let all = (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var restored: [String] = []
        var unfinished: Set<String> = []
        let asides = all.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).compactMap { hidden in
            Self.setAside(hidden.lastPathComponent).map {
                (hidden: hidden, attempt: $0.attempt, newType: $0.newType, fileName: $0.fileName)
            }
        }
        // Each attempt is judged once, by what is there before anything is
        // moved: putting one of its sounds back must not make the next look
        // as if it had been replaced.
        var wasReplaced: [String: Bool] = [:]
        for aside in asides where wasReplaced[aside.attempt] == nil {
            let stagedIsThere = all.contains { $0.lastPathComponent.hasPrefix("\(Self.stagedPrefix)\(aside.attempt).") }
            let name = URL(fileURLWithPath: aside.fileName).deletingPathExtension().lastPathComponent
            let newSoundIsThere = library.customFiles(named: name).contains { $0.pathExtension.lowercased() == aside.newType }
            // A new sound of the old one's own file name proves nothing by
            // being there unless the old one is not: both cannot be.
            wasReplaced[aside.attempt] = !stagedIsThere && newSoundIsThere
        }
        for aside in asides {
            let original = folder.appendingPathComponent(aside.fileName)
            if wasReplaced[aside.attempt] == true {
                try? files.removeItem(at: aside.hidden)
            } else if !files.fileExists(atPath: original.path) {
                // The staged copy goes only once the sound is back: until
                // then it is what says the replace was not finished.
                if (try? files.moveItem(at: aside.hidden, to: original)) != nil {
                    restored.append(original.deletingPathExtension().lastPathComponent)
                    unfinished.insert(aside.attempt)
                }
            }
        }
        // The copies that were to replace them, which now must not: left
        // there, a later look would take the replace for finished.
        for staged in all where unfinished.contains(where: { staged.lastPathComponent.hasPrefix("\(Self.stagedPrefix)\($0).") }) {
            try? files.removeItem(at: staged)
        }
        return restored
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
