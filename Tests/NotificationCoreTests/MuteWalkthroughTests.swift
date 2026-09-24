import XCTest
@testable import NotificationCore

final class MuteWalkthroughTests: XCTestCase {
    private func rule(_ condition: RuleCondition, enabled: Bool = true,
                      _ alert: AlertAction? = .sound(name: "Glass", gainDB: 0)) -> Rule {
        Rule(name: "r", condition: condition, isEnabled: enabled, alert: alert)
    }

    private func app(_ name: String) -> RuleCondition { .field(.app, .equals, name) }

    // MARK: - Which apps need muting

    func testAnEnabledSoundingRuleNamesItsApp() {
        XCTAssertEqual(MuteWalkthrough.appsToMute(rules: [rule(app("Microsoft Teams"))], alsoSounded: []),
                       ["Microsoft Teams"])
    }

    func testOnlyRulesThatMakeANoiseNeedTheirAppMuted() {
        let rules = [rule(app("Weather"), .silent),
                     rule(app("Mail"), nil),
                     rule(app("Slack"), enabled: false)]
        XCTAssertEqual(MuteWalkthrough.appsToMute(rules: rules, alsoSounded: []), [],
                       "an app whose rule makes no sound is not double-alerting anyone")
    }

    func testAppsAreFoundThroughAndAndOr() {
        let condition = RuleCondition.and([.or([app("Teams"), app("Slack")]), .field(.title, .contains, "@me")])
        XCTAssertEqual(MuteWalkthrough.appsToMute(rules: [rule(condition)], alsoSounded: []), ["Teams", "Slack"])
    }

    func testANegatedOrPatternedAppIsNotANameToMute() {
        let rules = [rule(.not(app("Teams"))),
                     rule(.field(.app, .matches, "Microsoft*")),
                     rule(.field(.app, .contains, "Team")),
                     rule(.field(.app, .notEquals, "Mail"))]
        XCTAssertEqual(MuteWalkthrough.appsToMute(rules: rules, alsoSounded: []), [])
    }

    func testAppsThatSoundedAreAddedAfterNamedOnesWithoutDuplicates() {
        let apps = MuteWalkthrough.appsToMute(rules: [rule(app("Météo"))],
                                              alsoSounded: ["meteo", "Microsoft Teams", " "])
        XCTAssertEqual(apps, ["Météo", "Microsoft Teams"],
                       "case and accents are ignored when combining, the first spelling kept, blanks dropped")
    }

    // MARK: - The checklist

    func testConfirmationIsMatchedIgnoringCaseAndAccents() {
        var list = MuteChecklist()
        list.setConfirmed("Météo", true)
        XCTAssertTrue(list.isConfirmed("METEO"))
        list.setConfirmed("meteo", false)
        XCTAssertFalse(list.isConfirmed("Météo"))
        XCTAssertEqual(list.confirmed, [])
    }

    func testReconfirmingDoesNotDuplicate() {
        var list = MuteChecklist(confirmed: ["Teams", "teams"])
        XCTAssertEqual(list.confirmed, ["Teams"])
        list.setConfirmed("TEAMS", true)
        XCTAssertEqual(list.confirmed, ["TEAMS"])
    }

    func testUnconfirmedAppsKeepTheirOrder() {
        let list = MuteChecklist(confirmed: ["Slack"])
        XCTAssertEqual(list.unconfirmed(among: ["Teams", "Slack", "Mail"]), ["Teams", "Mail"])
    }

    // MARK: - Finding the bundle ID

    private let teams = AppCandidate(bundleID: "com.microsoft.teams2", names: ["Microsoft Teams"])
    private let classicTeams = AppCandidate(bundleID: "com.microsoft.teams", names: ["Microsoft Teams"])

    func testAUniqueRunningAppIsFoundWithoutReadingTheDisk() {
        let resolution = BundleResolver.resolve("microsoft teams", running: [teams], installed: {
            XCTFail("the disk is read only when the running apps do not settle it")
            return []
        })
        XCTAssertEqual(resolution, .unique("com.microsoft.teams2"))
    }

    func testTheRunningAppWinsOverAnOlderInstalledOneOfTheSameName() {
        XCTAssertEqual(BundleResolver.resolve("Microsoft Teams", running: [teams], installed: { [self] in [teams, classicTeams] }),
                       .unique("com.microsoft.teams2"))
    }

