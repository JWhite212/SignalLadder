// Sources/ShortcutRunner/ShortcutRunner.swift
import Foundation

/// Runs a Shortcut as an escalation's last resort (tier 4, §5.16), and lists
/// the user's Shortcuts so a rule's is checked when the rules load (M4 plan,
/// ruling 11).
///
/// Its own target, on `RuleStorage`'s precedent (ruling 18): this is the one
/// place notification text is allowed onto disk, in the temp file a Shortcut
/// reads, so it is tested against real folders, outside the app target,
/// which has no tests.
///
/// The temp file holds exactly four fields, never the raw text, the time or
/// the subrole. It sits in a folder of its own, `0600` inside `0700`, and is
/// deleted the moment the Shortcut's process ends, however long that takes.
/// Anything a crash or a quit left behind is removed by `sweep()`, at launch
/// and at quit.
///
/// Delivery counts from a successful launch, not completion (§5.16): a
/// Shortcut that pages a phone may run for a long time, and nothing here ever
/// waits for it. `run` returns at once and reports once, whichever comes
/// first: the process exiting, or a short grace interval passing with it
/// still running (ruling 19).
@MainActor
public final class ShortcutRunner {
    public enum Outcome: Equatable, Sendable {
        case launched
        /// Always the app's own words, never the Shortcut's output, which can
        /// echo its input, which is notification content (ruling 19).
        case failed(String)
    }

    /// What a Shortcut is given. Its own type, because this target has no
    /// dependencies and so cannot take a `CapturedNotification`; the app
    /// fills one from it.
    public struct Fields: Equatable, Sendable, Encodable {
        public let appNameGuess: String
        public let title: String
        public let subtitle: String
        public let body: String

        public init(appNameGuess: String, title: String, subtitle: String, body: String) {
            self.appNameGuess = appNameGuess
            self.title = title
            self.subtitle = subtitle
            self.body = body
        }
    }

    /// Starts a process and returns at once, or throws if it could not be
    /// started. `onExit` is called on the main actor when it ends, with its
    /// exit code and the start of what it wrote to standard error.
    /// Injectable, so tests never start a real one.
    public typealias ProcessLauncher = (
        _ executable: URL, _ arguments: [String],
        _ onExit: @escaping @MainActor (_ exitCode: Int32, _ standardError: String) -> Void
    ) throws -> Void

    /// Runs `work` on the main actor after `seconds`. Injectable, so tests
    /// decide when the grace interval has passed, and never wait for it.
    public typealias Delay = (_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> Void

    public nonisolated static let executable = URL(fileURLWithPath: "/usr/bin/shortcuts")

    /// A missing Shortcut failed in 0.07 to 0.15 s, and `shortcuts run` spent
    /// about 0.2 s before a real one's actions began (findings, 2026-09-29).
    /// A second is several times the slowest failure, and far too short to
    /// hold up a ladder.
    public nonisolated static let launchGraceInterval: TimeInterval = 1

    /// The folder every run's own folder is made in, and the only one
    /// `sweep()` touches.
    public nonisolated static var defaultRoot: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("com.jamiewhite.signalladder.shortcut-input", isDirectory: true)
    }

    public let root: URL
    private let launcher: ProcessLauncher
    private let after: Delay
    private let graceInterval: TimeInterval

    public init(root: URL = ShortcutRunner.defaultRoot,
                launcher: @escaping ProcessLauncher = ShortcutRunner.launchProcess,
                after: @escaping Delay = ShortcutRunner.onMainQueue,
                graceInterval: TimeInterval = ShortcutRunner.launchGraceInterval) {
        self.root = root
        self.launcher = launcher
        self.after = after
        self.graceInterval = graceInterval
    }

    /// Runs the Shortcut named `name` with `fields` as its input, and calls
    /// `completion` exactly once.
    public func run(name: String, fields: Fields, completion: @escaping @MainActor (Outcome) -> Void) {
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let input = folder.appendingPathComponent("input.json")
        let decided = Decided()
        func finish(_ outcome: Outcome) {
            guard !decided.done else { return }
            decided.done = true
            completion(outcome)
        }

        do {
            try Self.write(fields, to: input, in: folder)
        } catch {
            Self.remove(folder)
            finish(.failed("its input could not be written, so the Shortcut \"\(name)\" was not run"))
            return
        }

        do {
            try launcher(Self.executable, ["run", name, "--input-path", input.path]) { exitCode, standardError in
                // Whenever it actually ends, which can be long after the
                // outcome was reported: the file lives exactly as long as the
                // process that reads it.
                Self.remove(folder)
                finish(exitCode == 0 ? .launched : .failed(Self.reason(name: name, exitCode: exitCode,
                                                                        standardError: standardError)))
            }
        } catch {
            Self.remove(folder)
            finish(.failed("the Shortcut \"\(name)\" could not be started"))
            return
        }

        // Still running when this fires is a launch: the Shortcut is under
        // way, and nothing here needs to know when, or whether, it finishes.
        // A failure after this is not reported again (§5.16: "it does not
        // retry").
        after(graceInterval) { finish(.launched) }
    }

