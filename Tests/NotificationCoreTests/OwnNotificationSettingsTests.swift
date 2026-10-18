import XCTest
@testable import NotificationCore

/// "Open Notification Settings…", in the Setup Guide and on the menu's advice line, promises
/// SignalLadder's own page, and opened the top of Notifications (workflow audit, 2026-10-16,
/// finding 8). It now opens the page the mute walkthrough's links open for other apps, with
/// SignalLadder's own bundle identifier. Measured on macOS 27.2 on 2026-10-16: System Settings
/// opened on a window titled SignalLadder, with Allow notifications and Alert Style.
final class OwnNotificationSettingsTests: XCTestCase {
    func testItOpensSignalLaddersOwnPage() {
        XCTAssertEqual(BundleResolver.ownNotificationSettingsURL(bundleID: "com.jamiewhite.signalladder").absoluteString,
                       "x-apple.systempreferences:com.apple.preference.notifications?id=com.jamiewhite.signalladder")
    }

    /// A build run from the command line has no bundle identifier: the pane itself.
    func testWithNoBundleIdentifierItOpensThePane() {
        XCTAssertEqual(BundleResolver.ownNotificationSettingsURL(bundleID: nil).absoluteString,
                       "x-apple.systempreferences:com.apple.preference.notifications")
    }
}

/// The app opens that URL with its own bundle identifier, and no other notifications URL is
/// left in the app. The app target has no tests, so this reads its source.
final class OwnNotificationSettingsWiringTests: XCTestCase {
    func testTheAppOpensItsOwnPageWithItsOwnBundleIdentifier() throws {
        let source = SourceCode.code(of: try XCTUnwrap(AppSources.read("OnboardingCoordinator.swift")))
        let opens = try XCTUnwrap(SourceCode.body(of: "static func openNotificationSettings() {", in: source))
        XCTAssertEqual(opens.trimmingCharacters(in: .whitespacesAndNewlines),
                       "NSWorkspace.shared.open(BundleResolver.ownNotificationSettingsURL(bundleID: Bundle.main.bundleIdentifier))")
        for file in try AppSources.fileNames() {
            XCTAssertFalse(try XCTUnwrap(AppSources.read(file)).contains("Notifications-Settings.extension"), file)
        }
    }
}
