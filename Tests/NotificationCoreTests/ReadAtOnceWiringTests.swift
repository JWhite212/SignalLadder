import XCTest
@testable import NotificationCore

/// How the watcher reads a banner that may not be on screen for long (#154). A
/// layout change names the element it is about; when that is a banner no read has
/// taken (`BannerTracker.isUnread`, held by `UnreadBannerTests`), the watcher reads
/// at once, and still reads 50 ms after the burst's first event, as before.
///
/// The watcher needs a live Notification Centre, so what it does with this is held
/// by reading its source, as `NotificationPermissionTests` does for the delivery
/// probe in the same target.
final class ReadAtOnceWiringTests: XCTestCase {
    private func watcherCode() throws -> String {
        try packageCode("Sources/NotificationCapture/AXBannerWatcher.swift")
    }

    /// The observer's callback hands on the element the notification is about,
    /// which is the only place the new banner is named.
    func testTheCallbackHandsOnTheElementTheNotificationNames() throws {
        let code = try watcherCode()
        XCTAssertTrue(code.contains("let callback: AXObserverCallback = { _, element, notification, refcon in"))
        XCTAssertTrue(code.contains("watcher.handle(notification: notification as String, element: element)"))
    }

    /// A layout change naming an unread banner reads the windows at once, before
    /// the coalesced scan is asked for, and nothing else reads at once: not a
    /// window event, which comes before the banner has its text, and not a
    /// destruction, whose element cannot be read.
    func testALayoutChangeNamingAnUnreadBannerIsReadAtOnceAndNothingElseIs() throws {
        let handle = try body(of: "private func handle(notification: String, element: AXUIElement) {", in: try watcherCode())
        let atOnce = "if notification == kAXLayoutChangedNotification, tracker.isUnread(AXElementNode(element)) {\nscanWindows()\n}"
        XCTAssertTrue(handle.contains(atOnce), "the read at once is not guarded by a layout change naming an unread banner")
        XCTAssertEqual(handle.components(separatedBy: "scanWindows()").count - 1, 1, "handle reads at once in one place")
        XCTAssertLessThan(try position(of: atOnce, in: handle),
                          try position(of: "scheduleScan(after: Self.scanDelay)", in: handle),
                          "the read at once comes before the coalesced scan is asked for")
    }

    /// The scan 50 ms after a burst's first event stays, coalesced as before: it
    /// reads whatever the read at once could not, such as a banner whose window
    /// was just created, and a banner whose text came after its layout change.
    func testTheCoalescedScanStillFollowsEveryEvent() throws {
        let code = try watcherCode()
        XCTAssertTrue(code.contains("private static let scanDelay: TimeInterval = 0.05"))
        let handle = try body(of: "private func handle(notification: String, element: AXUIElement) {", in: code)
        XCTAssertTrue(handle.hasSuffix("scheduleScan(after: Self.scanDelay)\n"), "every event still asks for the scan, last")
        let schedule = try body(of: "private func scheduleScan(after delay: TimeInterval) {", in: code)
        XCTAssertTrue(schedule.hasPrefix("\nguard !scanScheduled else { return }"), "the scan is still coalesced")
    }

    /// Layout changes are still left out of the count of observer events, which
    /// is the evidence that a notification was drawn, measured without them.
    func testLayoutChangesAreStillNotCountedAsObserverEvents() throws {
        let handle = try body(of: "private func handle(notification: String, element: AXUIElement) {", in: try watcherCode())
        XCTAssertTrue(handle.hasPrefix("\nif notification != kAXLayoutChangedNotification {\nobserverEventCount += 1\n}"))
    }
}
