import XCTest
@testable import NotificationCore

/// A layout change names the element it is about, and when that is a banner no
/// read has captured or set aside, the watcher reads at once rather than 50 ms
/// later (#154). Measured on macOS 27.2 on 2026-10-17, alerts from one app 0.05 s
/// apart each replaced the last in about 60 ms, and the layout change naming the
/// new one came 15 to 20 ms after it appeared, so a read 50 ms after that found
/// the next one, and half of a burst of 12 was never read. `isUnread` is what
/// decides, so that a banner already read, or a row already judged, costs no read.
final class UnreadBannerTests: XCTestCase {
    private func banner(_ id: String, _ title: String, subrole: String = "AXNotificationCenterAlertStack") -> FakeNode {
        FakeNode(subrole: subrole, description: "Script Editor, \(title), Body", id: id,
                 children: [FakeNode(value: title), FakeNode(value: "Body")])
    }

    private func window(_ banners: FakeNode...) -> FakeNode {
        FakeNode(subrole: "AXSystemDialog", children: [
            FakeNode(subrole: "AXHostingView", children: [FakeNode(children: [FakeNode(children: banners)])])
        ])
    }

    /// The panel as `BannerTrackerTests` builds it: focus, and the list's own
    /// menu button beside the list in its scroll area.
    private func panelWindow(_ id: String, _ items: FakeNode...) -> FakeNode {
        FakeNode(subrole: "AXSystemDialog", id: id, focused: true, children: [
            FakeNode(subrole: "AXHostingView", children: [FakeNode(children: [
                FakeNode(role: "AXScrollArea", children: [FakeNode(children: items), FakeNode(role: "AXMenuButton")])
            ])])
        ])
    }

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSinceReferenceDate: 2_000_000 + seconds) }

    func testABannerNoReadHasSeenIsUnread() {
        XCTAssertTrue(BannerTracker().isUnread(banner("a", "First")))
    }

    /// Every subrole a banner is located by counts, and nothing else does: the
    /// window, its wrappers and a banner's own text are named by layout changes
    /// too, and reading at once for each of them would read every burst many
    /// times over.
    func testOnlyAnElementWithABannerSubroleIsUnread() {
        let tracker = BannerTracker()
        for subrole in BannerSubrole.allowlist {
            XCTAssertTrue(tracker.isUnread(banner("b-\(subrole)", "Shown", subrole: subrole)), subrole)
        }
        XCTAssertFalse(tracker.isUnread(FakeNode(subrole: "AXSystemDialog", id: "window")))
        XCTAssertFalse(tracker.isUnread(FakeNode(role: "AXGroup", id: "wrapper")))
        XCTAssertFalse(tracker.isUnread(FakeNode(role: "AXStaticText", value: "Body", id: "text")))
        XCTAssertFalse(tracker.isUnread(FakeNode(id: "no-subrole")))
    }

    /// Layout changes fire again for a banner already read, 1.6 s and 2.2 s
    /// after it appeared in one run. Those cost no read at once.
    func testABannerOnceCapturedIsNotUnread() {
        let tracker = BannerTracker()
        XCTAssertEqual(tracker.scan(window(banner("a", "First"))).new.count, 1)
        XCTAssertFalse(tracker.isUnread(banner("a", "First")))
    }

    /// The case measured: each alert that joins the stack is a new element, so
    /// the one that replaces a captured alert is unread until a read takes it.
    func testTheElementThatReplacesACapturedOneIsUnread() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(banner("a", "First")))
        XCTAssertTrue(tracker.isUnread(banner("b", "Second")))
        XCTAssertEqual(tracker.scan(window(banner("b", "Second"))).new.map(\.textChildren), [["Second", "Body"]])
        XCTAssertFalse(tracker.isUnread(banner("b", "Second")))
    }

    /// A banner read before its text had loaded is not remembered, so the
    /// layout change that comes with its text reads it at once again.
    func testABannerReadWithNoTextIsStillUnread() {
        let tracker = BannerTracker()
        let empty = FakeNode(subrole: "AXNotificationCenterAlertStack", id: "a")
        XCTAssertEqual(tracker.scan(window(empty)).empty, ["AXNotificationCenterAlertStack"])
        XCTAssertTrue(tracker.isUnread(banner("a", "Loaded")))
    }

    /// Everything the panel holds when it opens is history. Its rows' layout
    /// changes, which come as it opens and as it scrolls, cost no read at once.
    func testARowThePanelOpenedWithIsNotUnread() {
        let tracker = BannerTracker()
        let row = banner("row", "Old")
        XCTAssertEqual(tracker.scan(panelWindow("w", row), at: at(0)).new, [])
        XCTAssertFalse(tracker.isUnread(row))
    }

    /// A row that arrived while the panel is open waits for a second read,
    /// which the watcher has already been told to make, so its layout changes
    /// do not read it at once as well.
    func testARowAwaitingItsSecondReadIsNotUnread() {
        let tracker = BannerTracker()
        _ = tracker.scan(panelWindow("w"), at: at(0))
        let arrival = banner("arrival", "Arrived while open")
        XCTAssertTrue(tracker.isUnread(arrival))
        XCTAssertTrue(tracker.scan(panelWindow("w", arrival), at: at(1)).needsSecondRead)
        XCTAssertFalse(tracker.isUnread(arrival))
    }

    /// A new process has new elements, and none read from the old one counts.
    func testAfterAResetABannerIsUnreadAgain() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(banner("a", "First")))
        tracker.reset()
        XCTAssertTrue(tracker.isUnread(banner("a", "First")))
    }

    /// Asking reads nothing but the element's subrole, and changes nothing: a
    /// banner asked about is still captured by the read that follows.
    func testAskingDoesNotCountAsARead() {
        let tracker = BannerTracker()
        let a = banner("a", "First")
        XCTAssertTrue(tracker.isUnread(a))
        XCTAssertTrue(tracker.isUnread(a))
        XCTAssertEqual(tracker.scan(window(a)).new.count, 1)
    }
}
