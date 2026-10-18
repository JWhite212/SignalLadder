import XCTest
@testable import NotificationCore

/// ⌃⌥⌘A acknowledges every escalation from any app. If it cannot be registered, as when
/// another app holds the same keys, only the log said so, and the user found out by pressing
/// it during an incident (workflow audit, 2026-10-16, finding 11). The On-Call Check now says
/// so. It is an advisory, not urgent: the panel and the menu still acknowledge, and nothing
/// about a page arriving has changed. So it is not watched, opens no window and sounds no beep,
/// and it has no button: no pane frees keys another app holds.
final class HotkeyFindingTests: XCTestCase {
    private func inputs(registered: Bool) -> OnCallCheck.Inputs {
        OnCallCheck.Inputs(health: .verified, unconfirmedMutedApps: [], outputSilent: false, alertVolume: 1,
                           reach: RuleReach(enabled: 1, alertingAloud: 1, withShortcut: 0),
                           ruleStatus: .loaded(enabled: 1, disabled: 0), ruleWarnings: [], startsAtLogin: nil,
                           loginItem: nil, acknowledgeHotkeyRegistered: registered)
    }

    func testAHotkeyThatCouldNotBeRegisteredIsAnAdvisoryInTheWindowAndTheMenu() throws {
        let found = try XCTUnwrap(OnCallCheck.findings(inputs(registered: false)).first { $0.kind == .hotkeyNotRegistered })
        XCTAssertEqual(found.text, "The acknowledge hotkey ⌃⌥⌘A could not be set up, so pressing it does nothing: "
                       + "acknowledge from the panel or the menu instead. Another app may be using the same keys.")
        XCTAssertEqual(found.menuText, "⌃⌥⌘A does nothing: acknowledge from the panel or the menu")
        XCTAssertFalse(found.isUrgent)
        XCTAssertNil(found.action)
        XCTAssertNil(found.destination)
        XCTAssertTrue(OnCallCheck.menuLines([found]).contains(found), "the menu's standard lines do not say it")
        XCTAssertFalse(OnCallWatch.isWatched(.hotkeyNotRegistered))
    }

    func testARegisteredHotkeyIsNoFinding() {
        XCTAssertFalse(OnCallCheck.findings(inputs(registered: true)).contains { $0.kind == .hotkeyNotRegistered })
    }
}

/// The hotkey controller records whether ⌃⌥⌘A was registered, and only a registration that
/// succeeded counts; the app hands that to the check. The app target has no tests, so this
/// reads its sources.
final class HotkeyFindingWiringTests: XCTestCase {
    func testOnlyARegistrationThatSucceededCounts() throws {
        let controller = try code("HotKeyController.swift")
        XCTAssertEqual(count("private(set) var isRegistered = false", in: controller), 1)
        XCTAssertEqual(count("isRegistered = ", in: controller), 2, "declared false, and set in one place")
        XCTAssertEqual(count("isRegistered = status == noErr", in: controller), 1)
    }
}
