import XCTest
@testable import NotificationCore

/// ⌘W closes the window in front. An accessory app's main menu is never drawn, but its key
/// equivalents work, and without a Close item no key closed any of SignalLadder's windows:
/// the close box was the only way (workflow audit, 2026-10-16, finding 12). Close is sent
/// down the responder chain with no target, as the Edit items are, so it reaches whichever
/// window is key. `performClose(_:)` is what the close box does, so a window that asks
/// first, as the rule editor does with a draft, asks the same way, and the Setup Guide
/// records a dismissal as its close box does. The escalation panel has no close button
/// and never becomes key, so ⌘W cannot close it. There is still no Quit (`MainMenu`). The
/// app target has no tests, so this reads its source, as `SettingsWiringTests` does.
final class CloseWindowWiringTests: XCTestCase {
    private func menu() throws -> String {
        PowerHoldWiringTests.code(of: try XCTUnwrap(AppSources.read("MainMenu.swift"),
                                                    "MainMenu.swift cannot be read at \(AppSources.directory.path)"))
    }

    private func body(of signature: String, in code: String) throws -> String {
        try XCTUnwrap(OnCallWiringTests.body(of: signature, in: code),
                      "\(signature) is not in the source exactly once, or is not closed")
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    func testTheWindowMenuHoldsCloseOnCommandWSentToWhicheverWindowIsKey() throws {
        let window = try body(of: "private static func window() -> NSMenu {", in: try menu())
        XCTAssertEqual(window.trimmingCharacters(in: .whitespacesAndNewlines), [
            "let menu = NSMenu(title: \"Window\")",
            "menu.addItem(withTitle: \"Close\", action: #selector(NSWindow.performClose(_:)), keyEquivalent: \"w\")",
            "return menu",
        ].joined(separator: "\n"), "Close and nothing else, with no target")
    }

    func testTheWindowMenuComesAfterEditAndTheMenuStillHasNoQuit() throws {
        let source = try menu()
        let made = try body(of: "static func make(settingsTarget: AnyObject, settingsAction: Selector) -> NSMenu {", in: source)
        let edit = try XCTUnwrap(made.range(of: "main.addItem(editItem)"))
        let window = try XCTUnwrap(made.range(of: "main.addItem(windowItem)"), "the Window menu is added")
        XCTAssertLessThan(edit.lowerBound, window.lowerBound)
        XCTAssertEqual(count("windowItem.submenu = window()", in: made), 1)
        for word in ["terminate", "Quit", "keyEquivalent: \"q\""] {
            XCTAssertFalse(source.contains(word), word)
        }
    }
}
