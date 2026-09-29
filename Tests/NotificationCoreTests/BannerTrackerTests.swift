// Tests/NotificationCoreTests/BannerTrackerTests.swift
import XCTest
@testable import NotificationCore

final class BannerTrackerTests: XCTestCase {
    /// A banner as macOS 26.7 draws one: the app, title and body joined in the
    /// description, and the title and body again as text children.
    private func banner(_ id: String, _ title: String, _ body: String = "Body",
                        subrole: String = "AXNotificationCenterBanner") -> FakeNode {
        FakeNode(subrole: subrole, description: "App, \(title), \(body)", id: id,
                 children: [FakeNode(value: title), FakeNode(value: body)])
    }

    /// The window a banner is shown in, reduced to the wrappers seen live.
    private func window(_ banners: FakeNode...) -> FakeNode {
        FakeNode(subrole: "AXSystemDialog", children: [
            FakeNode(subrole: "AXHostingView", children: [FakeNode(children: [FakeNode(children: banners)])])
        ])
    }

    func testCapturesABannerTheFirstTimeItIsRead() {
        let scan = BannerTracker().scan(window(banner("a", "First")))
        XCTAssertEqual(scan.new, [.init(rawText: "App, First, Body", subrole: "AXNotificationCenterBanner",
                                         textChildren: ["First", "Body"])])
    }

    /// Layout changes fire again for a banner already on screen — 1.6 s and
    /// 2.2 s after it appeared in one live run. None of them is a new banner.
    func testIgnoresTheSameBannerReadAgain() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(banner("a", "First")))
        XCTAssertEqual(tracker.scan(window(banner("a", "First"))).new, [])
        XCTAssertEqual(tracker.scan(window(banner("a", "First"))).new, [])
    }

    /// The bug this type exists for: a second banner, arriving while the first
    /// is still on screen, takes its place in the same window. It is a new
    /// element, so it is captured.
    func testCapturesABannerThatReplacesAnotherInPlace() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(banner("a", "First")))
        let scan = tracker.scan(window(banner("b", "Second")))
        XCTAssertEqual(scan.new.map(\.textChildren), [["Second", "Body"]])
    }

    /// Two genuinely separate notifications can carry the same text. Judging
    /// whether that is a repeat is `CaptureDeduplicator`'s job, where it is
    /// counted; dropping it here would hide it.
    func testCapturesAReplacementEvenWhenItsTextMatches() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(banner("a", "Same")))
        XCTAssertEqual(tracker.scan(window(banner("b", "Same"))).new.count, 1)
    }

    func testCapturesABannerAgainWhenItsTextChangesInPlace() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(banner("a", "First")))
        XCTAssertEqual(tracker.scan(window(banner("a", "Edited"))).new.map(\.textChildren), [["Edited", "Body"]])
    }

    /// Every read of another process can time out, and a timed-out child or
    /// description is simply missing from that read. Less text is not new.
    func testIgnoresARereadThatLostAChild() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(banner("a", "First")))
        let degraded = FakeNode(subrole: "AXNotificationCenterBanner", description: "App, First, Body", id: "a",
                                children: [FakeNode(value: "First")])
        XCTAssertEqual(tracker.scan(window(degraded)).new, [])
    }

    func testIgnoresARereadThatLostItsDescription() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(banner("a", "First")))
        let degraded = FakeNode(subrole: "AXNotificationCenterBanner", id: "a",
                                children: [FakeNode(value: "First"), FakeNode(value: "Body")])
        XCTAssertEqual(tracker.scan(window(degraded)).new, [])
    }

    /// A poorer read must not replace what was remembered, or the full read
    /// after it would look new.
    func testAFullRereadAfterADegradedOneIsNotNew() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(banner("a", "First")))
        _ = tracker.scan(window(FakeNode(subrole: "AXNotificationCenterBanner", id: "a",
                                         children: [FakeNode(value: "First")])))
        XCTAssertEqual(tracker.scan(window(banner("a", "First"))).new, [])
    }

    /// A first read that was partial is captured again when a later read finds
    /// the rest: the fuller text may match a rule the partial one could not.
    func testCapturesAgainWhenALaterReadFindsMoreText() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(FakeNode(subrole: "AXNotificationCenterBanner", id: "a",
                                         children: [FakeNode(value: "First")])))
        XCTAssertEqual(tracker.scan(window(banner("a", "First"))).new.map(\.textChildren), [["First", "Body"]])
    }

    /// A banner caught before its text is filled in must still be captured
    /// when a later event finds the text.
    func testDoesNotRememberABannerReadWithNoText() {
        let tracker = BannerTracker()
        let blank = FakeNode(subrole: "AXNotificationCenterBanner", id: "a")
        let first = tracker.scan(window(blank))
        XCTAssertEqual(first.new, [])
        XCTAssertEqual(first.empty, ["AXNotificationCenterBanner"])
        XCTAssertEqual(tracker.scan(window(banner("a", "First"))).new.count, 1)
    }

    /// An event carries only part of the tree — the banner, or the scroll area
    /// around it. A banner outside that part is still on screen, so it must
    /// not be forgotten, or the next event that does include it captures it
    /// again.
    func testDoesNotForgetABannerMissingFromOneScan() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(banner("a", "First")))
        _ = tracker.scan(FakeNode(subrole: "AXScrollArea"))
        XCTAssertEqual(tracker.scan(window(banner("a", "First"))).new, [])
    }

    /// Only destruction frees an element. If macOS reuses its identity for a
    /// later banner, that banner is new.
    func testForgetsABannerOnceItIsGone() {
        let tracker = BannerTracker()
        let first = banner("a", "First")
        _ = tracker.scan(window(first))
        first.isGone = true
        XCTAssertEqual(tracker.scan(window(banner("a", "First"))).new.count, 1)
    }

    func testCapturesEachBannerInAStackOnce() {
        let tracker = BannerTracker()
        let stack = FakeNode(subrole: "AXNotificationCenterBannerStack", id: "stack",
                             children: [banner("a", "One"), banner("b", "Two")])
        XCTAssertEqual(tracker.scan(window(stack)).new.map(\.textChildren), [["One", "Body"], ["Two", "Body"]])
        XCTAssertEqual(tracker.scan(window(stack)).new, [])
    }

    /// Opening Notification Centre shows its history in the same list as a
    /// banner arriving while it is open. Only the arrival is captured.
    func testCapturesAnArrivalButNotTheHistoryAroundIt() {
        let history = FakeNode(subrole: "AXNotificationCenterBannerStack",
                               description: "App, Old, Body, stacked", id: "old",
                               children: [FakeNode(value: "Old"), FakeNode(value: "Body"), FakeNode(value: "1m ago")])
        let scan = BannerTracker().scan(window(banner("new", "New"), history))
        XCTAssertEqual(scan.new.map(\.textChildren), [["New", "Body"]])
        XCTAssertEqual(scan.empty, [])
    }

    func testForgetsTheOldestBannersBeyondItsCapacity() {
        let tracker = BannerTracker(capacity: 2)
        _ = tracker.scan(window(banner("a", "One")))
        _ = tracker.scan(window(banner("b", "Two")))
        _ = tracker.scan(window(banner("c", "Three")))
        XCTAssertEqual(tracker.scan(window(banner("c", "Three"))).new, [], "the newest is remembered")
        XCTAssertEqual(tracker.scan(window(banner("a", "One"))).new.count, 1, "the oldest was forgotten")
    }

    func testResetForgetsEverything() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(banner("a", "First")))
        tracker.reset()
        XCTAssertEqual(tracker.scan(window(banner("a", "First"))).new.count, 1)
    }
}
