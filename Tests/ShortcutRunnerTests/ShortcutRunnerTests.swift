import XCTest
@testable import ShortcutRunner

/// The Shortcut runner (M4 Task 2), against real temporary folders. A fake
/// launcher stands in for the process and a fake clock for the grace
/// interval, so no test ever starts `/usr/bin/shortcuts` or waits on a real
/// clock. Fixtures are invented text, never captured content (§10.1).
@MainActor
final class ShortcutRunnerTests: XCTestCase {
    private var root: URL!
    private var outside: URL!

    /// What the fake launcher was asked to start, and how to end it.
    private struct Launch {
        let executable: URL
        let arguments: [String]
        let exit: @MainActor (Int32, String) -> Void
        var inputPath: String { arguments.firstIndex(of: "--input-path").map { arguments[$0 + 1] } ?? "" }
        var folder: URL { URL(fileURLWithPath: inputPath).deletingLastPathComponent() }
    }

    private var launches: [Launch] = []
    private var graceTimers: [(seconds: TimeInterval, fire: @MainActor () -> Void)] = []
    private var outcomes: [ShortcutRunner.Outcome] = []
    private var inputExistedAtLaunch: [Bool] = []

    private let fields = ShortcutRunner.Fields(appNameGuess: "Microsoft Teams", title: "Alex Example mentioned you",
                                               subtitle: "General", body: "Placeholder body text")

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShortcutRunnerTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        root = base.appendingPathComponent("shortcut-input", isDirectory: true)
        outside = base.appendingPathComponent("not-ours", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        launches = []
        graceTimers = []
        outcomes = []
        inputExistedAtLaunch = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func runner(throwing: Bool = false, grace: TimeInterval = 1) -> ShortcutRunner {
        ShortcutRunner(root: root, launcher: { [unowned self] executable, arguments, onExit in
            if throwing { throw CocoaError(.executableNotLoadable) }
            let launch = Launch(executable: executable, arguments: arguments, exit: onExit)
            inputExistedAtLaunch.append(FileManager.default.fileExists(atPath: launch.inputPath))
            launches.append(launch)
        }, after: { [unowned self] seconds, work in
            graceTimers.append((seconds, work))
        }, graceInterval: grace)
    }

    private func run(_ runner: ShortcutRunner, name: String = "Page the on-call phone") {
        runner.run(name: name, fields: fields) { [unowned self] in outcomes.append($0) }
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private func permissions(_ url: URL) throws -> Int {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    // MARK: - What it starts

    func testItRunsShortcutsRunWithTheNameAndTheInputFile() throws {
        run(runner())
        let launch = try XCTUnwrap(launches.first)
        XCTAssertEqual(launch.executable.path, "/usr/bin/shortcuts")
        XCTAssertEqual(launch.arguments, ["run", "--input-path", launch.inputPath, "--", "Page the on-call phone"])
        XCTAssertEqual(launch.folder.deletingLastPathComponent().path, root.path, "each run's folder is inside root")
        XCTAssertEqual(inputExistedAtLaunch, [true], "the file is written before the Shortcut starts")
    }

    func testTheInputHoldsExactlyTheFourFields() throws {
        // Never the raw text, which can carry more of the tree than a
        // Shortcut needs, nor the time or the subrole.
        run(runner())
        let data = try Data(contentsOf: URL(fileURLWithPath: try XCTUnwrap(launches.first).inputPath))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object, ["appNameGuess": "Microsoft Teams", "title": "Alex Example mentioned you",
                                "subtitle": "General", "body": "Placeholder body text"])
    }

    func testTheFolderIsForTheOwnerAloneAndSoIsTheFile() throws {
        run(runner())
        let launch = try XCTUnwrap(launches.first)
        XCTAssertEqual(try permissions(launch.folder), 0o700)
        XCTAssertEqual(try permissions(URL(fileURLWithPath: launch.inputPath)), 0o600)
    }

    func testADashedNameIsNeverReadAsAnOption() throws {
        // Without "--", shortcuts read "-Page" as an option and exited 64.
        run(runner(), name: "-Page the on-call phone")
        XCTAssertEqual(Array(try XCTUnwrap(launches.first).arguments.suffix(2)), ["--", "-Page the on-call phone"])
    }

    func testANameIsOneArgumentExactlyAsWritten() throws {
        // Never through a shell, so quotes and $(…) are only characters.
        let name = #" Page "the" $(phone) `now` "#
        run(runner(), name: name)
        XCTAssertEqual(try XCTUnwrap(launches.first).arguments.last, name)
    }

    func testTheDefaultRootIsTheAppsOwnFolderInTheTemporaryDirectory() {
        // sweep() empties root, so root must be ours alone.
        XCTAssertEqual(ShortcutRunner.defaultRoot.lastPathComponent, "com.jamiewhite.signalladder.shortcut-input")
        XCTAssertEqual(ShortcutRunner.defaultRoot.deletingLastPathComponent().standardizedFileURL,
                       FileManager.default.temporaryDirectory.standardizedFileURL)
        XCTAssertEqual(ShortcutRunner().root, ShortcutRunner.defaultRoot)
    }

    func testTwoRunsNeverShareAFolder() throws {
        let shortcuts = runner()
        run(shortcuts)
        run(shortcuts)
        XCTAssertEqual(launches.count, 2)
        XCTAssertNotEqual(launches[0].folder, launches[1].folder)
    }

    // MARK: - What it reports, once

    func testOneShortcutEndingLeavesAnotherRunningShortcutsInputAlone() throws {
        let shortcuts = runner()
        run(shortcuts)
        run(shortcuts)
        let (first, second) = (launches[0], launches[1])
        first.exit(0, "")
        XCTAssertFalse(exists(first.folder))
        XCTAssertTrue(exists(URL(fileURLWithPath: second.inputPath)), "the other Shortcut is still reading it")
        second.exit(0, "")
        XCTAssertFalse(exists(second.folder))
        XCTAssertEqual(outcomes, [.launched, .launched])
    }

    func testAQuickCleanExitIsALaunchAndTheFileGoes() throws {
        run(runner())
        let launch = try XCTUnwrap(launches.first)
        launch.exit(0, "")
        XCTAssertEqual(outcomes, [.launched])
        XCTAssertFalse(exists(launch.folder))
    }

    func testAMissingShortcutIsReportedAsNotInstalled() throws {
        // The measured shape: exit 1, "Couldn't find shortcut", in about
        // 150 ms, well inside the grace interval.
        run(runner(), name: "Page me")
        let launch = try XCTUnwrap(launches.first)
        // Exactly as measured, typographic apostrophes and all.
        launch.exit(1, "Error: The operation couldn\u{2019}t be completed. Couldn\u{2019}t find shortcut\n")
        XCTAssertEqual(outcomes, [.failed("the Shortcut \"Page me\" is not installed")])
        XCTAssertFalse(exists(launch.folder))
    }

    func testAMissingShortcutIsRecognisedWithAStraightApostropheToo() {
        XCTAssertEqual(ShortcutRunner.reason(name: "Page me", exitCode: 1, standardError: "Couldn't find shortcut"),
                       "the Shortcut \"Page me\" is not installed")
    }

    func testAnotherFailureGivesTheExitCodeAndNeverTheOutput() throws {
        // A Shortcut can echo its input, which is notification content.
        run(runner(), name: "Page me")
        let launch = try XCTUnwrap(launches.first)
        launch.exit(3, "Alex Example mentioned you: Placeholder body text")
        XCTAssertEqual(outcomes, [.failed("the Shortcut \"Page me\" stopped with exit code 3")])
        guard case .failed(let reason) = outcomes.first else { return XCTFail() }
        XCTAssertFalse(reason.contains("Alex Example") || reason.contains("Placeholder"), reason)
    }

    func testStillRunningWhenTheGraceEndsIsALaunchAndTheFileStaysUntilItExits() throws {
        run(runner())
        let launch = try XCTUnwrap(launches.first)
        try XCTUnwrap(graceTimers.first).fire()
        XCTAssertEqual(outcomes, [.launched])
        XCTAssertTrue(exists(launch.folder), "the Shortcut is still reading it")

        // It fails later, inside its own actions: the launch was already
        // reported, and is not reported again (§5.16), but the file goes.
        launch.exit(1, "")
        XCTAssertEqual(outcomes, [.launched])
        XCTAssertFalse(exists(launch.folder))
    }

    func testAnExitThenTheGraceTimerReportsOnce() throws {
        run(runner())
        try XCTUnwrap(launches.first).exit(0, "")
        try XCTUnwrap(graceTimers.first).fire()
        XCTAssertEqual(outcomes, [.launched])
    }

    func testAFailedExitThenTheGraceTimerReportsTheFailureOnce() throws {
        run(runner(), name: "Page me")
        try XCTUnwrap(launches.first).exit(1, "Couldn't find shortcut")
        try XCTUnwrap(graceTimers.first).fire()
        XCTAssertEqual(outcomes, [.failed("the Shortcut \"Page me\" is not installed")])
    }

    func testTheGraceIntervalIsTheOneGiven() {
        run(runner(grace: 0.25))
        XCTAssertEqual(graceTimers.map(\.seconds), [0.25])
    }

    func testTheGraceIntervalIsOneSecondByDefault() {
        let shortcuts = ShortcutRunner(root: root, launcher: { _, _, _ in }, after: { [unowned self] seconds, work in
            graceTimers.append((seconds, work))
        })
        run(shortcuts)
        XCTAssertEqual(graceTimers.map(\.seconds), [1])
    }

    func testRunReturnsBeforeAnythingIsReported() {
        // Nothing here waits for the Shortcut: a long one would otherwise
        // stall capture, which shares the main run loop (ruling 19).
        run(runner())
        XCTAssertEqual(outcomes, [])
    }

    func testALaunchThatThrowsFailsAtOnceAndLeavesNothing() throws {
        run(runner(throwing: true), name: "Page me")
        XCTAssertEqual(outcomes, [.failed("the Shortcut \"Page me\" could not be started")])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        XCTAssertEqual(graceTimers.count, 0)
    }

    func testAnInputThatCannotBeWrittenFailsAtOnceAndStartsNothing() throws {
        // Without its input the Shortcut is not run: running it bare would be
        // a fallback that quietly does something else.
        try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("in the way".utf8).write(to: root)
        run(runner(), name: "Page me")
        XCTAssertEqual(outcomes, [.failed("its input could not be written, so the Shortcut \"Page me\" was not run")])
        XCTAssertEqual(launches.count, 0)
        XCTAssertEqual(graceTimers.count, 0)
        XCTAssertEqual(try String(contentsOf: root, encoding: .utf8), "in the way")
    }

    // MARK: - What is left behind

    func testSweepRemovesEveryLeftoverRunAndNothingOutsideRoot() throws {
        // A crash, or a quit while a Shortcut still ran.
        run(runner())
        run(runner())
        let bystander = outside.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: bystander)

        XCTAssertEqual(runner().sweep(), 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        XCTAssertTrue(exists(bystander))
    }

    func testSweepingWhenNothingWasEverRunIsHarmless() {
        XCTAssertEqual(runner().sweep(), 0)
    }

    // MARK: - Reading a pipe without blocking

    /// Writes `bytes` into a pipe from another thread, then closes it unless
    /// told not to, and waits until the writer is done.
    private func write(_ bytes: Data, into pipe: Pipe, close: Bool = true) {
        let written = expectation(description: "writer finished")
        let writer = pipe.fileHandleForWriting
        DispatchQueue.global().async {
            writer.write(bytes)
            if close { try? writer.close() }
            written.fulfill()
        }
        wait(for: [written], timeout: 5)
    }

    func testAReaderKeepsItsLimitAndNeverBlocksTheWriter() {
        // 70,000 bytes is more than a pipe holds, so the writer finishes only
        // if the reader keeps draining.
        let pipe = Pipe()
        let reader = PipeReader(pipe, limit: 4096)
        write(Data(repeating: UInt8(ascii: "x"), count: 70_000), into: pipe)
        let read = reader.finishNow()
        XCTAssertEqual(read.start.utf8.count, 4096)
        XCTAssertNil(read.whole, "a list cut short is not a list")
    }

    func testAReaderThatFitsIsWhole() {
        let pipe = Pipe()
        let reader = PipeReader(pipe, limit: 4096)
        write(Data("Page on-call\nLog it\n".utf8), into: pipe)
        XCTAssertEqual(reader.finishNow().whole, "Page on-call\nLog it\n")
    }

    func testFinishingDoesNotWaitForAWriterThatStaysOpen() {
        // What a Shortcut started can inherit its standard error and outlive
        // it. The process ending must end the run all the same.
        let pipe = Pipe()
        let reader = PipeReader(pipe, limit: 4096)
        write(Data("Couldn't find shortcut".utf8), into: pipe, close: false)
        let started = Date()
        XCTAssertEqual(reader.finishNow().start, "Couldn't find shortcut")
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        try? pipe.fileHandleForWriting.close()
    }

    // MARK: - Listing the user's Shortcuts

    func testAListIsOneNamePerLineEachKeptExactly() {
        XCTAssertEqual(ShortcutRunner.names(fromList: "Page on-call\nLog it \n\nMorning, Routine\n"),
                       ["Page on-call", "Log it ", "Morning, Routine"])
        XCTAssertEqual(ShortcutRunner.names(fromList: ""), [])
    }
}
