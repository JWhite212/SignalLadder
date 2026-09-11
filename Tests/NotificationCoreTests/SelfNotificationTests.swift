import XCTest
@testable import NotificationCore

final class SelfNotificationTests: XCTestCase {
    private func banner(app: String, title: String) -> CapturedNotification {
        CapturedNotification(
            timestamp: Date(timeIntervalSince1970: 1_757_000_000),
            appNameGuess: app,
            title: title,
            subtitle: "",
            body: "Open the menu for details.",
            rawText: "\(app), \(title), Open the menu for details.",
            subrole: "AXNotificationCenterBanner"
        )
    }

    func testRecognisesItsOwnAlarms() {
        for title in [SelfNotification.blindTitle, SelfNotification.degradedTitle] {
            XCTAssertTrue(
                SelfNotification.isOwnAlarm(banner(app: "SignalLadder", title: title),
                                            ownAppName: "SignalLadder"),
                "Failed to recognise its own alarm titled \(title)"
            )
        }
    }

    /// The reason this test exists. Excluding on name alone would discard a
    /// real notification from an app that merely shares our name — a silent
    /// loss, which is the failure the whole product is built to prevent.
    func testDoesNotDiscardARealNotificationFromASameNamedApp() {
        let real = banner(app: "SignalLadder", title: "Your build finished")
        XCTAssertFalse(SelfNotification.isOwnAlarm(real, ownAppName: "SignalLadder"))
    }

    func testDoesNotClaimAnotherAppsNotificationQuotingOurWording() {
        let quoted = banner(app: "Microsoft Teams", title: SelfNotification.blindTitle)
        XCTAssertFalse(SelfNotification.isOwnAlarm(quoted, ownAppName: "SignalLadder"))
    }

    func testExcludesNothingWhenTheBundleDeclaresNoName() {
        let ours = banner(app: "SignalLadder", title: SelfNotification.blindTitle)
        XCTAssertFalse(SelfNotification.isOwnAlarm(ours, ownAppName: nil))
    }

    /// `NotificationFieldExtractor` yields an empty `appNameGuess` for any
    /// banner with no comma. An empty own-name must not match those, or a whole
    /// class of notifications would vanish at once.
    func testEmptyOwnNameMatchesNothing() {
        let anonymous = banner(app: "", title: SelfNotification.blindTitle)
        XCTAssertFalse(SelfNotification.isOwnAlarm(anonymous, ownAppName: ""))
    }

    /// Field extraction and recognition must agree. If the extractor's notion
    /// of title ever drifts from what the alarm sets, the exclusion silently
    /// stops working and self-alarms start counting as user traffic.
    func testMatchesWhatTheExtractorProducesFromARealAlarmBanner() {
        let raw = RawCapture(
            timestamp: Date(timeIntervalSince1970: 1_757_000_000),
            rawText: "SignalLadder, \(SelfNotification.degradedTitle), Open the menu for details.",
            subrole: "AXNotificationCenterBanner"
        )
        let extracted = NotificationFieldExtractor.extract(
            raw,
            textChildren: [SelfNotification.degradedTitle, "Open the menu for details."]
        )
        XCTAssertTrue(SelfNotification.isOwnAlarm(extracted, ownAppName: "SignalLadder"))
    }
}
