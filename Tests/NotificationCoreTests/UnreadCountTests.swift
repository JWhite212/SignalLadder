import XCTest
@testable import NotificationCore

/// A banner located under an allowlisted subrole that never had readable text is
/// counted unread once: when it goes, when it has stayed empty for `unreadBound`, or
/// when it is pushed out past the capacity (1.1 plan, Ruling 17). An empty first read
/// that fills in is never counted, and an attach forgets what it held.
final class UnreadCountTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func empty(_ id: String) -> FakeNode {
        FakeNode(subrole: "AXNotificationCenterBanner", id: id)
    }

    private func banner(_ id: String, _ title: String) -> FakeNode {
        FakeNode(subrole: "AXNotificationCenterBanner", description: "App, \(title), Body", id: id,
                 children: [FakeNode(value: title), FakeNode(value: "Body")])
    }

    private func window(_ banners: FakeNode...) -> FakeNode {
        FakeNode(subrole: "AXSystemDialog", children: [
            FakeNode(subrole: "AXHostingView", children: [FakeNode(children: [FakeNode(children: banners)])])
        ])
    }

    func testAnEmptyBannerThatGoesWithoutTextIsCountedUnreadOnce() {
        let tracker = BannerTracker()
        let blank = empty("a")
        XCTAssertEqual(tracker.scan(window(blank), at: at(0)).unread, 0)
        blank.isGone = true
        XCTAssertEqual(tracker.scan(window(), at: at(2)).unread, 1)
        XCTAssertEqual(tracker.scan(window(), at: at(3)).unread, 0, "once")
    }

    func testAnEmptyFirstReadThatFillsInIsNeverCounted() {
        let tracker = BannerTracker()
        let blank = empty("a")
        XCTAssertEqual(tracker.scan(window(blank), at: at(0)).unread, 0)
        let filled = banner("a", "Prod is down")
        let second = tracker.scan(window(filled), at: at(0.5))
        XCTAssertEqual(second.new.count, 1, "captured")
        XCTAssertEqual(second.unread, 0)
        blank.isGone = true
        filled.isGone = true
        XCTAssertEqual(tracker.scan(window(), at: at(5)).unread, 0)
    }

    func testAnElementStillEmptyAfterTheBoundIsCountedOnceWhileItStays() {
        let tracker = BannerTracker()
        let blank = empty("a")
        XCTAssertEqual(tracker.scan(window(blank), at: at(0)).unread, 0)
        XCTAssertEqual(tracker.scan(window(blank), at: at(BannerTracker.unreadBound + 1)).unread, 1)
        XCTAssertEqual(tracker.scan(window(blank), at: at(40)).unread, 0)
        XCTAssertEqual(tracker.scan(window(blank), at: at(90)).unread, 0, "still once, while it stays")
        blank.isGone = true
        XCTAssertEqual(tracker.scan(window(), at: at(95)).unread, 0, "and not again when it goes")
    }

    func testAnAttachForgetsEmptyElementsWithoutCountingThem() {
        let tracker = BannerTracker()
        let blank = empty("a")
        _ = tracker.scan(window(blank), at: at(0))
        tracker.reset()
        blank.isGone = true
        XCTAssertEqual(tracker.scan(window(), at: at(2)).unread, 0)
    }

    func testEmptyElementsPastTheCapacityAreCountedOldestFirst() {
        let tracker = BannerTracker()
        let blanks = (0..<17).map { empty("e\($0)") }
        let first = tracker.scan(window(blanks[0]), at: at(0))
        XCTAssertEqual(first.unread, 0)
        var counted = 0
        for (index, blank) in blanks.enumerated().dropFirst() {
            counted += tracker.scan(window(blank), at: at(Double(index) * 0.1)).unread
        }
        XCTAssertEqual(counted, 1, "the 17th pushes the oldest out, counted")
        // The oldest has been let go: its going is not counted again.
        blanks[0].isGone = true
        XCTAssertEqual(tracker.scan(window(), at: at(3)).unread, 0)
    }

    /// The rows of an open Notification Centre list load their text late and can
    /// scroll away first, so an empty row of one is not held and never counted.
    func testAnEmptyRowOfTheOpenListIsNotCounted() {
        let tracker = BannerTracker()
        func panel(_ items: FakeNode...) -> FakeNode {
            FakeNode(subrole: "AXSystemDialog", id: "panel", focused: true, children: [
                FakeNode(subrole: "AXHostingView", children: [FakeNode(children: [
                    FakeNode(role: "AXScrollArea", children: [FakeNode(children: items), FakeNode(role: "AXMenuButton")])
                ])])
            ])
        }
        _ = tracker.scan(panel(), at: at(0))
        let row = empty("row")
        XCTAssertEqual(tracker.scan(panel(row), at: at(1)).unread, 0)
        row.isGone = true
        XCTAssertEqual(tracker.scan(panel(), at: at(2)).unread, 0)
        XCTAssertEqual(tracker.scan(panel(), at: at(40)).unread, 0)
    }

    /// The tracker's memory of banners is unchanged: an empty read is still not
    /// remembered, so its text, when it comes, is captured.
    func testAnEmptyReadIsStillNotRememberedAsCaptured() {
        let tracker = BannerTracker()
        _ = tracker.scan(window(empty("a")), at: at(0))
        XCTAssertTrue(tracker.isUnread(empty("a")))
        XCTAssertEqual(tracker.scan(window(banner("a", "First")), at: at(0.3)).new.count, 1)
    }
}

