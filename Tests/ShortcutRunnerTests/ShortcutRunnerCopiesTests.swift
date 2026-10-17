import XCTest
@testable import ShortcutRunner

/// Two copies of the app running at the same time share the one folder runs are made in
/// (#106). Each sweeps at launch and at quit, so a sweep must leave a running copy's input
/// alone, while still removing what a copy that has ended left behind.
@MainActor
final class ShortcutRunnerCopiesTests: XCTestCase {
    private var root: URL!
    private var running: Set<Int32> = []
    private var inputs: [String] = []

    private let fields = ShortcutRunner.Fields(appNameGuess: "Placeholder app", title: "Placeholder title",
                                               subtitle: "General", body: "Placeholder body text")

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShortcutRunnerCopiesTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
            .appendingPathComponent("shortcut-input", isDirectory: true)
        running = []
        inputs = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    /// A copy of the app, as process `pid`, whose Shortcuts never end.
    private func copy(_ pid: Int32) -> ShortcutRunner {
        ShortcutRunner(root: root, launcher: { [unowned self] _, arguments, _ in
            inputs.append(arguments[2])
        }, after: { _, _ in }, processID: pid, isRunning: { [unowned self] in running.contains($0) })
    }

    private func run(_ runner: ShortcutRunner) {
        runner.run(name: "Page the on-call phone", fields: fields) { _ in }
    }

    private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    private func folders() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
    }

    func testARunsFolderIsNamedForTheProcessThatMadeIt() throws {
        run(copy(4242))
        let name = try XCTUnwrap(try folders().first)
        XCTAssertTrue(name.hasPrefix("4242-"), name)
        XCTAssertEqual(ShortcutRunner.owner(ofFolderNamed: name), 4242)
    }

    func testASecondCopysSweepLeavesARunningCopysInputAlone() throws {
        running = [100, 200]
        run(copy(100))
        let first = try XCTUnwrap(inputs.first)

        XCTAssertEqual(copy(200).sweep(), 0, "the first copy is running, so its folder is not the second's to remove")
        XCTAssertTrue(exists(first), "the first copy's Shortcut is still reading its input")
    }

    func testASweepRemovesWhatACopyThatHasEndedLeftBehind() throws {
        running = [100, 200]
        run(copy(100))
        let first = try XCTUnwrap(inputs.first)
        running = [200]

        XCTAssertEqual(copy(200).sweep(), 1)
        XCTAssertFalse(exists(first))
        XCTAssertEqual(try folders(), [])
    }

    func testASweepRemovesItsOwnProcesssFolders() throws {
        running = [100]
        let runner = copy(100)
        run(runner)
        run(runner)
        XCTAssertEqual(runner.sweep(), 2, "at quit, a copy removes its own runs, as it did before")
        XCTAssertEqual(try folders(), [])
    }

    func testAFolderWithNoProcessIdIsRemovedAsBefore() throws {
        // An earlier version named a run's folder with a UUID alone.
        let legacy = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        running = [100, 200]
        run(copy(100))

        XCTAssertEqual(copy(200).sweep(), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertEqual(try folders().count, 1, "only the running copy's folder is left")
    }

    func testOnlyANameThatBeginsWithAPositiveProcessIdHasAnOwner() {
        XCTAssertEqual(ShortcutRunner.owner(ofFolderNamed: "77-\(UUID().uuidString)"), 77)
        XCTAssertNil(ShortcutRunner.owner(ofFolderNamed: UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")))
        XCTAssertNil(ShortcutRunner.owner(ofFolderNamed: "0-x"))
        XCTAssertNil(ShortcutRunner.owner(ofFolderNamed: "-5-x"))
        XCTAssertNil(ShortcutRunner.owner(ofFolderNamed: "AB12-x"))
    }

    func testThisProcessIsRunningAndAnIdNoProcessHasIsNot() {
        XCTAssertTrue(ShortcutRunner.processIsRunning(ProcessInfo.processInfo.processIdentifier))
        XCTAssertTrue(ShortcutRunner.processIsRunning(1), "launchd exists, though it is not ours to signal")
        XCTAssertFalse(ShortcutRunner.processIsRunning(0))
        XCTAssertFalse(ShortcutRunner.processIsRunning(-1))
        XCTAssertFalse(ShortcutRunner.processIsRunning(Int32.max))
    }
}
