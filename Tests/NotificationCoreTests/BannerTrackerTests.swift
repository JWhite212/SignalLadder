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

    /// Reads at seconds from an arbitrary start, so a second read's spacing is
    /// explicit.
    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSinceReferenceDate: 1_000_000 + seconds) }
    private let later = BannerTracker.secondReadGap + 0.05

    /// The bug this fixes: an alert is heard, Notification Centre is opened to
    /// read it, and its row — under a minute old, so without a time label —
    /// looked exactly like an arrival.
    func testTheRowForAnAlertAlreadyHeardIsNeverCapturedAgain() {
        let tracker = BannerTracker()
        XCTAssertEqual(tracker.scan(window(banner("live", "Alert you just heard")), at: at(0)).new.count, 1)
        let row = FakeNode(subrole: "AXNotificationCenterBannerStack", description: "App, Alert you just heard, Body, stacked",
                           id: "row", children: [FakeNode(value: "Alert you just heard"), FakeNode(value: "Body")])
        XCTAssertEqual(tracker.scan(panelWindow("w", row), at: at(10)).new, [])
        XCTAssertEqual(tracker.scan(panelWindow("w", row), at: at(10 + later)).new, [])
    }

    /// Older rows carry a time label, which comes and goes between reads. Read
    /// with it, a row is history for good.
    func testALabelledRowIsHistoryEvenWhenItsLabelGoesMissing() {
        let tracker = BannerTracker()
        XCTAssertEqual(tracker.scan(panelWindow("w", historyItem("old", "Older", label: "19m ago")), at: at(0)).new, [])
        XCTAssertEqual(tracker.scan(panelWindow("w", historyItem("old", "Older", label: nil)), at: at(later)).new, [])
    }

    /// A row scrolled into view can be read between labels. It waits for a
    /// second read, which finds the label.
    func testARowCaughtBetweenLabelsWaitsAndIsThenHistory() {
        let tracker = BannerTracker()
        _ = tracker.scan(panelWindow("w"), at: at(-1))
        let first = tracker.scan(panelWindow("w", historyItem("old", "Older", label: nil)), at: at(0))
        XCTAssertEqual(first.new, [])
        XCTAssertTrue(first.needsSecondRead)
        XCTAssertEqual(tracker.scan(panelWindow("w", historyItem("old", "Older", label: nil)), at: at(0.1)).new, [],
                       "a second read too soon, inside the flicker, decides nothing")
        XCTAssertEqual(tracker.scan(panelWindow("w", historyItem("old", "Older", label: "19m ago")), at: at(later)).new, [])
        XCTAssertEqual(tracker.scan(panelWindow("w", historyItem("old", "Older", label: nil)), at: at(2 * later)).new, [])
    }

    /// A row appearing after the panel opened, with no evidence of being
    /// history, is captured once it has been read twice. The error this
    /// accepts is a replay, never a miss.
    func testARowWithNoEvidenceOfBeingHistoryIsCaptured() {
        let tracker = BannerTracker()
        _ = tracker.scan(panelWindow("w"), at: at(-1))
        XCTAssertEqual(tracker.scan(panelWindow("w", banner("alert", "Never seen")), at: at(0)).new, [])
        XCTAssertEqual(tracker.scan(panelWindow("w", banner("alert", "Never seen")), at: at(later)).new.map(\.textChildren),
                       [["Never seen", "Body"]])
        XCTAssertEqual(tracker.scan(panelWindow("w", banner("alert", "Never seen")), at: at(2 * later)).new, [])
    }

    /// Whatever the panel holds when it opens is history, including rows from
    /// before the app was running, whose text it never captured and which may
    /// show no label at all — and rows still loading their text.
    func testEverythingInThePanelWhenItOpensIsHistory() {
        let tracker = BannerTracker()
        let unknown = historyItem("before-launch", "From hours ago", label: nil)
        let loading = FakeNode(subrole: "AXNotificationCenterBanner", id: "loading")
        XCTAssertEqual(tracker.scan(panelWindow("w", unknown, loading), at: at(0)).new, [])
        XCTAssertEqual(tracker.scan(panelWindow("w", unknown, historyItem("loading", "Loaded late", label: nil)),
                                    at: at(later)).new, [])
        XCTAssertEqual(tracker.scan(panelWindow("w", unknown, historyItem("loading", "Loaded late", label: nil)),
                                    at: at(2 * later)).new, [])
    }

    func testAnArrivalWhileThePanelIsOpenIsCaptured() {
        let tracker = BannerTracker()
        let old = historyItem("old", "Earlier", label: "5m ago")
        _ = tracker.scan(panelWindow("w", old), at: at(0))
        _ = tracker.scan(panelWindow("w", banner("arrival", "Arrived while open"), old), at: at(1))
        let scan = tracker.scan(panelWindow("w", banner("arrival", "Arrived while open"), old), at: at(1 + later))
        XCTAssertEqual(scan.new.map(\.textChildren), [["Arrived while open", "Body"]])
    }

    /// A stack of alerts already heard, laid out again as separate elements
    /// while the panel is open (seen once, +3 for one arrival), is not heard
    /// again.
    func testAlertsLaidOutAgainAsNewElementsAreNotCapturedAgain() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(banner("q5", "Q5")), at: at(0))
        _ = tracker.scan(window(banner("q6", "Q6")), at: at(1))
        let regrouped = [banner("q5-again", "Q5"), banner("q6-again", "Q6")]
        XCTAssertEqual(tracker.scan(panelWindow("w", regrouped[0], regrouped[1]), at: at(5)).new, [])
        XCTAssertEqual(tracker.scan(panelWindow("w", regrouped[0], regrouped[1]), at: at(5 + later)).new, [])
    }

    /// Opening Notification Centre while a banner is on screen turns the
    /// banner's own window into the panel. The banner was captured when it
    /// arrived and is not captured again.
    func testTheBannerWindowBecomingThePanelCapturesNothingMore() {
        let tracker = BannerTracker()
        let live = banner("live", "On screen")
        let old = historyItem("old", "Earlier", label: "3m ago")
        XCTAssertEqual(tracker.scan(panelWindow("w", panel: false, live), at: at(0)).new.count, 1)
        XCTAssertEqual(tracker.scan(panelWindow("w", live, old), at: at(1)).new, [])
        XCTAssertEqual(tracker.scan(panelWindow("w", live, old), at: at(1 + later)).new, [])
    }

    /// Outside the panel nothing is set aside for looking like history. A
    /// calendar reminder that ends with its start time is a live alert.
    func testOutsideThePanelNothingIsSetAsideForLookingLikeHistory() {
        let tracker = BannerTracker()
        let reminder = FakeNode(subrole: "AXNotificationCenterAlert", description: "Outlook, Standup, 10:30 – 11:00",
                                id: "r", children: [FakeNode(value: "Standup"), FakeNode(value: "10:30")])
        XCTAssertEqual(tracker.scan(window(reminder), at: at(0)).new.count, 1)
    }

    /// A read of focus or of the menu button can time out, and then the open
    /// panel does not look like one. That must neither replay its history nor
    /// take the next arrival for history.
    func testOneReadThatMissesTheOpenPanelChangesNothing() {
        let tracker = BannerTracker()
        let old = historyItem("old", "Earlier", label: "2m ago")
        _ = tracker.scan(panelWindow("w", old), at: at(0))
        XCTAssertEqual(tracker.scan(panelWindow("w", panel: false, historyItem("old", "Earlier", label: nil)), at: at(1)).new, [])
        _ = tracker.scan(panelWindow("w", banner("arrival", "Arrived"), old), at: at(2))
        XCTAssertEqual(tracker.scan(panelWindow("w", banner("arrival", "Arrived"), old), at: at(2 + later)).new.count, 1)
    }

    /// An alert storm with the panel open: every arrival stays on screen, and
    /// none may be forgotten and captured again while it is.
    func testArrivalsStillOnScreenAreNeverCapturedTwice() {
        let tracker = BannerTracker(capacity: 4)
        var items: [FakeNode] = []
        var captured = 0
        _ = tracker.scan(panelWindow("w"), at: at(-1))
        func read(_ t: TimeInterval) -> Int {
            tracker.scan(FakeNode(subrole: "AXSystemDialog", id: "w", focused: true, children: [
                FakeNode(role: "AXScrollArea", children: [FakeNode(children: items), FakeNode(role: "AXMenuButton")])
            ]), at: at(t)).new.count
        }
        for i in 0..<10 {
            items.insert(banner("a\(i)", "Alert \(i)"), at: 0)
            captured += read(Double(i))
            captured += read(Double(i) + later)
        }
        for i in 0..<5 { captured += read(20 + Double(i)) }
        XCTAssertEqual(captured, 10)
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
