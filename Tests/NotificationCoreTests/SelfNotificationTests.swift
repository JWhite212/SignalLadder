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

    func testRecognisesEverythingItPostsAboutItself() {
        // The self-test is included deliberately. It is normally excluded
        // earlier by its per-run marker, but that match is exactly what fails
        // when a self-test fails — so without this backstop a failing canary
        // would inflate the count it is supposed to be invisible to.
        for title in [SelfNotification.blindTitle,
                      SelfNotification.degradedTitle,
                      SelfNotification.selfTestTitle] {
            XCTAssertTrue(
                SelfNotification.isOwnNotification(banner(app: "SignalLadder", title: title),
                                                   ownAppName: "SignalLadder"),
                "Failed to recognise its own notification titled \(title)"
            )
        }
    }

    /// The reason this test exists. Excluding on name alone would discard a
    /// real notification from an app that merely shares our name — a silent
    /// loss, which is the failure the whole product is built to prevent.
    func testDoesNotDiscardARealNotificationFromASameNamedApp() {
        let real = banner(app: "SignalLadder", title: "Your build finished")
        XCTAssertFalse(SelfNotification.isOwnNotification(real, ownAppName: "SignalLadder"))
    }

    func testDoesNotClaimAnotherAppsNotificationQuotingOurWording() {
        let quoted = banner(app: "Microsoft Teams", title: SelfNotification.blindTitle)
        XCTAssertFalse(SelfNotification.isOwnNotification(quoted, ownAppName: "SignalLadder"))
    }

    func testExcludesNothingWhenTheBundleDeclaresNoName() {
        let ours = banner(app: "SignalLadder", title: SelfNotification.blindTitle)
        XCTAssertFalse(SelfNotification.isOwnNotification(ours, ownAppName: nil))
    }

    /// `NotificationFieldExtractor` yields an empty `appNameGuess` for any
    /// banner with no comma. An empty own-name must not match those, or a whole
    /// class of notifications would vanish at once.
    func testEmptyOwnNameMatchesNothing() {
        let anonymous = banner(app: "", title: SelfNotification.blindTitle)
        XCTAssertFalse(SelfNotification.isOwnNotification(anonymous, ownAppName: ""))
    }

    // MARK: - The banner's fallback body

    /// The wording the banner has always carried when its health gives no cause
    /// to say. It moved here from the alarm unchanged, so it is held to what it
    /// was.
    func testTheFallbackBodyIsTheWordingTheBannerAlwaysHad() {
        XCTAssertEqual(SelfNotification.fallbackBody, "Open the menu for details.")
    }

    func testTheFallbackBodyIsNotEmpty() {
        XCTAssertFalse(SelfNotification.fallbackBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// It points at the menu and holds no notification text: no app name, none of
    /// the app's own titles and no cause's advice, which are the only words a
    /// banner of its own could be mistaken for or confused with.
    func testTheFallbackBodyHoldsNoNotificationTextOrCause() {
        let body = SelfNotification.fallbackBody
        for title in [SelfNotification.blindTitle, SelfNotification.degradedTitle, SelfNotification.selfTestTitle] {
            XCTAssertNotEqual(body, title)
            XCTAssertFalse(body.contains(title))
        }
        XCTAssertFalse(body.contains("SignalLadder"), "no app name, the app's own included")
        XCTAssertFalse(body.contains("\\("), "no interpolation: it is a constant")
    }

    /// The banner the alarm posts with it is still recognised as the app's own
    /// when capture reads it back, for either title it carries.
    func testABannerCarryingTheFallbackBodyIsStillRecognisedAsItsOwn() {
        for title in [SelfNotification.blindTitle, SelfNotification.degradedTitle] {
            let notification = CapturedNotification(
                timestamp: Date(timeIntervalSince1970: 1_757_000_000),
                appNameGuess: "SignalLadder",
                title: title,
                subtitle: "",
                body: SelfNotification.fallbackBody,
                rawText: "SignalLadder, \(title), \(SelfNotification.fallbackBody)",
                subrole: "AXNotificationCenterBanner")
            XCTAssertTrue(SelfNotification.isOwnNotification(notification, ownAppName: "SignalLadder"), title)
        }
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
        XCTAssertTrue(SelfNotification.isOwnNotification(extracted, ownAppName: "SignalLadder"))
    }
}
