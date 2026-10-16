import XCTest
@testable import NotificationCore

/// The menu's advice line opens the pane its cause names, and none for a cause no pane fixes
/// (`HealthCause.pane`, 2026-10-16). It carries the pane it was built with, so a click acts on
/// the cause the user read and not on whatever health reads when the click lands. The Keyboard
/// pane's address is the core's. The app target has no tests, so this reads its sources.
final class CausePaneWiringTests: XCTestCase {
    private func code(_ file: String) throws -> String {
        PowerHoldWiringTests.code(of: try XCTUnwrap(AppSources.read(file), "\(file) cannot be read at \(AppSources.directory.path)"))
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private func run(_ lines: [String], in text: String) -> Int {
        count("\n" + lines.joined(separator: "\n") + "\n", in: "\n" + text + "\n")
    }

    /// Measured on macOS 27.2 on 2026-10-16: this opened System Settings › Keyboard, which
    /// shows Keyboard navigation.
    func testTheKeyboardPanesAddress() {
        XCTAssertEqual(BundleResolver.keyboardSettingsURL.absoluteString, "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    func testTheAdviceLineCarriesItsCausesPaneAndHasNoActionForNone() throws {
        let app = try code("AppDelegate.swift")
        let items = try XCTUnwrap(OnCallWiringTests.body(of: "private func rebuildMenuItems(loginItemStatus: LoginItemStatus?) {", in: app))
        XCTAssertEqual(run([
            "if let cause = firstCause {",
            "let advice = NSMenuItem(title: cause.advice, action: cause.pane == nil ? nil : #selector(openSettingsForCause),",
            "keyEquivalent: \"\")",
            "advice.target = self",
            "advice.representedObject = cause.pane?.rawValue",
            "menu.addItem(advice)",
            "}",
        ], in: items), 1)
        let opens = try XCTUnwrap(OnCallWiringTests.body(of: "@objc private func openSettingsForCause(_ sender: NSMenuItem) {", in: app))
        XCTAssertEqual(opens.trimmingCharacters(in: .whitespacesAndNewlines), [
            "guard let raw = sender.representedObject as? String, let pane = HealthCause.Pane(rawValue: raw) else { return }",
            "OnboardingCoordinator.open(pane)",
        ].joined(separator: "\n"))
    }

    func testEachPaneIsOpenedByItsHelper() throws {
        let coordinator = try code("OnboardingCoordinator.swift")
        let open = try XCTUnwrap(OnCallWiringTests.body(of: "static func open(_ pane: HealthCause.Pane) {", in: coordinator))
        XCTAssertEqual(open.trimmingCharacters(in: .whitespacesAndNewlines), [
            "switch pane {",
            "case .notifications: openNotificationSettings()",
            "case .accessibility: openAccessibilitySettings()",
            "case .keyboard: openKeyboardSettings()",
            "}",
        ].joined(separator: "\n"))
        let keyboard = try XCTUnwrap(OnCallWiringTests.body(of: "static func openKeyboardSettings() {", in: coordinator))
        XCTAssertEqual(keyboard.trimmingCharacters(in: .whitespacesAndNewlines), "NSWorkspace.shared.open(BundleResolver.keyboardSettingsURL)")
    }
}