final class UnreadBannersTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_790_000_000)

    func testACountReachesBackHalfAnHour() {
        var unread = UnreadBanners()
        unread.record(2, at: t)
        XCTAssertEqual(unread.count(at: t), 2)
        XCTAssertEqual(unread.count(at: t.addingTimeInterval(29 * 60)), 2)
        XCTAssertEqual(unread.count(at: t.addingTimeInterval(31 * 60)), 0)
        unread.record(0, at: t)
        XCTAssertEqual(unread.count(at: t), 2, "a count of nothing records nothing")
    }

    func testItKeepsAtMostSixtyFourTimes() {
        var unread = UnreadBanners()
        for second in 0..<100 { unread.record(1, at: t.addingTimeInterval(TimeInterval(second))) }
        XCTAssertEqual(unread.count(at: t.addingTimeInterval(100)), UnreadBanners.capacity)
        XCTAssertEqual(UnreadBanners.capacity, 64)
    }
}

final class UnreadHealthTests: XCTestCase {
    private func inputs(failures: Int? = 0, authorized: Bool = true, trusted: Bool = true,
                        unread: Int) -> HealthInputs {
        HealthInputs(accessibilityTrusted: trusted, observerAttached: true, notificationsAuthorized: authorized,
                     notificationsWouldDisplay: true, consecutiveCanaryFailures: failures,
                     canaryFailedWithNoBannerActivity: false, capturesSinceLastCanary: 0,
                     unreadBannersRecently: unread, secondsSinceLastSuccessfulCanary: 0,
                     selfTestInterval: HealthEvaluator.selfTestInterval)
    }

