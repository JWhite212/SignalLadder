import XCTest
@testable import NotificationCore

/// A wall clock set back must not stretch a bound. Five types treat a time after
/// now as now (`CaptureDeduplicator`, `HealthAlarmPlan.State.clamped`,
/// `OnCallState`, `Snooze`, `EscalationCoordinator.Stamp`); these hold the four
/// that did not: `BannerTracker`, `SelfTestLedger`, `UnreadBanners` and
/// `CaptureRingBuffer` (#199). Each test steps the clock back and reads again.
final class ClockSetBackTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSinceReferenceDate: 3_000_000 + seconds) }
    private let later = BannerTracker.secondReadGap + 0.05

    private func banner(_ id: String, _ title: String) -> FakeNode {
        FakeNode(subrole: "AXNotificationCenterBanner", description: "App, \(title), Body", id: id,
                 children: [FakeNode(value: title), FakeNode(value: "Body")])
    }

    private func window(_ banners: FakeNode...) -> FakeNode {
        FakeNode(subrole: "AXSystemDialog", children: [
            FakeNode(subrole: "AXHostingView", children: [FakeNode(children: [FakeNode(children: banners)])])
        ])
    }

    private func panelWindow(_ id: String, _ items: FakeNode...) -> FakeNode {
        FakeNode(subrole: "AXSystemDialog", id: id, focused: true, children: [
            FakeNode(subrole: "AXHostingView", children: [FakeNode(children: [
                FakeNode(role: "AXScrollArea", children: [FakeNode(children: items), FakeNode(role: "AXMenuButton")])
            ])])
        ])
    }

    // MARK: - BannerTracker

    func testARowAwaitingItsSecondReadIsDecidedAfterTheClockIsSetBack() {
        let tracker = BannerTracker()
        _ = tracker.scan(panelWindow("w"), at: at(0))
        let first = tracker.scan(panelWindow("w", banner("a", "Arrived")), at: at(100))
        XCTAssertTrue(first.needsSecondRead)
        // An hour back: the first read is now an hour in the future.
        let stepped = tracker.scan(panelWindow("w", banner("a", "Arrived")), at: at(100 - 3600))
        XCTAssertTrue(stepped.needsSecondRead, "the wait starts again at the new now")
        let decided = tracker.scan(panelWindow("w", banner("a", "Arrived")), at: at(100 - 3600 + later))
        XCTAssertEqual(decided.new.map(\.textChildren), [["Arrived", "Body"]])
        XCTAssertFalse(decided.needsSecondRead)
    }

    func testADestroyedBannersTextExpiresWhenTheClockIsSetBack() {
        let tracker = BannerTracker()
        let first = banner("first", "Build failed")
        _ = tracker.scan(panelWindow("w"), at: at(0))
        _ = tracker.scan(panelWindow("w", first), at: at(1))
        XCTAssertEqual(tracker.scan(panelWindow("w", first), at: at(1 + later)).new.count, 1)
        first.isGone = true
        _ = tracker.scan(panelWindow("w"), at: at(10))
        // A minute back, the destroyed time is in the future; a genuine repeat is not a re-layout.
        let repeated = banner("repeat", "Build failed")
        _ = tracker.scan(panelWindow("w", repeated), at: at(10 - 60))
        XCTAssertEqual(tracker.scan(panelWindow("w", repeated), at: at(10 - 60 + later)).new.count, 1)
    }

    func testAnEmptyBannerIsCountedUnreadAfterTheBoundWhenTheClockIsSetBack() {
        let tracker = BannerTracker()
        let blank = FakeNode(subrole: "AXNotificationCenterBanner", id: "blank")
        XCTAssertEqual(tracker.scan(window(blank), at: at(0)).unread, 0)
        XCTAssertEqual(tracker.scan(window(blank), at: at(-3600)).unread, 0)
        XCTAssertEqual(tracker.scan(window(blank), at: at(-3600 + BannerTracker.unreadBound + 1)).unread, 1)
    }

    // MARK: - SelfTestLedger

    func testASuccessDatedAfterNowIsStaleSoHealthIsNotVerified() throws {
        var ledger = SelfTestLedger()
        let run = ledger.begin(captureCount: 0)
        _ = ledger.finish(run, result: true, bannerActivity: true, at: t0)
        let age = try XCTUnwrap(ledger.secondsSinceLastSuccess(at: t0.addingTimeInterval(-7200)))
        XCTAssertGreaterThan(age, HealthEvaluator.selfTestInterval + HealthEvaluator.freshnessGrace)
        XCTAssertFalse(HealthTitle.ago(age).isEmpty, "a title can be written from it")
    }

    // MARK: - UnreadBanners

    func testAnUnreadTimeAfterNowCountsAsNow() {
        var unread = UnreadBanners()
        unread.record(1, at: t0)
        XCTAssertEqual(unread.count(at: t0.addingTimeInterval(-3600)), 1)
        XCTAssertEqual(unread.count(at: t0.addingTimeInterval(UnreadBanners.window - 1)), 1, "still the bound going forward")
        XCTAssertEqual(unread.count(at: t0.addingTimeInterval(UnreadBanners.window + 1)), 0)
    }

    // MARK: - CaptureRingBuffer

    func testTheHoursCountLeavesOutEntriesDatedAfterTheCapture() {
        func note(_ offset: TimeInterval) -> CapturedNotification {
            CapturedNotification(timestamp: t0.addingTimeInterval(offset), appNameGuess: "Teams", title: "t",
                                 subtitle: "", body: "b", rawText: "Teams, t, b", subrole: "AXNotificationCenterBanner")
        }
        let buffer = CaptureRingBuffer()
        buffer.record(note(0), suppressedRepeatCount: 0)
        buffer.record(note(5), suppressedRepeatCount: 0)
        // The clock is set back an hour: both earlier entries are after this capture.
        let entry = buffer.record(note(-3600), suppressedRepeatCount: 0)
        XCTAssertEqual(entry.context.recentCountForApp, 1)
        // Going forward the hour is as it was: the entry from 3600 s before is just outside it.
        XCTAssertEqual(buffer.record(note(10), suppressedRepeatCount: 0).context.recentCountForApp, 3)
    }
}
