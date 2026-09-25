import XCTest
@testable import NotificationCore

final class HealthTitleTests: XCTestCase {
    func testVerifiedSaysHowOldItsEvidenceIs() {
        XCTAssertEqual(HealthTitle.text(for: .verified, secondsSinceLastSuccessfulCanary: 5),
                       "Working — verified just now")
        XCTAssertEqual(HealthTitle.text(for: .verified, secondsSinceLastSuccessfulCanary: 22 * 60 + 40),
                       "Working — verified 22 min ago")
    }

    func testStaleEvidenceIsUnverifiedAndSaysWhen() {
        XCTAssertEqual(HealthTitle.text(for: .unknown, secondsSinceLastSuccessfulCanary: 34 * 60),
                       "Unverified — last verified 34 min ago")
    }

    func testStaleEvidenceDoesNotClaimACheckIsUnderWay() {
        let title = HealthTitle.text(for: .unknown, secondsSinceLastSuccessfulCanary: 34 * 60)
        XCTAssertFalse(title.contains("Checking"), title)
        XCTAssertFalse(title.hasPrefix("Working"), title)
    }

    func testBeforeAnySelfTestItIsStillChecking() {
        XCTAssertEqual(HealthTitle.text(for: .unknown, secondsSinceLastSuccessfulCanary: nil), "Checking…")
    }

    func testFaultTitlesAreUnchangedByAge() {
        XCTAssertEqual(HealthTitle.text(for: .degraded([.selfTestInconclusive]), secondsSinceLastSuccessfulCanary: 60),
                       "Cannot verify itself")
        XCTAssertEqual(HealthTitle.text(for: .blind([.lazyAccessibilityTree]), secondsSinceLastSuccessfulCanary: 60),
                       "NOT capturing notifications")
    }

    func testAgesReadNaturally() {
        XCTAssertEqual(HealthTitle.ago(0), "just now")
        XCTAssertEqual(HealthTitle.ago(59), "just now")
        XCTAssertEqual(HealthTitle.ago(60), "1 min ago")
        XCTAssertEqual(HealthTitle.ago(59 * 60 + 59), "59 min ago")
        XCTAssertEqual(HealthTitle.ago(3600), "1 hr ago")
        XCTAssertEqual(HealthTitle.ago(3600 + 5 * 60), "1 hr 5 min ago")
        XCTAssertEqual(HealthTitle.ago(26 * 3600), "26 hr ago")
    }

    func testAClockSetBackwardsReadsAsJustNow() {
        XCTAssertEqual(HealthTitle.ago(-300), "just now")
    }
}
