// Sources/AlertAudio/SoundEditStore.swift
import AVFoundation
import CryptoKit
import Foundation
import NotificationCore

/// Opens a sound to be edited and saves what was made of it (sound editor plan, Task 5).
///
/// A saved sound is two things (Ruling 1): the audio file a rule names, which is all an alert
/// ever plays, and a recipe that says how it was made from its source, kept in a hidden folder
/// beside it, `.edits/Name.edit/`, with a copy of the source. Everything here is arranged so that
/// the recipe can be lost and nothing else is:
///
/// - Opening trusts a recipe only for the file it made (Ruling 10). It records a digest of what
///   it rendered, and a file that does not match was replaced outside the editor: it opens as a
///   plain sound, its own file the source, and nothing is an error.
/// - Saving gives the sound its name through `SoundInstall`, the one step that can lose a sound
///   the user has (Ruling 8): what is written is checked as an added sound is, under a hidden name,
///   and only then named, with a sound it replaces set aside and put back if anything fails. A
///   failure of any step before that leaves every file as it was.
/// - The recipe is put in place last, once the sound has its name. If that cannot be done the
///   sound is kept, and is a plain sound, and the outcome says so.
///
/// Nothing here is the main actor's. Opening decodes a whole file and saving renders and writes
/// one, and the editor calls them from a task of its own; only the giving of a name is a few
/// renames in one folder, and those are held against the rules' recovery of a stopped replace, which
/// runs on the main actor, and against the sweep of edits (`SoundInstall.whileTheFolderIsUntouched`).
public struct SoundEditStore {
    public let library: SoundLibrary
    /// The rename that gives the recipe its place beside the sound, and the sound its name, handed
    /// on to `SoundInstall`. A test makes it fail.
    var move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }

    public init(library: SoundLibrary) {
        self.library = library
    }

    // MARK: - What is opened and what is saved

    /// A sound opened for editing: what to show and what to start the edits from.
    public struct Opened: Equatable, Sendable {
        /// The sound's name as its file spells it.
        public let name: String
        /// The source, decoded to the player's format. What every recipe of this sound is a list of
        /// pieces of.
        public let source: SampleBuffer
        /// Where the edits start: the recipe the sound was saved with, or the whole of the source.
        public let recipe: SoundRecipe
        /// Whether the recipe it was saved with was found and is trusted (Ruling 10). False for a
        /// sound that was not made by the editor, and for one that was and has since been replaced.
        public let hasEdits: Bool
        /// The file whose bytes are the source, which a save copies into the new sound's own folder.
        let sourceFile: URL
        /// The source's bytes as they were read, which the recipe's digest is of. A save is made from the file first and
        /// from these only when the file has gone or is no longer the source, as it is after a save that replaced a sound
        /// of another type than WAV, or one whose edits could not be kept: the source then is on disk nowhere. Held
        /// for as long as the window is, at most as much again as the decoded source is.
        let sourceBytes: Data
        /// The sound's own file, as it was opened, and a digest of its bytes then: what a save over it
        /// is held to, so that a file put in its place since is not replaced unseen.
        let soundFile: URL
        let soundDigest: String
    }

    /// What a save did, once the sound has its name.
    public enum Saved: Equatable, Sendable {
        /// The sound and its edits are kept.
        case saved(String)
        /// The sound has its name and plays as it should, but its edits could not be kept beside it,
        /// so the editor will open it as a new sound (Rulings 1 and 10). The window says so, in
        /// `SoundEditorText.editsCannotBeReopened`.
        case savedWithoutEdits(String)

        public var name: String {
            switch self {
            case .saved(let name), .savedWithoutEdits(let name): return name
            }
        }
    }

    // MARK: - Where things are

    /// The hidden folder in the sounds folder that holds every sound's edits. The library skips hidden
    /// files and does not look inside folders, so none of it is ever listed as a sound.
    static let editsFolderName = ".edits"
    static let sidecarSuffix = ".edit"
    static let recipeFileName = "recipe.json"
    static let sourcePrefix = "source-"
    /// The longest a sound may be to be opened (Ruling 18).
    static let maximumOpenSeconds = Double(SoundRecipe.maximumFrames) / Double(SampleBuffer.sampleRate)

    static func sidecar(of name: String, in folder: URL) -> URL {
        folder.appendingPathComponent(editsFolderName, isDirectory: true)
            .appendingPathComponent(name + sidecarSuffix, isDirectory: true)
    }

    /// The name a source's copy is kept under: its digest, so that two sources never share one, a
    /// copy that is already there is the one wanted, and a save over a sound whose source differs
    /// can never write over the source the sound's recipe still depends on.
    static func sourceName(digest: String, type: String) -> String {
        "\(sourcePrefix)\(digest.prefix(16)).\(type)"
    }

    /// A digest of some bytes, to tell one file from another.
    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Opening

    /// Opens the sound a rule would name `name`, for editing.
    ///
    /// When it was saved by the editor and its recipe matches it, the edits come back with the source
    /// they were made from. Otherwise it is a plain sound: its own file is the source and the edits
    /// start as the whole of it. A recipe that cannot be read, is newer than this app, or is for
    /// a file other than the one that is there is no error, and is not touched.
    public func open(_ name: String) -> Result<Opened, SoundOpenFailure> {
        guard let file = library.url(for: name) else { return .failure(.notFound(name)) }
        let displayName = file.deletingPathExtension().lastPathComponent
        let limit = SoundImport.maximumBytes
        if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > limit {
            return .failure(.tooLarge(limitMegabytes: limit / 1_048_576))
        }
        if let edited = openEdited(file, named: displayName) { return .success(edited) }
        return openPlain(file, named: displayName)
    }

    private func openPlain(_ file: URL, named name: String) -> Result<Opened, SoundOpenFailure> {
        let bytes: Data
        let samples: SampleBuffer
        do {
            bytes = try Data(contentsOf: file)
            guard bytes.count <= SoundImport.maximumBytes else {
                return .failure(.tooLarge(limitMegabytes: SoundImport.maximumBytes / 1_048_576))
            }
            samples = try Self.decode(file)
        } catch SoundDecoding.Failure.tooLong(let seconds) {
            return .failure(.tooLong(frames: SampleBuffer.frames(seconds: seconds)))
        } catch SoundDecoding.Failure.unreadable(let reason) {
            return .failure(.unreadable(reason))
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
        let digest = Self.digest(of: bytes)
        let type = file.pathExtension.lowercased()
        guard let source = SoundRecipe.Source(name: Self.sourceName(digest: digest, type: type),
                                              frames: samples.frameCount, digest: digest) else {
            return .failure(.unreadable("it is empty"))
        }
        do {
            return .success(Opened(name: name, source: samples, recipe: try SoundRecipe(wholeOf: source), hasEdits: false,
                                   sourceFile: file, sourceBytes: bytes, soundFile: file, soundDigest: digest))
        } catch SoundEditRefusal.sourceTooLong(let frames) {
            return .failure(.tooLong(frames: frames))
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
    }

    /// The sound with the edits it was saved with, or nil when it has none that are for this file
    /// (`savedEdits`), or when the source that is kept cannot be read as the audio the recipe says.
    private func openEdited(_ file: URL, named name: String) -> Opened? {
        guard let saved = Self.savedEdits(of: file, named: name, library: library),
              let samples = try? Self.decode(saved.sourceFile),
              samples.frameCount == saved.stored.recipe.source.frames else { return nil }
        return Opened(name: name, source: samples, recipe: saved.stored.recipe, hasEdits: true, sourceFile: saved.sourceFile,
                      sourceBytes: saved.sourceBytes, soundFile: file, soundDigest: saved.stored.renderedDigest)
    }

    /// What a sound that the editor saved is trusted for, found beside it.
    private struct SavedEdits {
        let stored: SoundRecipeCodec.Stored
        /// The kept copy of what the sound was made from, and its bytes.
        let sourceFile: URL
        let sourceBytes: Data
    }

    /// The recipe a sound's file was saved with and the copy of its source that is kept beside it, or nil when
    /// there are none that are for this file: no folder, no recipe, a recipe that cannot be read or is newer, a
    /// file that is not the one the recipe rendered, or a source that is gone, changed, or not the one the
    /// recipe says.
    private static func savedEdits(of file: URL, named name: String, library: SoundLibrary) -> SavedEdits? {
        let folder = library.customDirectory.resolvingSymlinksInPath()
        guard file.deletingLastPathComponent().resolvingSymlinksInPath().path == folder.path,
              file.pathExtension.lowercased() == "wav" else { return nil }
        let sidecar = Self.sidecar(of: name, in: folder)
        guard let recipeBytes = try? Data(contentsOf: sidecar.appendingPathComponent(Self.recipeFileName)),
              let stored = try? SoundRecipeCodec.decode(recipeBytes),
              let soundBytes = try? Data(contentsOf: file),
              Self.digest(of: soundBytes) == stored.renderedDigest else { return nil }

        // The name is the recipe file's to say, and so is not taken to be one that stays inside its folder.
        let sourceName = stored.recipe.source.name
        guard !sourceName.isEmpty, !sourceName.hasPrefix("."), !sourceName.contains("/") else { return nil }
        let sourceFile = sidecar.appendingPathComponent(sourceName)
        guard let size = (try? sourceFile.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size <= SoundImport.maximumBytes,
              let sourceBytes = try? Data(contentsOf: sourceFile),
              Self.digest(of: sourceBytes) == stored.recipe.source.digest else { return nil }
        return SavedEdits(stored: stored, sourceFile: sourceFile, sourceBytes: sourceBytes)
    }

    private static func decode(_ file: URL) throws -> SampleBuffer {
        try SoundDecoding.samples(of: file, maximumSeconds: maximumOpenSeconds,
                                  maximumDecodedBytes: SoundImport.maximumDecodedBytes)
    }

    // MARK: - Saving

    /// Saves `recipe`, made from what `opened` is of, as the sound `name`.
    ///
    /// The sound is rendered, written as 48 kHz stereo float (Ruling 14), and checked as an added sound
    /// is, so that one that is silent or over 30 seconds is never given a name (Ruling 8). `name` is
    /// refused when macOS has a sound of it, and when the user has one and `replacing` is false.
    /// The window asks before it passes `replacing`.
    ///
    /// Until the sound has its name, every file is as it was, whatever fails. After, a recipe that
    /// cannot be put beside it is `savedWithoutEdits`, and not a failure.
    public func save(_ recipe: SoundRecipe, of opened: Opened, as name: String, replacing: Bool) -> Result<Saved, SoundSaveFailure> {
        guard recipe.source == opened.recipe.source, opened.source.frameCount == recipe.source.frames else {
            return .failure(.sourceChanged)
        }
        guard SoundInstall.isSafeToSave(name: name) else { return .failure(.badName) }
        guard recipe.canBeSaved else { return .failure(.tooLong) }

        var installer = SoundInstall(library: library)
        installer.move = move
        // First, so that a sound a stopped replace left hidden is asked about as the sound it is.
        installer.recoverSetAsideSounds()
        if let system = library.systemName(matching: name) { return .failure(.systemSound(system)) }
        let existing = library.customFiles(named: name)
        if let first = existing.first, !replacing {
            return .failure(.alreadyExists(first.deletingPathExtension().lastPathComponent))
        }
        // A sound that was put in the place of the one that was opened, outside the editor, is not the one
        // the window showed, and is not replaced without being seen.
        if existing.contains(where: { Self.isTheSame($0, as: opened.soundFile) }), !Self.soundIsAsOpened(opened, library: library) {
            return .failure(.sourceChanged)
        }

        let files = FileManager.default
        let folder = library.customDirectory.resolvingSymlinksInPath()
        do {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return .failure(.couldNotWrite(error.localizedDescription))
        }
        SoundInstall.removeStaleStagedCopies(in: folder)
        Self.removeOrphanedSidecars(library: library)

        let attempt = UUID().uuidString
        let stagedSound = folder.appendingPathComponent("\(SoundInstall.renderingPrefix)\(attempt).wav")
        let stagedRecipe = folder.appendingPathComponent("\(SoundInstall.recipePrefix)\(attempt).json")
        let sidecar = Self.sidecar(of: name, in: folder)
        var made = Made()
        /// Takes back what this save made, so that a save that fails leaves the folder as it found it.
        func abandon() {
            try? files.removeItem(at: stagedSound)
            try? files.removeItem(at: stagedRecipe)
            made.undo(sidecar: sidecar, in: folder)
        }

        do {
            let rendered = SoundRender.render(source: opened.source, recipe: recipe)
            try Self.write(rendered, to: stagedSound)
            try SoundImport.check(stagedSound)
            let renderedDigest = Self.digest(of: try Data(contentsOf: stagedSound))
            let recipeBytes = try SoundRecipeCodec.encode(.init(recipe: recipe, renderedDigest: renderedDigest))
            try recipeBytes.write(to: stagedRecipe, options: .withoutOverwriting)
            made = try Self.keepSource(of: opened, for: recipe, in: sidecar, under: folder, library: library)
        } catch let failure as SoundSaveFailure {
            abandon()
            return .failure(failure)
        } catch let refusal as SoundImport.Refusal {
            abandon()
            return .failure(SoundSaveFailure(refusal))
        } catch {
            abandon()
            return .failure(.couldNotWrite(error.localizedDescription))
        }

        switch installer.install(stagedSound, as: name, replacing: replacing) {
        case .failure(let refusal):
            abandon()
            return .failure(SoundSaveFailure(refusal))
        case .success:
            break
        }

        // The sound has its name. Its old recipe, if it had one, is for a sound that is gone, and the
        // new one takes its place.
        guard keepRecipe(stagedRecipe, in: sidecar, source: recipe.source.name) else {
            try? files.removeItem(at: stagedRecipe)
            try? files.removeItem(at: sidecar)
            Made.removeEditsFolderIfEmpty(in: folder)
            return .success(.savedWithoutEdits(name))
        }
        return .success(.saved(name))
    }

    /// The sound as the window that saved it goes on with it, for the window's next save.
    ///
    /// The window keeps editing the sound it saved, and saves again, over or as new. The `Opened` it was given is the
    /// sound as it was before its first save, which is no longer the sound, or the source, on disk when the sound was
    /// not a WAV (its file went when the WAV was given its name) or when its edits could not be kept (the source is
    /// then nowhere on disk). So every save is followed by this, and the next save is made of what it returns: the file
    /// the save wrote, which is its own render and no change made outside the editor, and the source wherever it now
    /// is. A file that is not the render by the time this looks, because it was replaced in that instant, is not taken
    /// for it: the next save is then refused, as a sound changed outside the editor is.
    ///
    /// Reads the sound's file, and so is not the main actor's to call, as `save` is not.
    public static func continuing(_ opened: Opened, after saved: Saved, library: SoundLibrary) -> Opened {
        let name = saved.name
        let file = library.customDirectory.resolvingSymlinksInPath().appendingPathComponent("\(name).wav")
        let hasEdits: Bool
        let sourceFile: URL
        let renderDigest: String
        switch saved {
        case .saved:
            // The file as the recipe it was saved with says it is, and that recipe the one the save wrote.
            let kept = savedEdits(of: file, named: name, library: library).flatMap {
                $0.stored.recipe.source == opened.recipe.source ? $0 : nil
            }
            hasEdits = true
            sourceFile = kept?.sourceFile ?? opened.sourceFile
            renderDigest = kept?.stored.renderedDigest ?? ""
        case .savedWithoutEdits:
            hasEdits = false
            sourceFile = opened.sourceFile
            renderDigest = (try? Data(contentsOf: file)).map(digest(of:)) ?? ""
        }
        return Opened(name: name, source: opened.source, recipe: opened.recipe, hasEdits: hasEdits, sourceFile: sourceFile,
                      sourceBytes: opened.sourceBytes, soundFile: file, soundDigest: renderDigest)
    }

    /// The bytes of the source the recipe is of: the file the sound was opened from, when it is still what was
    /// opened. A sound that was opened plain is its own source until the editor saves it over, and then the
    /// file is the render and the source is the copy kept beside it, which is what a save from the window that
    /// opened it, after one of its own, is made from. Failing both, the bytes the window read: used only while the
    /// sound's own file is the one the window knows, the render it saved or the file it opened, so that a sound
    /// that was not a WAV, or whose edits could not be kept, and so has its source nowhere else, can be saved again.
    /// A file that is none of these was changed outside the editor.
    private static func sourceBytes(of opened: Opened, for recipe: SoundRecipe, library: SoundLibrary) throws -> Data {
        if let bytes = try? Data(contentsOf: opened.sourceFile), bytes.count <= SoundImport.maximumBytes,
           digest(of: bytes) == recipe.source.digest {
            return bytes
        }
        if let saved = savedEdits(of: opened.soundFile, named: opened.name, library: library),
           saved.stored.recipe.source == recipe.source {
            return saved.sourceBytes
        }
        if digest(of: opened.sourceBytes) == recipe.source.digest,
           let bytes = try? Data(contentsOf: opened.soundFile), digest(of: bytes) == opened.soundDigest {
            return opened.sourceBytes
        }
        throw SoundSaveFailure.sourceChanged
    }

    private static func isTheSame(_ file: URL, as other: URL) -> Bool {
        file.resolvingSymlinksInPath().standardizedFileURL.path == other.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Whether the sound's file is still the one that was opened, or one the editor made of it since: a sound
    /// saved over is a file that was opened and is now the render, which is no change made outside the editor,
    /// and the window goes on from the sound it saved.
    private static func soundIsAsOpened(_ opened: Opened, library: SoundLibrary) -> Bool {
        guard let bytes = try? Data(contentsOf: opened.soundFile) else { return false }
        return digest(of: bytes) == opened.soundDigest
            || savedEdits(of: opened.soundFile, named: opened.name, library: library) != nil
    }

    /// What a save made in the sidecar before the sound had its name, which a failure takes back.
    private struct Made {
        var editsFolder = false
        var sidecar = false
        var source: URL?

        mutating func undo(sidecar folder: URL, in sounds: URL) {
            let files = FileManager.default
            if let source { try? files.removeItem(at: source) }
            if sidecar { try? files.removeItem(at: folder) }
            if editsFolder { Self.removeEditsFolderIfEmpty(in: sounds) }
            self = Made()
        }

        static func removeEditsFolderIfEmpty(in sounds: URL) {
            let edits = sounds.appendingPathComponent(SoundEditStore.editsFolderName, isDirectory: true)
            if let left = try? FileManager.default.contentsOfDirectory(atPath: edits.path), left.isEmpty {
                try? FileManager.default.removeItem(at: edits)
            }
        }
    }

    /// Puts a copy of the source in the sound's own folder, unless it is there. The copy is what the
    /// sound's recipe renders from, so that a source that is later changed or deleted cannot break it
    /// (Ruling 10): it is read now and held to the digest the recipe carries, so that what is kept is what
    /// the edits were made of, whatever has happened to the file since it was opened.
    private static func keepSource(of opened: Opened, for recipe: SoundRecipe, in sidecar: URL,
                                   under folder: URL, library: SoundLibrary) throws -> Made {
        let files = FileManager.default
        let bytes = try sourceBytes(of: opened, for: recipe, library: library)
        var made = Made()
        let edits = sidecar.deletingLastPathComponent()
        let target = sidecar.appendingPathComponent(recipe.source.name)
        do {
            if !files.fileExists(atPath: edits.path) {
                try files.createDirectory(at: edits, withIntermediateDirectories: true)
                made.editsFolder = true
            }
            if !files.fileExists(atPath: sidecar.path) {
                try files.createDirectory(at: sidecar, withIntermediateDirectories: true)
                made.sidecar = true
            }
            if let kept = try? Data(contentsOf: target), digest(of: kept) == recipe.source.digest { return made }
            try bytes.write(to: target, options: .atomic)
            made.source = target
            return made
        } catch {
            made.undo(sidecar: sidecar, in: folder)
            throw error
        }
    }

    /// Puts the staged recipe in the sound's folder, in place of the one it had, and takes away what the
    /// sound it replaced kept there that the new one does not use. False when it could not be done, in
    /// which case the sound has no recipe: one that is left would be for a sound that is gone.
    private func keepRecipe(_ staged: URL, in sidecar: URL, source: String) -> Bool {
        let files = FileManager.default
        let target = sidecar.appendingPathComponent(Self.recipeFileName)
        do {
            if files.fileExists(atPath: target.path) { try files.removeItem(at: target) }
            try move(staged, target)
        } catch {
            return false
        }
        for entry in (try? files.contentsOfDirectory(atPath: sidecar.path)) ?? []
        where entry != Self.recipeFileName && entry != source {
            try? files.removeItem(at: sidecar.appendingPathComponent(entry))
        }
        return true
    }

    /// Writes samples as the file the sound is kept in: 48 kHz, float, 32 bits, a WAV, so that a level
    /// over full scale is kept as it is (Ruling 14).
    private static func write(_ samples: SampleBuffer, to url: URL) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(SampleBuffer.sampleRate),
                                         channels: AVAudioChannelCount(samples.channelCount), interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.frameCount)),
              let channels = buffer.floatChannelData else {
            throw SoundSaveFailure.couldNotWrite(nil)
        }
        buffer.frameLength = AVAudioFrameCount(samples.frameCount)
        for (index, channel) in samples.channels.enumerated() {
            channel.withUnsafeBufferPointer { channels[index].update(from: $0.baseAddress!, count: $0.count) }
        }
        // The file is closed when it goes out of scope, which is what finishes its header.
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        try file.write(from: buffer)
    }

    // MARK: - The sweep

    /// Removes the edits of sounds that are gone: a folder in `.edits/` whose sound no longer has a
    /// file of its name, because it was deleted or renamed in the Finder, once it is old and not before.
    /// A sound that is there is never judged, by age or anything else, however old its edits.
    ///
    /// Done wherever the staged files a crash left are swept, when a sound is added or saved, so that
    /// nothing else has to remember to. Age is the newest change to the folder or anything in it: a
    /// save writes the source before the sound has its name, so a young folder with no sound may be a
    /// save under way. An entry that is not a folder whose name ends in `.edit` is not this code's to remove.
    static func removeOrphanedSidecars(library: SoundLibrary, now: Date = Date()) {
        let files = FileManager.default
        let sounds = library.customDirectory.resolvingSymlinksInPath()
        let edits = sounds.appendingPathComponent(editsFolderName, isDirectory: true)
        // Not told the sounds are not there by a folder that could not be read.
        guard (try? files.contentsOfDirectory(atPath: sounds.path)) != nil,
              let entries = try? files.contentsOfDirectory(
                at: edits, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return }
        // Held so that a sound that is being replaced, and so for a moment has no file of its name, is
        // not taken for one that has gone.
        SoundInstall.whileTheFolderIsUntouched {
            for entry in entries {
                let fileName = entry.lastPathComponent
                guard fileName.hasSuffix(sidecarSuffix), fileName.count > sidecarSuffix.count,
                      (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let name = String(fileName.dropLast(sidecarSuffix.count))
                guard library.customFiles(named: name).isEmpty,
                      let changed = newestChange(in: entry), now.timeIntervalSince(changed) > SoundInstall.staleAfter else { continue }
                try? files.removeItem(at: entry)
            }
            Made.removeEditsFolderIfEmpty(in: sounds)
        }
    }

    private static func newestChange(in folder: URL) -> Date? {
        let inside = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return ([folder] + inside).compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }.max()
    }
}

extension SoundSaveFailure {
    /// What a refusal of `SoundImport`'s checks or of `SoundInstall` is, as a failure of saving, so that a
    /// sound being saved is never told "The sound could not be added". Every case is said: the ones a
    /// save cannot make, a file that is not a file or is of a type no sound may be, are written as
    /// what they would be to a person, a sound that could not be written.
    init(_ refusal: SoundImport.Refusal) {
        switch refusal {
        case .badName: self = .badName
        case .systemSound(let name): self = .systemSound(name)
        case .alreadyExists(let name): self = .alreadyExists(name)
        case .cannotSetAside(let name): self = .cannotSetAside(name)
        case .silent: self = .silent
        // More audio than a sound may hold is a sound that is too long, whatever it is that is too much of it.
        case .tooLong, .tooLarge: self = .tooLong
        case .unreadable(let reason): self = .unreadable(reason)
        case .couldNotCopy(let reason): self = .couldNotWrite(reason)
        case .notAFile, .unsupportedType: self = .couldNotWrite(nil)
        }
    }
}
