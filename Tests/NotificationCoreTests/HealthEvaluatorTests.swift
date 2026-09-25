import XCTest
@testable import NotificationCore

final class HealthEvaluatorTests: XCTestCase {
    private func inputs(trusted: Bool = true,
                        attached: Bool = true,
                        authorized: Bool = true,
                        wouldDisplay: Bool = true,
                        failures: Int? = 0,
                        noBannerActivity: Bool = false,
                        capturesSince: Int = 0,
                        verifiedAgo: TimeInterval? = 0,
                        interval: TimeInterval = HealthEvaluator.selfTestInterval) -> HealthInputs {
        HealthInputs(accessibilityTrusted: trusted,
                     observerAttached: attached,
                     notificationsAuthorized: authorized,
                     notificationsWouldDisplay: wouldDisplay,
                     consecutiveCanaryFailures: failures,
                     canaryFailedWithNoBannerActivity: noBannerActivity,
                     capturesSinceLastCanary: capturesSince,
                     secondsSinceLastSuccessfulCanary: verifiedAgo,
                     selfTestInterval: interval)
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

    func testCapturedTrafficSettlesWhatTheSelfTestCannot() {
        // Observed live: the canary was accepted by the notification daemon and
        // never displayed, while three notifications from another app were
        // captured normally. The app reported "either not shown, or blind" —
        // honest, but it held the evidence ruling one of those out.
        let health = HealthEvaluator.evaluate(
            inputs(failures: 1, noBannerActivity: true, capturesSince: 3))
        XCTAssertEqual(health, .degraded([.ownAlertsNotShown]))
    }

    func testWithNoTrafficTheFailureStaysHonestlyAmbiguous() {
        // The complement: absent traffic, nothing has been ruled out and the
        // app must not manufacture a diagnosis from silence.
        let health = HealthEvaluator.evaluate(
            inputs(failures: 1, noBannerActivity: true, capturesSince: 0))
        XCTAssertEqual(health, .degraded([.selfTestAlertNeverSeen]))
    }

    func testCapturedTrafficDoesNotOverrideADefiniteCaptureFault() {
        // Stale traffic must never mask an observer that has since detached.
        XCTAssertEqual(
            HealthEvaluator.evaluate(inputs(attached: false, failures: 2, capturesSince: 9)),
            .blind([.observerNotAttached]))
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

    // MARK: - How old the evidence is
    //
    // A live run on 2026-09-25: capture went blind about 80 seconds after a
    // self-test passed at launch, and the menu said "Working — verified" for as
    // long as the app ran — up to 30 minutes, until the next self-test. The
    // claim was about one moment and never aged.

    func testRecentEvidenceIsVerified() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(verifiedAgo: 29 * 60)), .verified)
    }

    func testEvidenceOlderThanTheNextSelfTestShouldHaveBeenIsNoLongerVerified() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(verifiedAgo: 32 * 60)), .unknown)
    }

    func testTheGraceAbsorbsASelfTestThatStartsALittleLate() {
        let justLate = HealthEvaluator.selfTestInterval + HealthEvaluator.freshnessGrace / 2
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(verifiedAgo: justLate)), .verified)
    }

    func testEvidenceExactlyAtTheLimitStillCounts() {
        let limit = HealthEvaluator.selfTestInterval + HealthEvaluator.freshnessGrace
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(verifiedAgo: limit)), .verified)
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(verifiedAgo: limit + 1)), .unknown)
    }

    func testStaleEvidenceIsUnverifiedNotAlarming() {
        // Staleness is missing evidence, not evidence of a fault. It must not
        // sound the audible alarm on a quiet night.
        XCTAssertFalse(HealthEvaluator.evaluate(inputs(verifiedAgo: 3 * 3600)).isAlarming)
    }

    func testAShorterIntervalAgesEvidenceSooner() {
        // The on-call cadence (§14: 5 minutes) must age evidence at its own
        // rate, or "verified" would outlive the promise the cadence makes.
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(verifiedAgo: 7 * 60, interval: 5 * 60)), .unknown)
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(verifiedAgo: 4 * 60, interval: 5 * 60)), .verified)
    }

    func testTheAgeOfAnOldSuccessNeverSoftensALaterFailure() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(failures: 1, verifiedAgo: 10)),
                       .degraded([.selfTestInconclusive]))
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(failures: 2, verifiedAgo: 3 * 3600)),
                       .blind([.lazyAccessibilityTree]))
    }

    func testAgeCannotManufactureAVerdictBeforeAnySelfTestRan() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(failures: nil, verifiedAgo: nil)), .unknown)
    }

    func testDefiniteCaptureFaultsOutrankFreshEvidence() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(trusted: false, verifiedAgo: 5)),
                       .blind([.accessibilityNotTrusted]))
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
