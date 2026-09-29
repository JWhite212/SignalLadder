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

        // Without its input the Shortcut is not run. Running it bare would be
        // a fallback that quietly does something else; the failure is
        // reported instead, as any other failure of the last tier is.
        do {
            try Self.write(fields, to: input, in: folder)
        } catch {
            Self.remove(folder)
            finish(.failed("its input could not be written, so the Shortcut \"\(name)\" was not run"))
            return
        }

        do {
            try launcher(Self.executable, Self.arguments(name: name, input: input)) { exitCode, standardError in
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

    /// The name goes last, after `--`: without it, `shortcuts` read a name
    /// starting with "-" as an option and exited 64 before looking it up
    /// (macOS 26.7.1, 2026-09-30), so a Shortcut the load check had accepted
    /// could never run. It is one argument, never passed through a shell.
    nonisolated static func arguments(name: String, input: URL) -> [String] {
        ["run", "--input-path", input.path, "--", name]
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

        let reader = PipeReader(output, limit: 1 << 20)
        let ended = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in ended.signal() }
        do {
            try process.run()
        } catch {
            reader.stop()
            return nil
        }
        // A semaphore, not `waitUntilExit()`, which would run the main run
        // loop from inside a rules load.
        guard ended.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            reader.stop()
            return nil
        }
        let status = process.terminationStatus
        let whole = reader.finishNow().whole
        guard status == 0, let whole else { return nil }
        return names(fromList: whole)
    }

    /// One name per line, as `shortcuts list` prints them, each kept exactly.
    public nonisolated static func names(fromList output: String) -> Set<String> {
        Set(output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
    }

    // MARK: - The real process and the real clock

    /// A real `Process`. Standard output goes nowhere: a Shortcut can echo its
    /// input, and a pipe nobody reads blocks its writer at 64 KB. Standard
    /// error is read as it arrives, without blocking, keeping the first 4 KB.
    ///
    /// The process ending is the only event that ends a run. `onExit` does
    /// not wait for standard error to close: something the Shortcut started
    /// can inherit it and outlive it, and must not keep the temp file alive.
    /// Nor is a thread held while a Shortcut runs. A first version read
    /// standard error on a blocked thread until it closed, and with 70 or so
    /// Shortcuts running at once that starved the shared threads, so a
    /// missing Shortcut read as launched and its file stayed until they
    /// ended (review, 2026-09-30). `onExit` runs on the main queue, since
    /// `terminationHandler` runs off it (ruling 19).
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

        let reader = PipeReader(errors, limit: 4096)
        process.terminationHandler = { ended in
            let status = ended.terminationStatus
            reader.finish { start, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { onExit(status, start) }
                }
            }
        }
        do {
            try process.run()
        } catch {
            reader.stop()
            throw error
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

/// Reads a pipe as data arrives, without ever blocking a thread on it,
/// keeping at most `limit` bytes and discarding the rest, so a writer is
/// never held up and memory never grows. Everything it does happens on its
/// own serial queue.
final class PipeReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.jamiewhite.signalladder.pipe-reader", qos: .utility)
    private let handle: FileHandle
    private let descriptor: Int32
    private let source: DispatchSourceRead
    private let limit: Int
    private var kept = Data()
    private var overflowed = false
    private var stopped = false

    init(_ pipe: Pipe, limit: Int) {
        self.limit = limit
        handle = pipe.fileHandleForReading
        descriptor = handle.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { [handle] in try? handle.close() }
        source.resume()
    }

    /// What was read so far, and whether it is the whole of it.
    struct Read {
        /// The first `limit` bytes: enough to recognise a message.
        let start: String
        /// Everything, or nil when more arrived than was kept: a list cut
        /// short is not a list.
        let whole: String?
    }

    /// Reads whatever is waiting, stops, and hands over what was kept. Called
    /// once the writer has ended, so nothing more is waited for.
    func finish(_ done: @escaping @Sendable (_ start: String, _ whole: String?) -> Void) {
        queue.async {
            let read = self.finishOnQueue()
            done(read.start, read.whole)
        }
    }

    /// As `finish`, waiting for it.
    func finishNow() -> Read {
        queue.sync { finishOnQueue() }
    }

    /// Stops reading and keeps nothing more.
    func stop() {
        queue.async { self.stopOnQueue() }
    }

    private func finishOnQueue() -> Read {
        drain()
        stopOnQueue()
        let start = String(decoding: kept, as: UTF8.self)
        return Read(start: start, whole: overflowed ? nil : start)
    }

    /// Reads until nothing more is waiting, or the writer has closed.
    private func drain() {
        guard !stopped else { return }
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                let room = limit - kept.count
                if count > room { overflowed = true }
                if room > 0 { kept.append(contentsOf: buffer[0..<min(count, room)]) }
            } else if count == 0 {
                // Closed. Stopping here also keeps a reader whose writer
                // closed early from being woken again and again.
                stopOnQueue()
                return
            } else if errno != EINTR {
                return
            }
        }
    }

    /// Cancelling closes the descriptor, and `stopped` keeps a later read
    /// from touching a number the system may have given to something else.
    private func stopOnQueue() {
        guard !stopped else { return }
        stopped = true
        source.cancel()
    }
}
