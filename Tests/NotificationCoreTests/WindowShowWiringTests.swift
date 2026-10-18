import XCTest
@testable import NotificationCore

/// Every window the app shows can be minimised, and showing it must bring it back from the
/// Dock. The rule editor and the Setup Guide did, and the Inspector, Settings and the
/// On-Call Check did not, so their menu items, and the check window's beep for a new
/// finding while on call, could leave the window on the Dock (workflow audit, 2026-10-16,
/// finding 5). Each controller now shows its window the same way: activate, bring it back
/// if it is minimised, then make it key and front. The app target has no tests, so this
/// reads its sources, as `SetupWiringTests` does, and it reads every window controller
/// there is, so one added later is held too.
final class WindowShowWiringTests: XCTestCase {
    private func run(_ lines: [String], in text: String) -> Int {
        count("\n" + lines.joined(separator: "\n") + "\n", in: "\n" + text + "\n")
    }

    private func controllers() throws -> [String] {
        try AppSources.fileNames().filter { $0.hasSuffix("WindowController.swift") }
    }

    func testTheWindowControllersAreTheFiveTheAppShows() throws {
        XCTAssertEqual(try controllers(), [
            "InspectorWindowController.swift",
            "OnCallCheckWindowController.swift",
            "RuleEditorWindowController.swift",
            "SettingsWindowController.swift",
            "SetupWindowController.swift",
        ], "a window controller added or gone: say here how it is shown")
    }

    func testEveryMinimisableWindowIsBroughtBackFromTheDockWhenItIsShown() throws {
        for file in try controllers() {
            let source = try code(file)
            XCTAssertTrue(source.contains(".miniaturizable"), "\(file): its window can be minimised")
            XCTAssertEqual(run([
                "NSApp.activate(ignoringOtherApps: true)",
                "if window?.isMiniaturized == true { window?.deminiaturize(nil) }",
                "window?.makeKeyAndOrderFront(nil)",
            ], in: source), 1, "\(file): activate, bring it back, then front")
            XCTAssertEqual(count("makeKeyAndOrderFront(", in: source), 1, "\(file): shown in one place")
        }
    }
}
