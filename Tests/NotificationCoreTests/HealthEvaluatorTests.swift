import XCTest
@testable import NotificationCore

final class HealthEvaluatorTests: XCTestCase {
    private func inputs(trusted: Bool = true,
                        attached: Bool = true,
                        authorized: Bool = true,
                        wouldDisplay: Bool = true,
                        canary: Bool? = true) -> HealthInputs {
        HealthInputs(accessibilityTrusted: trusted,
                     observerAttached: attached,
                     notificationsAuthorized: authorized,
                     notificationsWouldDisplay: wouldDisplay,
                     lastCanarySucceeded: canary)
    }

    func testEverythingHealthyAndCanaryPassedIsVerified() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs()), .verified)
    }

    func testNoCanaryYetIsUnknownNotVerified() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(canary: nil)), .unknown)
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
        let health = HealthEvaluator.evaluate(inputs(wouldDisplay: false, canary: false))
        XCTAssertEqual(health, .degraded([.notificationsSuppressed]))
    }

    func testDeniedNotificationPermissionDegradesRatherThanBlinds() {
        let health = HealthEvaluator.evaluate(inputs(authorized: false, canary: false))
        XCTAssertEqual(health, .degraded([.notificationPermissionDenied]))
    }

    func testBothDeliveryFaultsAreReportedTogether() {
        let health = HealthEvaluator.evaluate(inputs(authorized: false, wouldDisplay: false, canary: false))
        XCTAssertEqual(health, .degraded([.notificationPermissionDenied, .notificationsSuppressed]))
    }

    /// Delivery confirmed working, capture configured, and the round trip
    /// still failed — this is the macOS 15.4 lazy-tree signature.
    func testFailedCanaryWithHealthyDeliveryIsBlindOnTheLazyTree() {
        XCTAssertEqual(HealthEvaluator.evaluate(inputs(canary: false)),
                       .blind([.lazyAccessibilityTree]))
    }

    func testCaptureFaultsOutrankDeliveryFaults() {
        // Untrusted AND suppressed: the capture fault is the actionable one.
        let health = HealthEvaluator.evaluate(inputs(trusted: false, wouldDisplay: false, canary: false))
        XCTAssertEqual(health, .blind([.accessibilityNotTrusted]))
    }

    func testDeliveryAndCaptureFaultsAreCorrectlyClassified() {
        XCTAssertTrue(HealthCause.notificationPermissionDenied.isDeliveryFault)
        XCTAssertTrue(HealthCause.notificationsSuppressed.isDeliveryFault)
        XCTAssertFalse(HealthCause.accessibilityNotTrusted.isDeliveryFault)
        XCTAssertFalse(HealthCause.observerNotAttached.isDeliveryFault)
        XCTAssertFalse(HealthCause.lazyAccessibilityTree.isDeliveryFault)
    }

    func testOnlyVerifiedAndUnknownAreNonAlarming() {
        XCTAssertFalse(CaptureHealth.verified.isAlarming)
        XCTAssertFalse(CaptureHealth.unknown.isAlarming)
        XCTAssertTrue(CaptureHealth.degraded([.notificationsSuppressed]).isAlarming)
        XCTAssertTrue(CaptureHealth.blind([.lazyAccessibilityTree]).isAlarming)
    }

    func testEveryCauseHasAdviceThatIsNotEmpty() {
        let all: [HealthCause] = [.notificationPermissionDenied, .notificationsSuppressed,
                                  .accessibilityNotTrusted, .observerNotAttached,
                                  .lazyAccessibilityTree]
        for cause in all {
            XCTAssertFalse(cause.advice.isEmpty, "\(cause) has no advice")
        }
    }
}
