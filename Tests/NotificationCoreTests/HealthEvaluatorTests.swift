import XCTest
@testable import NotificationCore

final class HealthEvaluatorTests: XCTestCase {
    private func inputs(trusted: Bool = true,
                        attached: Bool = true,
                        authorized: Bool = true,
                        wouldDisplay: Bool = true,
                        failures: Int? = 0,
                        noBannerActivity: Bool = false) -> HealthInputs {
        HealthInputs(accessibilityTrusted: trusted,
                     observerAttached: attached,
                     notificationsAuthorized: authorized,
                     notificationsWouldDisplay: wouldDisplay,
                     consecutiveCanaryFailures: failures,
                     canaryFailedWithNoBannerActivity: noBannerActivity)
    }

    func testEverythingHealthyAndCanaryPassedIsVerified() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs()), .verified)
    }

    // MARK: - Suppressed vs missed
    //
    // These encode a real failure. Do Not Disturb routed the self-test straight
    // to history without drawing a banner; `alertStyle` still read "Banner", so
    // wouldDisplay was true, and the app reported an inconclusive self-test and
    // offered to open Accessibility settings. Nothing about capture was wrong.

    func testAFailedSelfTestThatSawNothingIsReportedAsAmbiguousNotAsSuppression() {
        // This asserted `.notificationsSuppressed` until a live run disproved
        // it: Do Not Disturb was OFF, banners were demonstrably being drawn,
        // no accessibility events arrived, and the app told the user its
        // notifications were being muted. It was blind. "No event" is evidence
        // for two opposite causes and the app cannot tell which.
        let health = HealthEvaluator.evaluate(inputs(failures: 1, noBannerActivity: true))
        XCTAssertEqual(health, .degraded([.selfTestAlertNeverSeen]))
    }

    func testTheAmbiguousCauseNamesBothPossibilities() {
        let advice = HealthCause.selfTestAlertNeverSeen.advice
        XCTAssertTrue(advice.contains("Do Not Disturb"), advice)
        XCTAssertTrue(advice.contains("not seeing banners"), advice)
        XCTAssertTrue(advice.contains("Full Keyboard Access"), advice)
    }

    func testRepeatedFailuresThatDrewNoBannerNeverEscalateToBlind() {
        // The important half. Left alone overnight under Do Not Disturb, the
        // old ladder would reach "NOT capturing notifications" and start
        // alarming about an Accessibility fault that does not exist.
        for failures in [2, 5, 40] {
            let health = HealthEvaluator.evaluate(inputs(failures: failures, noBannerActivity: true))
            XCTAssertEqual(health, .degraded([.selfTestAlertNeverSeen]),
                           "\(failures) unseen self-tests must not harden into a diagnosis")
        }
    }

    func testAFailedSelfTestThatDidDrawABannerStillEscalatesNormally() {
        // The complement: a banner WAS drawn and we missed it. That is a real
        // capture fault and must still climb the ladder.
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(failures: 1)),
                       .degraded([.selfTestInconclusive]))
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(failures: 2)),
                       .blind([.lazyAccessibilityTree]))
    }

    func testNoBannerActivityIsIgnoredWhenTheLastSelfTestSucceeded() {
        // The flag is stale state from an earlier failure; a success clears the
        // verdict regardless of what it says.
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(failures: 0, noBannerActivity: true)),
                       .verified)
    }

    func testNoBannerActivityCannotManufactureAVerdictBeforeAnySelfTestRan() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(failures: nil, noBannerActivity: true)),
                       .unknown)
    }

    func testARealCaptureFaultStillOutranksSuppression() {
        // Suppression must never mask a definite capture fault.
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(trusted: false, failures: 3, noBannerActivity: true)),
                       .blind([.accessibilityNotTrusted]))
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(attached: false, failures: 3, noBannerActivity: true)),
                       .blind([.observerNotAttached]))
    }

    func testAnInconclusiveSelfTestDoesNotSendTheUserToAccessibility() {
        // The click target follows isDeliveryFault. Offering Accessibility for
        // a fault we cannot attribute accuses the half that is probably fine.
        XCTAssertTrue(HealthCause.selfTestInconclusive.isDeliveryFault)
        XCTAssertTrue(HealthCause.notificationsSuppressed.isDeliveryFault)
        XCTAssertFalse(HealthCause.lazyAccessibilityTree.isDeliveryFault)
    }

    func testNoCanaryYetIsUnknownNotVerified() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(failures: nil)), .unknown)
    }

    func testUntrustedIsBlindRegardlessOfEverythingElse() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(trusted: false)),
                       .blind([.accessibilityNotTrusted]))
    }

    func testDetachedObserverIsBlind() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(attached: false)),
                       .blind([.observerNotAttached]))
    }

    /// The central rule: a failed canary with notifications suppressed must
    /// NOT be reported as a capture fault. The banner never appeared, so
    /// capture was never tested.
    func testSuppressedNotificationsDegradeRatherThanBlind() {
        let health = HealthEvaluator.evaluate(inputs(wouldDisplay: false, failures: 2))
        XCTAssertEqual(health, .degraded([.notificationsSuppressed]))
    }

    func testDeniedNotificationPermissionDegradesRatherThanBlinds() {
        let health = HealthEvaluator.evaluate(inputs(authorized: false, failures: 2))
        XCTAssertEqual(health, .degraded([.notificationPermissionDenied]))
    }

    func testBothDeliveryFaultsAreReportedTogether() {
        let health = HealthEvaluator.evaluate(inputs(authorized: false, wouldDisplay: false, failures: 2))
        XCTAssertEqual(health, .degraded([.notificationPermissionDenied, .notificationsSuppressed]))
    }

    /// Delivery confirmed working, capture configured, and the round trip
    /// still failed — this is the macOS 15.4 lazy-tree signature.
    func testFailedCanaryWithHealthyDeliveryIsBlindOnTheLazyTree() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(failures: 2)),
                       .blind([.lazyAccessibilityTree]))
    }

    /// A Focus suppressing our own notification produces exactly this: one
    /// failed self-test on a completely healthy app. Declaring blindness here
    /// would mean a recurring false alarm every night.
    func testSingleFailedSelfTestDegradesRatherThanBlinds() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(failures: 1)),
                       .degraded([.selfTestInconclusive]))
    }

    func testTwoConsecutiveFailuresAreEvidenceOfBlindness() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(failures: 2)),
                       .blind([.lazyAccessibilityTree]))
    }

    func testCaptureFaultsOutrankDeliveryFaults() {
        // Untrusted AND suppressed: the capture fault is the actionable one.
        let health = HealthEvaluator.evaluate(inputs(trusted: false, wouldDisplay: false, failures: 2))
        XCTAssertEqual(health, .blind([.accessibilityNotTrusted]))
    }

    func testDeliveryAndCaptureFaultsAreCorrectlyClassified() {
        XCTAssertTrue(HealthCause.notificationPermissionDenied.isDeliveryFault)
        XCTAssertTrue(HealthCause.notificationsSuppressed.isDeliveryFault)
        XCTAssertFalse(HealthCause.accessibilityNotTrusted.isDeliveryFault)
        XCTAssertFalse(HealthCause.observerNotAttached.isDeliveryFault)
        XCTAssertFalse(HealthCause.lazyAccessibilityTree.isDeliveryFault)

        // This assertion used to read `XCTAssertFalse`, on the reasoning that
        // an inconclusive self-test is an absence of evidence rather than a
        // delivery fault. That reasoning was right about the cause and wrong
        // about the consequence: the flag decides which settings pane is
        // offered, and `false` offers Accessibility. A live run had Do Not
        // Disturb suppress the self-test, and the app invited the user to
        // re-grant Accessibility to fix it — the exact misdirection the
        // delivery/capture split exists to prevent.
        //
        // We still cannot attribute the fault. But when we cannot, the honest
        // move is to stop pointing at the half that is probably innocent.
        XCTAssertTrue(HealthCause.selfTestInconclusive.isDeliveryFault,
                      "An unattributable self-test failure must not send the user to Accessibility")
    }

    func testOnlyVerifiedAndUnknownAreNonAlarming() {
        XCTAssertFalse(CaptureHealth.verified.isAlarming)
        XCTAssertFalse(CaptureHealth.unknown.isAlarming)
        XCTAssertTrue(CaptureHealth.degraded([.notificationsSuppressed]).isAlarming)
        XCTAssertTrue(CaptureHealth.blind([.lazyAccessibilityTree]).isAlarming)
    }

    func testEveryCauseHasAdviceThatIsNotEmpty() {
        let all: [HealthCause] = [.notificationPermissionDenied, .notificationsSuppressed,
                                  .selfTestInconclusive,
                                  .accessibilityNotTrusted, .observerNotAttached,
                                  .lazyAccessibilityTree]
        for cause in all {
            XCTAssertFalse(cause.advice.isEmpty, "\(cause) has no advice")
        }
    }
}
