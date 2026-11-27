// Sources/AlertAudio/SoundInstall.swift
import Foundation

/// Gives a sound that has been written and checked under a hidden name its
/// place in the user's sounds folder, and finishes the job if the app stopped
/// part of the way.
///
/// The one step that can cost the user a sound they already have: a sound it
/// replaces is set aside under a hidden name first and put back if the new one
/// cannot take its place. So there is one implementation of it, and adding a
/// sound and saving an edited one both call it. Whoever calls it has made the
/// staged file and checked it: what was checked is what is kept, and nothing is
/// given a name that has not passed.
///
/// The hidden name a sound is set aside under says what it was called and
/// which staged copy was to replace it, so that if the app stops between the
/// two, the next look at the folder puts it back (`recoverSetAsideSounds`).
public struct SoundInstall {
    /// The rename that gives the staged file its name. A test makes it fail.
    var move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }

    public let library: SoundLibrary

    public init(library: SoundLibrary) {
        self.library = library
    }

    // MARK: - Names

    /// A copy of a chosen file, waiting to be checked and named.
    static let addingPrefix = ".adding-"
    /// A rendered sound, waiting to be checked and named.
    static let renderingPrefix = ".rendering-"
    /// A recipe, waiting to be put beside the sound it made.
    static let recipePrefix = ".recipe-"
    /// The names a sound waits under before it is installed: the ones whose
    /// presence says a replace was not finished.
    static let stagedSoundPrefixes = [addingPrefix, renderingPrefix]
    /// Everything staged, a crash's leavings included.
    static let stagedPrefixes = stagedSoundPrefixes + [recipePrefix]
    /// A sound that is being replaced, hidden until the new one has its name.
    static let asidePrefix = ".replacing-"
    /// How old a staged file must be before it is taken for one a crash left.
    static let staleAfter: TimeInterval = 600
    /// Held while the folder is looked at to learn which sounds are in it and something is done about
    /// what is seen: a sound being given its name, a stopped replace being finished, and the edits of
    /// sounds that have gone being swept. Each of those takes a sound out of sight for a moment or
    /// judges one by whether it is in sight, so one that ran under another would put right, or take
    /// away, what is only half done. A lock and not the main actor, because a saved sound is given its
    /// name from the task that rendered it, while the rules load, and recover, on the main actor.
    /// Recursive, as giving a name finishes a stopped replace first.
    private static let folderLock = NSRecursiveLock()

    /// Runs `body` with nothing else looking at the folder as these steps do.
    static func whileTheFolderIsUntouched<Value>(_ body: () throws -> Value) rethrows -> Value {
        folderLock.lock()
        defer { folderLock.unlock() }
        return try body()
    }

    /// The most bytes a file's name may have on the volumes macOS uses.
    static let longestFileName = 255
    static let maximumNameLength = 100
    /// The most bytes the name of a sound that is saved may have: what is left of a file's name
    /// once a sound that is being replaced is set aside under a name that holds its own and more.
    /// A name of fewer characters can be more bytes, so the characters alone do not hold it.
    /// `SoundSaveNaming.longestNameBytes` is the same limit, which the window applies as the user
    /// types. It is the name of a saved sound that is held to it, and not an added one's, which is
    /// the file's own and may be longer, and is refused only when it would replace a sound that
    /// could not be set aside (`SoundImport.Refusal.cannotSetAside`).
    static let longestNameBytes = longestFileName
        - (asidePrefix.utf8.count + 36 + "-".utf8.count + longestType + "-".utf8.count + ".".utf8.count + longestType)
    /// The longest type a sound's file may have, in bytes.
    private static var longestType: Int { SoundLibrary.extensions.map(\.utf8.count).max() ?? 4 }

    /// The attempt and the type a staged sound's name holds, or nil for a name
    /// that is not one a stage gives.
    static func staged(_ fileName: String) -> (attempt: String, type: String)? {
        for prefix in stagedSoundPrefixes where fileName.hasPrefix(prefix) {
            let rest = fileName.dropFirst(prefix.count)
            let attempt = String(rest.prefix(36))
            guard UUID(uuidString: attempt) != nil, rest.dropFirst(36).first == "." else { return nil }
            let type = String(rest.dropFirst(37))
            guard SoundLibrary.extensions.contains(type) else { return nil }
            return (attempt, type)
        }
        return nil
    }

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

    /// The name a rule would say for `file`, or nil when it has none that is
    /// safe to give a file in the folder.
    static func soundName(for file: URL) -> String? {
        let name = file.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return isSafe(name: name) ? name : nil
    }

    /// Whether `name` is one a rule may say and a file in the folder may have.
    static func isSafe(name: String) -> Bool {
        guard !name.isEmpty, name.count <= maximumNameLength, !name.hasPrefix("."),
              name == name.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        let unsafe = CharacterSet(charactersIn: "/:\\").union(.controlCharacters).union(.newlines)
        return name.unicodeScalars.allSatisfy { !unsafe.contains($0) }
    }

    /// Whether `name` is one a sound may be saved under: one a rule may say, in the bytes the window
    /// holds a name to as well as in characters.
    static func isSafeToSave(name: String) -> Bool {
        isSafe(name: name) && name.utf8.count <= longestNameBytes
    }

    // MARK: - Installing

    /// Gives a staged sound its name, setting aside what it replaces. A few
    /// renames in one folder, held against `recoverSetAsideSounds` and the sweep
    /// of the edits of sounds that have gone (`whileTheFolderIsUntouched`), so
    /// that none of them runs at once, on whatever thread each is called.
    ///
    /// `staged` is a file in the sounds folder under a name a stage gave it, which
    /// ties it to the sounds set aside for it. It is gone when this returns,
    /// renamed into place or removed, whatever the outcome: it is never left
    /// for a later look to take for an unfinished add. A file that is not named
    /// as a staged sound is not this type's to remove, and is refused untouched.
    ///
    /// Refuses with `.alreadyExists` when the user has a sound of that name and
    /// `replacing` is false, and always with `.systemSound` when macOS has one.
    public func install(_ staged: URL, as name: String, replacing: Bool) -> Result<String, SoundImport.Refusal> {
        guard let held = Self.staged(staged.lastPathComponent) else {
            return .failure(.couldNotCopy("the copy has no name that says which add it belongs to"))
        }
        defer { try? FileManager.default.removeItem(at: staged) }
        let isSaved = staged.lastPathComponent.hasPrefix(Self.renderingPrefix)
        guard isSaved ? Self.isSafeToSave(name: name) : Self.isSafe(name: name) else { return .failure(.badName) }
        do {
            return .success(try Self.whileTheFolderIsUntouched {
                try giveName(name, to: staged, type: held.type, attempt: held.attempt, replacing: replacing)
            })
        } catch let refusal as SoundImport.Refusal {
            return .failure(refusal)
        } catch {
            return .failure(.couldNotCopy(error.localizedDescription))
        }
    }

    private func giveName(_ name: String, to staged: URL, type: String, attempt: String, replacing: Bool) throws -> String {
        let files = FileManager.default
        let folder = library.customDirectory.resolvingSymlinksInPath()
        // First, so that a sound a stopped replace left set aside is back
        // under its name before this add asks what is there. It leaves this
        // add's own staged copy alone: nothing is set aside for it yet.
        recoverSetAsideSounds()
        // Asked again: the folder may have changed while the copy was made.
        if let system = library.systemName(matching: name) { throw SoundImport.Refusal.systemSound(system) }
        let existing = library.customFiles(named: name)
        if !existing.isEmpty && !replacing {
            throw SoundImport.Refusal.alreadyExists(existing[0].deletingPathExtension().lastPathComponent)
        }

        // The sounds it replaces are set aside under hidden names, not
        // deleted, until the new one has its name; if it cannot be given it,
        // each is put back.
        let destination = folder.appendingPathComponent("\(name).\(type)")
        var aside: [(original: URL, hidden: URL)] = []
        // Asked of every one before any is moved, so a name too long for the
        // hidden name leaves the folder as it was.
        for old in existing where Self.asideName(for: old.lastPathComponent, attempt: attempt, newType: type).utf8.count > Self.longestFileName {
            throw SoundImport.Refusal.cannotSetAside(old.deletingPathExtension().lastPathComponent)
        }
        do {
            for old in existing {
                let hidden = folder.appendingPathComponent(
                    Self.asideName(for: old.lastPathComponent, attempt: attempt, newType: type))
                try files.moveItem(at: old, to: hidden)
                aside.append((old, hidden))
            }
            try move(staged, destination)
        } catch {
            for pair in aside.reversed() { try? files.moveItem(at: pair.hidden, to: pair.original) }
            throw SoundImport.Refusal.couldNotCopy(error.localizedDescription)
        }
        for pair in aside { try? files.removeItem(at: pair.hidden) }
        return name
    }

    // MARK: - Recovering

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
        Self.whileTheFolderIsUntouched { recoverWhileUntouched() }
    }

    private func recoverWhileUntouched() -> [String] {
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
            let stagedIsThere = all.contains { Self.isStaged($0.lastPathComponent, forAttempt: aside.attempt) }
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
        for staged in all where unfinished.contains(where: { Self.isStaged(staged.lastPathComponent, forAttempt: $0) }) {
            try? files.removeItem(at: staged)
        }
        return restored
    }

    /// Whether `fileName` is a sound staged for the attempt.
    private static func isStaged(_ fileName: String, forAttempt attempt: String) -> Bool {
        stagedSoundPrefixes.contains { fileName.hasPrefix("\($0)\(attempt).") }
    }

    /// Removes staged files a crash left in the folder: the names a stage gives,
    /// the sounds' and the recipes', and only ones old enough not to be another
    /// add or save under way. A set-aside sound is no part of this: it is put
    /// back by `recoverSetAsideSounds` or not touched, and is never judged by
    /// its age, which moving a file does not change.
    static func removeStaleStagedCopies(in folder: URL, now: Date = Date()) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where stagedPrefixes.contains(where: file.lastPathComponent.hasPrefix) {
            guard let changed = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(changed) > staleAfter else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