    func testAPassingSelfTestWithAnUnreadBannerIsDegraded() {
        XCTAssertEqual(HealthEvaluator.unreadBannersThreshold, 1)
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(unread: 1)), .degraded([.bannersUnreadable]))
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(unread: 0)), .verified)
    }

    func testABlindOrDeliveryFaultIsReportedBeforeUnreadBanners() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(trusted: false, unread: 3)), .blind([.accessibilityNotTrusted]))
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(authorized: false, unread: 3)),
                       .degraded([.notificationPermissionDenied]))
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(failures: 1, unread: 3)), .degraded([.selfTestInconclusive]))
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(failures: 2, unread: 3)), .blind([.lazyAccessibilityTree]))
    }

    /// Not Accessibility's fault, and nothing in System Settings fixes it, so its
    /// advice opens nothing.
    func testUnreadBannersOpenNoPaneAndSayWhatToDo() {
        XCTAssertNil(HealthCause.bannersUnreadable.pane)
        XCTAssertEqual(HealthCause.bannersUnreadable.advice,
                       "Some notification banners in the last half hour could not be read, so no rule could match them. Look in Notification Centre for anything you missed. If it keeps happening, quit and reopen SignalLadder.")
    }

    func testUnreadBannersReadAsCouldNotReadSomeBanners() {
        XCTAssertEqual(HealthTitle.text(for: .degraded([.bannersUnreadable]), secondsSinceLastSuccessfulCanary: 60),
                       "Could not read some banners")
        XCTAssertEqual(HealthTitle.someBannersUnreadLine, "Could not read some banners")
        for cause in [HealthCause.selfTestInconclusive, .notificationsSuppressed, .ownAlertsNotShown] {
            XCTAssertEqual(HealthTitle.text(for: .degraded([cause]), secondsSinceLastSuccessfulCanary: 60),
                           "Cannot verify itself", "\(cause)")
        }
    }

    func testUnreadBannersAlarmLikeAnyDegradedHealth() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let health = CaptureHealth.degraded([.bannersUnreadable])
        XCTAssertTrue(health.isAlarming)
        XCTAssertEqual(HealthAlarmPlan.banner(for: health)?.body, HealthCause.bannersUnreadable.advice)
        for onCall in [true, false] {
            let first = HealthAlarmPlan.decide(health: health, deliveryHealthy: true, onCall: onCall, now: now,
                                               state: HealthAlarmPlan.State())
            XCTAssertTrue(first.beep, "onCall \(onCall): it sounds when it begins")
            let later = now.addingTimeInterval(HealthAlarmPlan.repeatInterval(afterBeeps: 1))
            let again = HealthAlarmPlan.decide(health: health, deliveryHealthy: true, onCall: onCall, now: later,
                                               state: first.state)
            XCTAssertEqual(again.beep, onCall, "on call it repeats; off call it sounds once")
        }
    }
}

/// The count reaches health from the watcher through the controller and the pipeline,
/// and the app works health out again at once. These read the sources and show the
/// lines are there, not that they run.
final class UnreadWiringTests: XCTestCase {
    private func app(_ file: String) throws -> String {
        SourceCode.code(of: try XCTUnwrap(AppSources.read(file)))
    }

    func testHealthIsGivenTheUnreadCountAndWorkedOutAgainWhenOneComes() throws {
        let delegate = try app("AppDelegate.swift")
        XCTAssertEqual(count("unreadBannersRecently: capture.pipeline.unreadBanners.count(at: Date()),", in: delegate), 1)
        XCTAssertEqual(count("capture.onUnreadBanners = { [weak self] in", in: delegate), 1)
        let hook = try XCTUnwrap(delegate.components(separatedBy: "capture.onUnreadBanners = { [weak self] in").last)
        XCTAssertTrue(hook.hasPrefix("\nTask { @MainActor in await self?.refreshHealth(runCanary: false) }"),
                      "health is worked out again, with no self-test")
    }

    func testTheControllerRecordsTheCountWithItsTimeAndSaysSo() throws {
        let capture = try app("CaptureController.swift")
        XCTAssertEqual(count("}, onUnread: { [weak self] count in", in: capture), 1)
        XCTAssertEqual(count("self.pipeline.recordUnreadBanners(count, at: Date())", in: capture), 1)
        XCTAssertEqual(count("self.onUnreadBanners?()", in: capture), 1)
    }

    func testTheWatcherHandsOnTheCountAndNothingElseOnlyWhenThereIsOne() throws {
        let watcher = try packageCode("Sources/NotificationCapture/AXBannerWatcher.swift")
        XCTAssertEqual(count("if scan.unread > 0 { onUnread(scan.unread) }", in: watcher), 1)
        XCTAssertEqual(count("onUnread(", in: watcher), 1, "called in one place")
        XCTAssertEqual(count("onUnread: @escaping (Int) -> Void = { _ in }", in: watcher), 1,
                       "a number only, and the probe keeps the default")
    }
}
