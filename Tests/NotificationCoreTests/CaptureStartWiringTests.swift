import XCTest
@testable import NotificationCore

/// Where the app starts capture once Accessibility is granted. A grant is made in
/// System Settings, and nothing tells the app it was made: before, capture started
/// only at launch, when the menu opened and on the Setup Guide's Check again, so a
/// grant made from the menu's own advice line, with the menu then closed, left
/// capture off and every banner missed until the menu was opened again.
///
/// Now every health refresh starts it, if it can, before it reads the conditions:
/// the recheck made every minute while Accessibility is not granted
/// (`SelfTestPlan.decide`), the scheduled self-test and each retry. Activation still
/// only reads (`SetupWiringTests`), so a grant takes effect within the minute, or at
/// once when the menu opens or Check again is pressed.
/// `startCaptureIfTrusted()` does nothing when Accessibility is not granted or
/// capture is already running, and capture that starts asks for its own self-test
/// when it attaches. The app target has no tests, so this reads its source, as
/// `SetupWiringTests` does.
final class CaptureStartWiringTests: XCTestCase {
    private func app() throws -> String {
        SourceCode.code(of: try XCTUnwrap(AppSources.read("AppDelegate.swift"),
                                                    "AppDelegate.swift cannot be read at \(AppSources.directory.path)"))
    }

    func testEveryHealthRefreshStartsCaptureIfItCanBeforeItReadsTheConditions() throws {
        let refresh = try body(of: "private func refreshHealth(runCanary: Bool) async {", in: try app())
        XCTAssertTrue(trimmed(refresh).hasPrefix("delivery = await DeliveryStatusProbe.current()\nstartCaptureIfTrusted()\n"
                                                 + "let conditions = SelfTestPlan.Conditions("),
                      "the probe first, as ever, then capture, before the conditions are read")
    }

    /// The recheck made while a self-test is blocked, which is every minute while
    /// Accessibility is not granted, is a health refresh, and so starts capture.
    func testTheRecheckWhileBlockedIsAHealthRefresh() throws {
        let recheck = try body(of: "private func scheduleBlockedRecheck() {", in: try app())
        XCTAssertTrue(recheck.contains("await self?.refreshHealth(runCanary: true)"))
        XCTAssertTrue(recheck.contains("Self.blockedRecheckInterval"))
    }
}