    /// Removes every run's folder left behind, by a crash or by quitting while
    /// a Shortcut still ran, and nothing outside `root`. Returns how many.
    @discardableResult
    public func sweep() -> Int {
        let files = FileManager.default
        guard let left = try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return 0 }
        var removed = 0
        for entry in left where (try? files.removeItem(at: entry)) != nil { removed += 1 }
        return removed
    }

    // MARK: - The temp file

    private static func write(_ fields: Fields, to input: URL, in folder: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard files.createFile(atPath: input.path, contents: try encoder.encode(fields),
                               attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private nonisolated static func remove(_ folder: URL) {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Standard error is used only to tell a missing Shortcut from any other
    /// failure. What it says is never kept, logged or shown.
    ///
    /// The message is "Error: The operation couldn’t be completed. Couldn’t
    /// find shortcut", with a typographic apostrophe (macOS 26.7.1,
    /// 2026-09-29): matched with a straight one, a missing Shortcut read as
    /// any other failure. Both are accepted. On a Mac in another language
    /// the words differ, and it reads as a failure with its exit code.
    nonisolated static func reason(name: String, exitCode: Int32, standardError: String) -> String {
        if standardError.replacingOccurrences(of: "\u{2019}", with: "'").contains("Couldn't find shortcut") {
            return "the Shortcut \"\(name)\" is not installed"
        }
        return "the Shortcut \"\(name)\" stopped with exit code \(exitCode)"
    }

    // MARK: - Listing the user's Shortcuts

    /// The names of the user's Shortcuts, from `shortcuts list`, or nil if
    /// they could not be listed in time. Synchronous, because rules load
    /// synchronously; `timeout` is what bounds the wait, at a hundred times
    /// the 10 ms it was measured to take (2026-09-29). The output is the
    /// user's own Shortcut names, and is never logged.
    public nonisolated static func installedShortcuts(timeout: TimeInterval = 1) -> Set<String>? {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["list"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let listing = Listing(limit: 1 << 20)
        let finished = DispatchGroup()
        finished.enter()
        process.terminationHandler = { _ in finished.leave() }
        do {
            try process.run()
        } catch {
            finished.leave()
            return nil
        }
        finished.enter()
        let reading = output.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async {
            listing.drain(reading)
            finished.leave()
        }
        // A semaphore-style wait, not `waitUntilExit()`, which would run the
        // main run loop from inside a rules load.
        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0, let text = listing.text else { return nil }
        return names(fromList: text)
    }

    /// One name per line, as `shortcuts list` prints them, each kept exactly.
    public nonisolated static func names(fromList output: String) -> Set<String> {
        Set(output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
    }

    // MARK: - The real process and the real clock

    /// A real `Process`. Standard output goes nowhere: a Shortcut can echo its
    /// input, and a pipe nobody reads blocks its writer at 64 KB. Standard
    /// error is read as it arrives, keeping the first 4 KB, so a chatty
    /// Shortcut can never block on it either. `onExit` is called once the
    /// process has ended and its standard error is drained, on the main
    /// queue, since `terminationHandler` runs off it (ruling 19).
    public nonisolated static func launchProcess(
        _ executable: URL, _ arguments: [String],
        _ onExit: @escaping @MainActor (_ exitCode: Int32, _ standardError: String) -> Void
    ) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors

        let kept = Listing(limit: 4096)
        let ended = DispatchGroup()
        ended.enter()
        process.terminationHandler = { _ in ended.leave() }
        do {
            try process.run()
        } catch {
            ended.leave()
            throw error
        }
        ended.enter()
        let reading = errors.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            kept.drain(reading)
            ended.leave()
        }
        let exited = Exited(process)
        ended.notify(queue: .main) {
            MainActor.assumeIsolated { onExit(exited.status, kept.start) }
        }
    }

    /// The real grace timer, on the main queue.
    public nonisolated static func onMainQueue(_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            MainActor.assumeIsolated { work() }
        }
    }
}

/// Whether a run has reported yet.
@MainActor
private final class Decided {
    var done = false
}

/// Reads a pipe to its end, keeping at most `limit` bytes and discarding the
/// rest, so a writer is never blocked and memory never grows. Read on one
/// background thread and then, once that has finished, on the main thread.
private final class Listing: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var kept = Data()
    private var overflowed = false

    init(limit: Int) { self.limit = limit }

    func drain(_ handle: FileHandle) {
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            lock.lock()
            let room = limit - kept.count
            if chunk.count > room { overflowed = true }
            if room > 0 { kept.append(chunk.prefix(room)) }
            lock.unlock()
        }
    }

    /// What was kept, even if more arrived: enough to recognise a message.
    var start: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: kept, as: UTF8.self)
    }

    /// nil when more arrived than was kept: a list cut short is not a list.
    var text: String? {
        lock.lock()
        defer { lock.unlock() }
        return overflowed ? nil : String(decoding: kept, as: UTF8.self)
    }
}

/// A process's exit code, read only once it has ended.
private final class Exited: @unchecked Sendable {
    private let process: Process
    init(_ process: Process) { self.process = process }
    var status: Int32 { process.terminationStatus }
}
