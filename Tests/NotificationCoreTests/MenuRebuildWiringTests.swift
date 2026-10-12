import XCTest
@testable import NotificationCore

/// How the app target carries out what `MenuRebuildGate` answers when the status
/// menu closes (M5 plan, Ruling 22).
///
/// The app target has no tests, and what the gate cannot hold is the close: that
/// `menuDidClose` tells it the menu has closed, and makes the rebuild its answer
/// says is owed. The answer can be discarded without a warning, so a close that
/// drops it builds cleanly, and so does one that tells the gate nothing, and either
/// way the rebuild held back while the menu was open is never made. So this reads
/// the app's sources, as `OnCallWiringTests` does, and holds the close to what it is
/// meant to say. It starts nothing and opens no menu.
final class MenuRebuildWiringTests: XCTestCase {
    private func code(_ file: String) throws -> String {
        PowerHoldWiringTests.code(of: try XCTUnwrap(AppSources.read(file),
                                                    "\(file) cannot be read at \(AppSources.directory.path)"))
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private func body(of signature: String, in code: String) throws -> String {
        try XCTUnwrap(OnCallWiringTests.body(of: signature, in: code),
                      "\(signature) is not in the source exactly once, or is not closed")
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The close of the status item's menu tells the gate, once, and goes on only
    /// when the answer is not empty. The close answers the rebuild of the items alone
    /// when one was held, and nothing when none was (`MenuRebuildGateTests`), so that
    /// is reading whether a rebuild is owed. The rebuild is not made in the close: it
    /// is reported before the chosen item's action runs, and emptying the menu then
    /// would take that item away. The next turn of the main queue makes it, through
    /// `rebuildMenu()`, which asks the gate again, so that a menu opened again in
    /// between is still held, and makes the items when the gate says so.
    func testClosingTellsTheGateTheMenuClosedAndMakesTheRebuildItSaysIsOwedOnTheNextTurn() throws {
        let app = try code("AppDelegate.swift")
        let closes = try body(of: "func menuDidClose(_ menu: NSMenu) {", in: app)
        XCTAssertEqual(trimmed(closes), [
            "guard menu === statusItem?.menu else { return }",
            "guard !menuGate.menuClosed().isEmpty else { return }",
            "DispatchQueue.main.async { [weak self] in",
            "MainActor.assumeIsolated { self?.rebuildMenu() }",
            "}",
        ].joined(separator: "\n"))

        let rebuild = try body(of: "private func rebuildMenu(loginItemStatus: LoginItemStatus? = nil) {", in: app)
        XCTAssertEqual(count("for step in menuGate.request() {", in: rebuild), 1, "the rebuild asks the gate again")
        XCTAssertEqual(count("case .rebuildItems: rebuildMenuItems(loginItemStatus: loginItemStatus)", in: rebuild), 1,
                       "and makes the items when it says so")

        // The other place is `menuNeedsUpdate`, whose build as the menu opens is the
        // owed one (`OnCallWiringTests`). A third, with nothing to make of the answer,
        // could take the owed rebuild and make none.
        XCTAssertEqual(count("menuGate.menuClosed()", in: app), 2, "this close and the opening, and nowhere else")
    }
}