    func testAnAppNotRunningIsFoundAmongInstalledApps() {
        let weather = AppCandidate(bundleID: "com.apple.weather", names: ["Weather", "Météo"])
        XCTAssertEqual(BundleResolver.resolve("meteo", running: [teams], installed: { [weather] }),
                       .unique("com.apple.weather"))
    }

    func testTwoAppsWithOneNameAreAmbiguousRatherThanGuessed() {
        XCTAssertEqual(BundleResolver.resolve("Microsoft Teams", running: [], installed: { [self] in [teams, classicTeams] }),
                       .ambiguous(["com.microsoft.teams2", "com.microsoft.teams"]))
    }

    func testTwoRunningAppsWithOneNameAreAmbiguousWithoutReadingTheDisk() {
        let resolution = BundleResolver.resolve("Microsoft Teams", running: [teams, classicTeams], installed: {
            XCTFail("two running matches are already an answer: the user must choose")
            return []
        })
        XCTAssertEqual(resolution, .ambiguous(["com.microsoft.teams2", "com.microsoft.teams"]))
    }

    func testOneAppFoundTwiceIsStillOneApp() {
        let twice = [teams, AppCandidate(bundleID: "COM.microsoft.teams2", names: ["Microsoft Teams"])]
        XCTAssertEqual(BundleResolver.resolve("Microsoft Teams", running: twice, installed: { [] }),
                       .unique("com.microsoft.teams2"))
    }

    func testNothingFoundIsSaid() {
        XCTAssertEqual(BundleResolver.resolve("Nonexistent", running: [teams], installed: { [] }), .notFound)
        XCTAssertEqual(BundleResolver.resolve("  ", running: [AppCandidate(bundleID: "x", names: [""])], installed: { [] }),
                       .notFound, "a blank name matches nothing, not every nameless app")
    }

    // MARK: - Where the links go

    func testAUniqueMatchLinksStraightToTheApp() {
        XCTAssertEqual(BundleResolver.notificationSettingsURL(for: .unique("com.microsoft.teams2")).absoluteString,
                       "x-apple.systempreferences:com.apple.preference.notifications?id=com.microsoft.teams2")
    }

    func testAnythingElseOpensTheNotificationsPane() {
        let pane = "x-apple.systempreferences:com.apple.preference.notifications"
        XCTAssertEqual(BundleResolver.notificationSettingsURL(for: .notFound).absoluteString, pane)
        XCTAssertEqual(BundleResolver.notificationSettingsURL(for: .ambiguous(["a", "b"])).absoluteString, pane)
    }

    func testAnOddBundleIDCannotBreakOutOfTheLink() {
        XCTAssertEqual(BundleResolver.notificationSettingsURL(for: .unique("a&b=c d")).absoluteString,
                       "x-apple.systempreferences:com.apple.preference.notifications?id=a%26b%3Dc%20d")
    }

    // MARK: - Wording

    func testTheTitleNamesWhatIsOutstanding() {
        let list = MuteChecklist(confirmed: ["Slack"])
        XCTAssertEqual(MuteWalkthroughText.title(apps: ["Teams", "Slack"], checklist: list), "⚠︎ Not confirmed muted: Teams")
        XCTAssertEqual(MuteWalkthroughText.title(apps: ["Slack"], checklist: list), "Confirmed muted: Slack")
    }

    func testListsReadAsEnglish() {
        XCTAssertEqual(MuteWalkthroughText.list(["A"]), "A")
        XCTAssertEqual(MuteWalkthroughText.list(["A", "B"]), "A and B")
        XCTAssertEqual(MuteWalkthroughText.list(["A", "B", "C"]), "A, B and C")
        XCTAssertEqual(MuteWalkthroughText.list(["A", "B", "C", "D", "E"]), "A, B, C and 2 more")
    }

    func testAFallbackPutsTheNameOnScreenAndAUniqueMatchNeedsNone() {
        XCTAssertNil(MuteWalkthroughText.lookupFallback("Teams", .unique("com.microsoft.teams2")))
        XCTAssertEqual(MuteWalkthroughText.lookupFallback("Teams", .notFound)?.body.contains("“Teams”"), true)
        let ambiguous = MuteWalkthroughText.lookupFallback("Teams", .ambiguous(["a.b", "c.d"]))
        XCTAssertEqual(ambiguous?.title.contains("More than one"), true)
        XCTAssertEqual(ambiguous?.body.contains("a.b, c.d"), true)
    }
}
