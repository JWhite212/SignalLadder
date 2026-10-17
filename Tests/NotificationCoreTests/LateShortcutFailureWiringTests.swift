import XCTest
@testable import NotificationCore

/// A Shortcut that stops with an error after it was reported as launched (1.1 plan,
/// Ruling 16) reaches the coordinator from the runner, the pipeline from the
/// coordinator, and the editor's report from Test Shortcut. These read the app
/// target's sources and show the lines are there, not that they run.
final class LateShortcutFailureWiringTests: XCTestCase {
    private func code(_ file: String) throws -> String {
        PowerHoldWiringTests.code(of: try XCTUnwrap(AppSources.read(file),
                                                    "\(file) cannot be read at \(AppSources.directory.path)"))
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    func testTheTierFourClosurePassesTheLateFailureOn() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("runShortcut: { [weak self] name, notification, report, lateFailure in", in: app), 1)
        XCTAssertEqual(count("}, lateFailure: lateFailure)", in: app), 1,
                       "the runner's late failure is the coordinator's, unchanged")
    }

    func testARetiredEscalationsLateFailureIsHeldByThePipeline() throws {
        let app = try code("AppDelegate.swift")
        XCTAssertEqual(count("self?.capture.recordLateShortcutFailure(ruleName: ruleName, shortcutName: shortcutName, reason: reason)",
                             in: app), 1)
        let capture = try code("CaptureController.swift")
        XCTAssertEqual(count("pipeline.recordLateShortcutFailure(ruleName: ruleName, shortcutName: shortcutName, reason: reason, at: Date())",
                             in: capture), 1)
    }

    /// Shown beside the button if the report still names that Shortcut, and held
    /// nowhere: a test that fails is a draft's business, not the menu's.
    func testTestShortcutShowsALateFailureBesideTheButtonOnly() throws {
        let editor = try code("RuleEditorModel.swift")
        // Built in two parts, so that counting test declarations by their text finds tests only.
        let signature = "func " + "testShortcut(name: String) {"
        let test = try XCTUnwrap(OnCallWiringTests.body(of: signature, in: editor))
        XCTAssertEqual(count("lateFailure: { [weak self] reason in", in: test), 1)
        XCTAssertEqual(count("guard let self, shortcutTest?.name == name else { return }", in: test), 1)
        XCTAssertEqual(count("outcome: .failed(reason)", in: test), 2, "the failure to start, and the late one")
        XCTAssertFalse(test.contains("recordLateShortcutFailure"), "held nowhere")
    }
}
