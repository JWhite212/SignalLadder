// Sources/RuleStorage/RulesFile.swift
import Foundation
import CryptoKit

/// The rules file on disk: read with a fingerprint, written without ever
/// losing what was there.
///
/// Its own target, with its own tests, because this is the one place a bug
/// destroys the user's rules — and the app target has no tests.
///
/// Three guarantees, each tested:
/// - **Nothing is lost.** Before a write, the bytes on disk are COPIED to a
///   backup; the original is never moved, so a failure at any point leaves
///   `rules.json` whole.
/// - **Nothing is half-written.** The new file is written atomically: a
///   temporary file, then a rename.
/// - **Nothing is overwritten unseen.** A save states the fingerprint of the
///   file it was made from, and is refused if the file has changed since —
///   edited, created, or deleted — so a hand edit made while the editor was
///   open is never silently replaced.
///
/// One gap is accepted and documented: a write landing in the milliseconds
/// between the re-read and the rename is not detected. Closing it would need
/// file coordination, which text editors do not take part in.
public struct RulesFile: Sendable {
    /// Writes bytes to a URL atomically. Injectable so a test can make one
    /// write fail and prove what is left behind.
    public typealias Writer = @Sendable (Data, URL) throws -> Void

    public static let atomicWriter: Writer = { data, url in try data.write(to: url, options: .atomic) }

    /// Where the version on disk before each ordinary save is kept.
    public static let previousName = "rules.previous.json"

    public let url: URL
    private let writer: Writer

    public init(url: URL, writer: @escaping Writer = RulesFile.atomicWriter) {
        self.url = url
        self.writer = writer
    }

    /// What was read, and its fingerprint.
    public struct Snapshot: Equatable, Sendable {
        /// nil when there is no file.
        public let data: Data?
        public let fingerprint: Fingerprint

        public init(data: Data?) {
            self.data = data
            self.fingerprint = Fingerprint(data)
        }
    }

    /// Identifies exactly one state of the file: its SHA-256, or its absence.
    /// Absence is a state like any other — a file appearing after the editor
    /// read "no file" is a change, and is refused like one.
    public struct Fingerprint: Hashable, Sendable {
        let digest: String?

        public init(_ data: Data?) {
            digest = data.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
        }

        public static let noFile = Fingerprint(nil)
    }

    public enum ReadError: Error, Equatable, CustomStringConvertible {
        /// Present but unopenable — permissions, a directory in the way.
        /// Never treated as "no file", which would read as the user simply
        /// not having written any rules yet.
        case unopenable(String)

        public var description: String {
            switch self {
            case .unopenable(let reason): return "the file exists but could not be opened: \(reason)"
            }
        }
    }

    public func read() throws -> Snapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return Snapshot(data: nil) }
        do {
            return Snapshot(data: try Data(contentsOf: url))
        } catch {
            throw ReadError.unopenable(error.localizedDescription)
        }
    }

    public enum SaveResult: Equatable, Sendable {
        case saved
        /// The file is not what the save was made from. Nothing was written;
        /// here is what is there now.
        case changedOnDisk(Snapshot)
    }

    /// Writes `data`, if the file is still the one `expected` fingerprints.
    /// The version it replaces is kept as `rules.previous.json`.
    public func save(_ data: Data, expecting expected: Fingerprint) throws -> SaveResult {
        let current = try read()
        guard current.fingerprint == expected else { return .changedOnDisk(current) }
        try write(data, keeping: current, as: Self.previousName)
        return .saved
    }

    /// Writes `data` over whatever is there now — the user's answer to a
    /// conflict. What it replaces is kept under its own timestamped name, never
    /// in the rotating `rules.previous.json` slot, where the next ordinary save
    /// would overwrite it.
    ///
    /// - Returns: where the replaced version was kept, or nil if there was no
    ///   file to keep.
    @discardableResult
    public func saveReplacing(_ data: Data, at date: Date) throws -> URL? {
        let current = try read()
        let kept = current.data == nil ? nil : try uniqueBackupURL(for: date)
        try write(data, keeping: current, as: kept?.lastPathComponent)
        return kept
    }

    /// Creates the file if, and only if, there is none. `.withoutOverwriting`
    /// makes that the operating system's guarantee: a file appearing between
    /// the check and the write makes the write fail rather than replace it.
    @discardableResult
    public func createIfMissing(_ data: Data) throws -> Bool {
        guard !FileManager.default.fileExists(atPath: url.path) else { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .withoutOverwriting)
        return true
    }

    // MARK: - Writing

    /// The order is the guarantee: the backup is a copy made while the
    /// original stays in place, and the only operation that touches
    /// `rules.json` is the final atomic write. A failure before it leaves the
    /// old file; a failure during it leaves the old file (the rename never
    /// happened); after it, the new one.
    private func write(_ data: Data, keeping current: Snapshot, as backupName: String?) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let old = current.data, let backupName {
            try writer(old, folder.appendingPathComponent(backupName))
        }
        // Written through a symlink to its target. Renaming onto the link
        // itself would replace it with a plain file, silently cutting the
        // arrangement the user made (a synced or versioned copy).
        try writer(data, url.resolvingSymlinksInPath())
    }

    private func uniqueBackupURL(for date: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let stem = "rules.replaced-\(formatter.string(from: date))"
        let folder = url.deletingLastPathComponent()
        var candidate = folder.appendingPathComponent("\(stem).json")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(stem)-\(n).json")
            n += 1
        }
        return candidate
    }
}
