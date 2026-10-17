import XCTest
@testable import ShortcutRunner

/// A Shortcut reported as launched by the grace interval that then stops with an error
/// is reported once more, as a late failure (1.1 plan, Ruling 16). Nothing else is.
@MainActor
final class ShortcutLateFailureTests: XCTestCase {
    private var root: URL!
    private var exits: [(Int32, String) -> Void] = []
    private var graceTimers: [() -> Void] = []
    private var outcomes: [ShortcutRunner.Outcome] = []
    private var lateFailures: [String] = []

    private let fields = ShortcutRunner.Fields(appNameGuess: "Placeholder app", title: "Placeholder title",
                                               subtitle: "General", body: "Placeholder body text")

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShortcutLateFailureTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
            .appendingPathComponent("shortcut-input", isDirectory: true)
        exits = []
        graceTimers = []
        outcomes = []
        lateFailures = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func launch(lateFailure: Bool = true) {
        let runner = ShortcutRunner(root: root, launcher: { [unowned self] _, _, onExit in
            exits.append(onExit)
        }, after: { [unowned self] _, work in graceTimers.append(work) })
        let completion: @MainActor (ShortcutRunner.Outcome) -> Void = { [unowned self] outcome in
            outcomes.append(outcome)
        }
        if lateFailure {
            runner.run(name: "Page me", fields: fields, completion: completion, lateFailure: { [unowned self] reason in
                lateFailures.append(reason)
            })
        } else {
            runner.run(name: "Page me", fields: fields, completion: completion)
        }
    }

    func testAFailureAfterTheGraceIsReportedOnceAsALateFailure() throws {
        launch()
        try XCTUnwrap(graceTimers.first)()
        try XCTUnwrap(exits.first)(1, "Error: something the Shortcut said")
        XCTAssertEqual(outcomes, [.launched])
        XCTAssertEqual(lateFailures, ["the Shortcut \"Page me\" started, then stopped with exit code 1"],
                       "the app's own words, never the Shortcut's output")
    }

    func testACleanExitAfterTheGraceReportsNothingMore() throws {
        launch()
        try XCTUnwrap(graceTimers.first)()
        try XCTUnwrap(exits.first)(0, "")
        XCTAssertEqual(outcomes, [.launched])
        XCTAssertEqual(lateFailures, [])
    }

    func testAnExitBeforeTheGraceIsNeverALateFailure() throws {
        launch()
        try XCTUnwrap(exits.first)(1, "")
        try XCTUnwrap(graceTimers.first)()
        XCTAssertEqual(outcomes, [.failed("the Shortcut \"Page me\" stopped with exit code 1")])
        XCTAssertEqual(lateFailures, [], "reported once, as the failure it is")
    }

    /// A caller that passes none, as before, is told nothing more, and nothing breaks.
    func testWithNoLateFailureAskedForALateExitChangesNothing() throws {
        launch(lateFailure: false)
        try XCTUnwrap(graceTimers.first)()
        try XCTUnwrap(exits.first)(1, "")
        XCTAssertEqual(outcomes, [.launched])
    }
}
