import XCTest
@testable import NotificationCore

/// What each self-test result does to what health is judged from (#98). These were
/// decisions of `AppDelegate` that nothing tested.
final class SelfTestLedgerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    func testANewLedgerKnowsNoResultAndWaitsTheFirstRetryDelay() {
        let ledger = SelfTestLedger()
        XCTAssertNil(ledger.consecutiveFailures, "no self-test has completed")
        XCTAssertFalse(ledger.failedWithNoBannerActivity)
        XCTAssertNil(ledger.lastSucceededAt)
        XCTAssertNil(ledger.secondsSinceLastSuccess(at: t0))
        XCTAssertEqual(ledger.retryDelay, SelfTestPlan.firstRetryDelay)
        XCTAssertEqual(ledger.capturesSinceLastRun(captureCount: 7), 7)
    }

    func testASuccessIsDatedClearsTheFailuresAndCancelsTheRetry() {
        var ledger = SelfTestLedger()
        let run = ledger.begin(captureCount: 3)
        XCTAssertEqual(ledger.finish(run, result: true, bannerActivity: true, at: t0), .cancel)
        XCTAssertEqual(ledger.consecutiveFailures, 0)
        XCTAssertEqual(ledger.lastSucceededAt, t0)
        XCTAssertEqual(ledger.secondsSinceLastSuccess(at: t0 + 90), 90)
        XCTAssertFalse(ledger.failedWithNoBannerActivity)
    }

    func testFailuresCountInARowAreRetriedAndASuccessEndsTheRun() {
        var ledger = SelfTestLedger()
        for expected in 1...3 {
            let run = ledger.begin(captureCount: 0)
            XCTAssertEqual(ledger.finish(run, result: false, bannerActivity: true, at: t0), .schedule)
            XCTAssertEqual(ledger.consecutiveFailures, expected)
        }
        XCTAssertNil(ledger.lastSucceededAt, "a failure is not a success")
        let run = ledger.begin(captureCount: 0)
        _ = ledger.finish(run, result: true, bannerActivity: true, at: t0)
        XCTAssertEqual(ledger.consecutiveFailures, 0)
    }

    /// With no banner drawn during the run, the alert was suppressed and the failure says
    /// nothing about capture; health is told so. A success never says it.
    func testAFailureWithNoBannerActivityIsMarkedAndOnlyAFailureIs() {
        var ledger = SelfTestLedger()
        var run = ledger.begin(captureCount: 0)
        _ = ledger.finish(run, result: false, bannerActivity: false, at: t0)
        XCTAssertTrue(ledger.failedWithNoBannerActivity)
        run = ledger.begin(captureCount: 0)
        _ = ledger.finish(run, result: false, bannerActivity: true, at: t0)
        XCTAssertFalse(ledger.failedWithNoBannerActivity)
        run = ledger.begin(captureCount: 0)
        _ = ledger.finish(run, result: false, bannerActivity: false, at: t0)
        run = ledger.begin(captureCount: 0)
        _ = ledger.finish(run, result: true, bannerActivity: false, at: t0)
        XCTAssertFalse(ledger.failedWithNoBannerActivity, "a success with nothing drawn is still a success")
    }

    /// The count is taken as the run is asked for, so captures during the round trip count
    /// as traffic since it.
    func testCapturesAreCountedFromWhenTheRunWasAskedFor() {
        var ledger = SelfTestLedger()
        let run = ledger.begin(captureCount: 10)
        XCTAssertEqual(ledger.capturesSinceLastRun(captureCount: 12), 2, "during the run")
        _ = ledger.finish(run, result: false, bannerActivity: true, at: t0)
        XCTAssertEqual(ledger.capturesSinceLastRun(captureCount: 15), 5)
    }

    /// A run that did not happen changes nothing a result would, puts the count back and
    /// asks for a retry.
    func testARunThatDidNotHappenPutsTheCountBackAndAsksForARetry() {
        var ledger = SelfTestLedger()
        let first = ledger.begin(captureCount: 4)
        _ = ledger.finish(first, result: true, bannerActivity: true, at: t0)
        let none = ledger.begin(captureCount: 9)
        XCTAssertEqual(ledger.finish(none, result: nil, bannerActivity: false, at: t0 + 60), .schedule)
        XCTAssertEqual(ledger.capturesSinceLastRun(captureCount: 9), 5, "counted from the run that happened")
        XCTAssertEqual(ledger.consecutiveFailures, 0)
        XCTAssertEqual(ledger.lastSucceededAt, t0)
    }

    /// A run asked for while another is under way gets no result of its own. It must leave
    /// the count the one under way set, and that one's result is then what counts.
    func testARunAskedForDuringAnotherLeavesThatOnesCount() {
        var ledger = SelfTestLedger()
        let underWay = ledger.begin(captureCount: 5)
        let overlapping = ledger.begin(captureCount: 7)
        _ = ledger.finish(overlapping, result: nil, bannerActivity: false, at: t0)
        XCTAssertEqual(ledger.captureCountAtLastRun, 5)
        _ = ledger.finish(underWay, result: true, bannerActivity: true, at: t0)
        XCTAssertEqual(ledger.capturesSinceLastRun(captureCount: 8), 3)
    }

    /// Each retry waits the delay then due and moves the back-off on, as `SelfTestPlan`
    /// says; a cancel starts it afresh.
    func testTheRetryBacksOffAsThePlanSaysAndACancelStartsItAfresh() {
        for onCall in [false, true] {
            var ledger = SelfTestLedger()
            var expected = SelfTestPlan.firstRetryDelay
            for _ in 0..<6 {
                XCTAssertEqual(ledger.takeRetryDelay(onCall: onCall), expected, "on call \(onCall)")
                expected = SelfTestPlan.nextRetryDelay(after: expected, onCall: onCall)
            }
            XCTAssertNotEqual(ledger.retryDelay, SelfTestPlan.firstRetryDelay, "it has backed off")
            ledger.retryCancelled()
            XCTAssertEqual(ledger.takeRetryDelay(onCall: onCall), SelfTestPlan.firstRetryDelay)
        }
    }
}
