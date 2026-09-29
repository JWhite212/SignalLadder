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
}
