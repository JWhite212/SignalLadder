// Tests/NotificationCoreTests/SelfTestPlanTests.swift
import XCTest
@testable import NotificationCore

final class SelfTestPlanTests: XCTestCase {
    private func conditions(trusted: Bool = true, displays: Bool = true, attached: Bool = true) -> SelfTestPlan.Conditions {
        .init(accessibilityTrusted: trusted, ownAlertsDisplay: displays, observerAttached: attached)
    }

    func testRunsARequestedSelfTestWhenNothingBlocksIt() {
        XCTAssertEqual(SelfTestPlan.decide(requested: true, previous: nil, current: conditions()), .run)
    }

    /// Launched with its own banners switched off: skipped, and — unlike
    /// before — tried again.
    func testRetriesARequestedSelfTestItsOwnBannersWouldNotShow() {
        XCTAssertEqual(SelfTestPlan.decide(requested: true, previous: nil, current: conditions(displays: false)),
                       .retryLater)
    }

    func testRetriesARequestedSelfTestWithoutAccessibility() {
        XCTAssertEqual(SelfTestPlan.decide(requested: true, previous: nil, current: conditions(trusted: false)),
                       .retryLater)
    }

    /// Attaching runs a self-test of its own.
    func testLeavesADetachedObserverToTheSelfTestAttachingRuns() {
        XCTAssertEqual(SelfTestPlan.decide(requested: true, previous: nil, current: conditions(attached: false)),
                       .nothing)
    }

    func testAHealthCheckForTheMenuRunsNoSelfTestByItself() {
        XCTAssertEqual(SelfTestPlan.decide(requested: false, previous: conditions(), current: conditions()), .nothing)
        XCTAssertEqual(SelfTestPlan.decide(requested: false, previous: nil, current: conditions()), .nothing)
    }

    /// Accessibility granted again: capture carried on, and must be re-proved
    /// rather than vouched for by a self-test from before the outage.
    func testRunsASelfTestWhenAccessibilityComesBack() {
        XCTAssertEqual(SelfTestPlan.decide(requested: false, previous: conditions(trusted: false),
                                           current: conditions()), .run)
    }

    func testRunsASelfTestWhenItsOwnBannersComeBack() {
        XCTAssertEqual(SelfTestPlan.decide(requested: false, previous: conditions(displays: false),
                                           current: conditions()), .run)
    }

    func testOneBlockerClearingWhileAnotherHoldsRetriesLater() {
        XCTAssertEqual(SelfTestPlan.decide(requested: false, previous: conditions(trusted: false, displays: false),
                                           current: conditions(trusted: false)), .retryLater)
    }

    /// Losing Accessibility is shown by the health model at once; it needs no
    /// self-test to find out.
    func testLosingAConditionRunsNothingUnasked() {
        XCTAssertEqual(SelfTestPlan.decide(requested: false, previous: conditions(),
                                           current: conditions(trusted: false)), .nothing)
    }

    // MARK: - The wait before a retry (M5 plan, Ruling 8)

    /// The delays a run of failures uses: the first, then each next one after the
    /// one before.
    private func delays(count: Int, onCall: Bool) -> [TimeInterval] {
        var delay = SelfTestPlan.firstRetryDelay
        var used: [TimeInterval] = []
        for _ in 0..<count {
            used.append(delay)
            delay = SelfTestPlan.nextRetryDelay(after: delay, onCall: onCall)
        }
        return used
    }

    func testTheFirstRetryIsAMinuteAway() {
        XCTAssertEqual(SelfTestPlan.firstRetryDelay, 60)
    }

    /// What the app has always done: the delay doubled and capped at the
    /// steady interval.
    func testOffCallTheDelaysAre60To1800AndStayAtHalfAnHour() {
        XCTAssertEqual(delays(count: 9, onCall: false), [60, 120, 240, 480, 960, 1800, 1800, 1800, 1800])
    }

    func testOnCallTheDelaysAre60To300AndStayAtFiveMinutes() {
        XCTAssertEqual(delays(count: 8, onCall: true), [60, 120, 240, 300, 300, 300, 300, 300])
    }

    /// Off call is the rule the app computed inline before this function
    /// replaced it, at every delay that rule could have been given.
    func testOffCallIsExactlyTheRuleTheAppUsedBefore() {
        for current in stride(from: 60.0, through: 4000.0, by: 7.0) {
            XCTAssertEqual(SelfTestPlan.nextRetryDelay(after: current, onCall: false),
                           min(current * 2, 30 * 60), "after \(current)")
        }
    }

    /// A delay under half a minute doubles to less than a minute, and a retry is
    /// not made sooner than the first one is. At 30 seconds or more, doubling
    /// reaches a minute by itself.
    func testNoDelayIsShorterThanTheFirst() {
        for current in [0.0, 1, 10, 29] {
            for onCall in [true, false] {
                XCTAssertEqual(SelfTestPlan.nextRetryDelay(after: current, onCall: onCall), 60,
                               "after \(current), onCall \(onCall)")
            }
        }
        for current in stride(from: 0.0, through: 200.0, by: 0.5) {
            for onCall in [true, false] {
                XCTAssertGreaterThanOrEqual(SelfTestPlan.nextRetryDelay(after: current, onCall: onCall), 60,
                                            "after \(current), onCall \(onCall)")
            }
        }
    }

    /// A delay that was used in the other state is brought under this one's
    /// cap by the next, so a retry is never later than the next scheduled
    /// self-test would be.
    func testNoDelayIsLongerThanTheIntervalOfTheStateItIsAskedIn() {
        for current in [300.0, 960, 1800, 3600, 100_000] {
            XCTAssertEqual(SelfTestPlan.nextRetryDelay(after: current, onCall: true), 300, "after \(current)")
            XCTAssertLessThanOrEqual(SelfTestPlan.nextRetryDelay(after: current, onCall: false), 1800)
        }
        XCTAssertEqual(SelfTestPlan.nextRetryDelay(after: 960, onCall: false), 1800)
        XCTAssertEqual(SelfTestPlan.nextRetryDelay(after: 960, onCall: true), 300)
    }

    /// The cap is the interval the evaluator is given, so the two cannot drift
    /// apart: no retry is later than the point where evidence goes stale.
    func testTheCapIsTheIntervalHealthAgesEvidenceBy() {
        for onCall in [true, false] {
            XCTAssertEqual(SelfTestPlan.nextRetryDelay(after: 1_000_000, onCall: onCall),
                           HealthEvaluator.selfTestInterval(onCall: onCall))
        }
    }
}
