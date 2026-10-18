import XCTest
@testable import NotificationCore

/// How the app answers being opened again while it runs. Which window opens is the core's
/// (`SetupPlan.windowOnReopen`); the app delegate only asks it, with the facts gathered the
/// one way they are gathered, and shows that window through its one door. When one of its
/// windows is on screen already, opening the app brings it forward and nothing more is
/// shown. The app target has no tests, so this reads its source, as `SetupWiringTests` does.
final class ReopenWiringTests: XCTestCase {
    private func app() throws -> String {
        SourceCode.code(of: try XCTUnwrap(AppSources.read("AppDelegate.swift"),
                                                    "AppDelegate.swift cannot be read at \(AppSources.directory.path)"))
    }

    func testOpeningTheAppAgainShowsTheWindowTheCoreNamesWhenNoneIsOnScreen() throws {
        let signature = "func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {"
        let reopen = try XCTUnwrap(SourceCode.body(of: signature, in: try app()), "\(signature) is not in the source exactly once")
        XCTAssertEqual(reopen.trimmingCharacters(in: .whitespacesAndNewlines), [
            "guard !flag else { return true }",
            "switch SetupPlan.windowOnReopen(setupCoordinator.facts()) {",
            "case .setupGuide: showSetupGuide()",
            "case .settings: showSettings()",
            "}",
            "return true",
        ].joined(separator: "\n"))
    }
}
