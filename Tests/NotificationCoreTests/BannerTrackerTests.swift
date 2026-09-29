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

    /// A persistent alert arriving while another from the same app is up
    /// joins it in a stack that shows the newest. The stack is the same
    /// element with new text, or a new element: either way, an arrival.
    func testCapturesEachAlertJoiningAPersistentStack() {
        let tracker = BannerTracker()
        func stack(_ id: String, _ title: String) -> FakeNode {
            FakeNode(subrole: "AXNotificationCenterAlertStack", description: "Teams, \(title), Body, stacked", id: id,
                     children: [FakeNode(value: title), FakeNode(value: "Body")])
        }
        XCTAssertEqual(tracker.scan(window(banner("first", "First", subrole: "AXNotificationCenterAlert"))).new.count, 1)
        XCTAssertEqual(tracker.scan(window(stack("s", "Second"))).new.map(\.textChildren), [["Second", "Body"]])
        XCTAssertEqual(tracker.scan(window(stack("s", "Third"))).new.map(\.textChildren), [["Third", "Body"]])
        XCTAssertEqual(tracker.scan(window(stack("s", "Third"))).new, [])
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

    // MARK: - Notification Centre's history panel

    /// The window as measured: the list inside a scroll area, and — only while
    /// it is showing the panel — focus and the panel's own menu button.
    private func panelWindow(_ id: String, panel: Bool = true, _ items: FakeNode...) -> FakeNode {
        var inScrollArea: [FakeNode] = [FakeNode(children: items)]
        if panel { inScrollArea.append(FakeNode(role: "AXMenuButton")) }
        return FakeNode(subrole: "AXSystemDialog", id: id, focused: panel, children: [
            FakeNode(subrole: "AXHostingView", children: [FakeNode(children: [FakeNode(role: "AXScrollArea", children: inScrollArea)])])
        ])
    }

    private func historyItem(_ id: String, _ title: String, label: String?) -> FakeNode {
        var children = [FakeNode(value: title), FakeNode(value: "Body")]
        if let label { children.append(FakeNode(value: label)) }
        return FakeNode(subrole: "AXNotificationCenterBanner", description: "App, \(title), Body", id: id, children: children)
    }

    /// The bug this fixes: history under a minute old has no time label and
    /// looks exactly like a banner that has just arrived.
    func testTheHistoryInAWindowThatBecomesThePanelIsNeverCaptured() {
        let tracker = BannerTracker()
        let fresh = historyItem("fresh", "Alert you just heard", label: nil)
        let old = historyItem("old", "Older", label: "19m ago")
        let loading = FakeNode(subrole: "AXNotificationCenterBanner", id: "loading")
        XCTAssertEqual(tracker.scan(panelWindow("w", fresh, old, loading)).new, [])
        XCTAssertEqual(tracker.scan(panelWindow("w", fresh, old, loading)).new, [])
        XCTAssertEqual(tracker.scan(panelWindow("w", fresh, historyItem("old", "Older", label: nil),
                                                historyItem("loading", "Now loaded", label: nil))).new, [],
                       "a label that goes missing, or text that loads late, does not make history new")
    }

    func testAnArrivalWhileThePanelIsOpenIsCaptured() {
        let tracker = BannerTracker()
        let fresh = historyItem("fresh", "Earlier", label: nil)
        _ = tracker.scan(panelWindow("w", fresh))
        let scan = tracker.scan(panelWindow("w", banner("arrival", "Arrived while open"), fresh))
        XCTAssertEqual(scan.new.map(\.textChildren), [["Arrived while open", "Body"]])
    }

    /// A row that appears later with a time label is history scrolled into
    /// view, and stays history if its label goes missing on a later read.
    func testALabelledRowAppearingLaterInThePanelIsHistory() {
        let tracker = BannerTracker()
        _ = tracker.scan(panelWindow("w", historyItem("a", "Top", label: nil)))
        XCTAssertEqual(tracker.scan(panelWindow("w", historyItem("a", "Top", label: nil),
                                                historyItem("b", "Further down", label: "2h ago"))).new, [])
        XCTAssertEqual(tracker.scan(panelWindow("w", historyItem("a", "Top", label: nil),
                                                historyItem("b", "Further down", label: nil))).new, [])
    }

    /// Opening Notification Centre while a banner is on screen turns the
    /// banner's own window into the panel. The banner was captured when it
    /// arrived and is not captured again; the history around it never is.
    func testTheBannerWindowBecomingThePanelCapturesNothingMore() {
        let tracker = BannerTracker()
        let live = banner("live", "On screen")
        XCTAssertEqual(tracker.scan(panelWindow("w", panel: false, live)).new.count, 1)
        XCTAssertEqual(tracker.scan(panelWindow("w", live, historyItem("fresh", "Earlier", label: nil))).new, [])
        XCTAssertEqual(tracker.scan(panelWindow("w", banner("next", "Then this"), live,
                                                historyItem("fresh", "Earlier", label: nil))).new.count, 1)
    }

    /// Closed and opened again, the panel's history is history again.
    func testReopeningThePanelTakesItsContentsAsHistoryAgain() {
        let tracker = BannerTracker()
        _ = tracker.scan(panelWindow("w", historyItem("a", "One", label: nil)))
        _ = tracker.scan(panelWindow("w", panel: false))
        _ = tracker.scan(panelWindow("w", panel: false))
        XCTAssertEqual(tracker.scan(panelWindow("w", historyItem("a", "One", label: nil),
                                                historyItem("b", "Two", label: nil))).new, [])
    }

    /// A read of focus or of the menu button can time out, and then the open
    /// panel does not look like one. That must neither replay its history nor
    /// take the next arrival for history.
    func testOneReadThatMissesTheOpenPanelChangesNothing() {
        let tracker = BannerTracker()
        let fresh = historyItem("fresh", "Earlier", label: nil)
        _ = tracker.scan(panelWindow("w", fresh))
        XCTAssertEqual(tracker.scan(panelWindow("w", panel: false, fresh)).new, [])
        XCTAssertEqual(tracker.scan(panelWindow("w", banner("arrival", "Arrived"), fresh)).new.count, 1)
    }

    /// An alert storm with the panel open: every arrival stays on screen, and
    /// none may be forgotten and captured again while it is.
    func testArrivalsStillOnScreenAreNeverCapturedTwice() {
        let tracker = BannerTracker(capacity: 4)
        _ = tracker.scan(panelWindow("w"))
        var items: [FakeNode] = []
        var captured = 0
        for i in 0..<10 {
            items.insert(banner("a\(i)", "Alert \(i)"), at: 0)
            captured += tracker.scan(FakeNode(subrole: "AXSystemDialog", id: "w", focused: true, children: [
                FakeNode(role: "AXScrollArea", children: [FakeNode(children: items), FakeNode(role: "AXMenuButton")])
            ])).new.count
        }
        XCTAssertEqual(captured, 10)
    }

    /// Outside a window known to be the panel, the time label is the only
    /// evidence of history — and once seen, it is remembered.
    func testALabelledItemOutsideThePanelStaysHistoryWhenItsLabelGoesMissing() {
        let tracker = BannerTracker()
        XCTAssertEqual(tracker.scan(window(historyItem("a", "Old", label: "5m ago"))).new, [])
        XCTAssertEqual(tracker.scan(window(historyItem("a", "Old", label: nil))).new, [])
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
