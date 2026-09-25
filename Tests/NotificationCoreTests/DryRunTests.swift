import XCTest
@testable import NotificationCore

/// The dry-run must answer for the rules as they will be once saved — order,
/// switches and problems included — and its wording must never read as
/// protection that is not yet in force.
final class DryRunTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_757_000_000)
    private let sounds = RuleSetCodec.SoundCheck(available: ["Glass"], unplayable: nil)

    private func note(_ app: String, _ title: String = "t", _ body: String = "b") -> CapturedNotification {
        CapturedNotification(timestamp: t0, appNameGuess: app, title: title, subtitle: "", body: body,
                             rawText: "\(app), \(title), \(body)", subrole: "AXNotificationCenterBanner")
    }

    private func entries(_ notes: CapturedNotification...) -> [InspectorEntry] {
        notes.map { InspectorEntry(captured: $0, context: ContextSnapshot(date: t0, recentCountForApp: 1),
                                   suppressedRepeatCount: 0, annotation: nil, preview: nil) }
    }

    private func rule(_ name: String, app: String, on: Bool = true, alert: AlertAction? = nil) -> Rule {
        Rule(name: name, condition: .field(.app, .equals, app), isEnabled: on, alert: alert)
    }

    private let mention = Rule(name: "Mentions", condition: .field(.raw, .contains, "@me"))

    // MARK: - Verdicts

    func testEachNotificationIsMatchedClaimedOrNot() {
        let held = entries(note("Teams", "All Hands", "@me hi"), note("Teams", "Random", "noise"), note("Weather", "Rain"))
        let rules = [rule("All Teams", app: "Teams"), mention]
        let run = DryRun.report(forRuleAt: 1, in: rules, over: held, sounds: sounds)

        XCTAssertEqual(run.rows.map(\.verdict), [.claimedBy(index: 0, name: "All Teams"), .notMatched, .notMatched])
        XCTAssertEqual(run.rows.map(\.entryID), held.map(\.id), "one row per notification, in the order given")
        XCTAssertEqual(run.matchedCount, 0)
        XCTAssertEqual(run.claimedCount, 1)
        XCTAssertEqual(run.moveAboveIndex, 0)
    }

    func testARuleBelowItNeverClaims() {
        let held = entries(note("Teams", "x", "@me"))
        let run = DryRun.report(forRuleAt: 0, in: [mention, rule("All Teams", app: "Teams")], over: held, sounds: sounds)
        XCTAssertEqual(run.rows.map(\.verdict), [.matched])
    }

    func testARuleAboveThatIsOffOrBrokenClaimsNothing() {
        // Neither will be in effect once saved: the loader drops a broken
        // rule, and an off rule never matches.
        let held = entries(note("Teams", "x", "@me"))
        let off = rule("Off", app: "Teams", on: false)
        let broken = rule("Broken", app: "Teams", alert: .sound(name: "Glas", gainDB: 0))
        let run = DryRun.report(forRuleAt: 2, in: [off, broken, mention], over: held, sounds: sounds)
        XCTAssertEqual(run.rows.map(\.verdict), [.matched])
    }

    func testAnOffRuleIsTriedAsIfOnAndSaysSo() {
        var draft = mention
        draft.isEnabled = false
        let run = DryRun.report(forRuleAt: 0, in: [draft], over: entries(note("Teams", "x", "@me")), sounds: sounds)
        XCTAssertEqual(run.matchedCount, 1)
        XCTAssertTrue(run.ruleIsOff)
        XCTAssertEqual(EditorText.dryRunHeadline(run), "In this draft: would match 1 of the last 1 notification when switched on.")
    }

    func testABrokenRuleIsReportedAsNotGoingToRun() {
        let broken = Rule(name: "Pager", condition: .field(.raw, .contains, "@me"), alert: .sound(name: "Glas", gainDB: 0))
        let run = DryRun.report(forRuleAt: 0, in: [broken], over: entries(note("Teams", "x", "@me")), sounds: sounds)
        XCTAssertTrue(run.ruleHasProblems)
    }

    func testMovingAboveTheEarliestClaimerFreesEverything() {
        let held = entries(note("Teams", "x", "@me"), note("Slack", "y", "@me"))
        let rules = [rule("Slack", app: "Slack"), rule("Teams", app: "Teams"), mention]
        let run = DryRun.report(forRuleAt: 2, in: rules, over: held, sounds: sounds)
        XCTAssertEqual(run.claimers.map(\.name), ["Slack", "Teams"])
        XCTAssertEqual(run.moveAboveIndex, 0)

        var moved = rules
        moved.insert(moved.remove(at: 2), at: run.moveAboveIndex!)
        XCTAssertEqual(DryRun.report(forRuleAt: 0, in: moved, over: held, sounds: sounds).matchedCount, 2)
    }

    func testAStaleIndexReportsNothingRatherThanTrapping() {
        XCTAssertEqual(DryRun.report(forRuleAt: 3, in: [mention], over: entries(note("a")), sounds: sounds).rows, [])
        XCTAssertEqual(DryRun.report(forRuleAt: -1, in: [mention], over: entries(note("a")), sounds: sounds).rows, [])
    }

    // MARK: - Wording

    func testTheHeadlineAlwaysSaysItIsTheDraft() {
        let held = entries(note("Teams", "x", "@me"), note("Teams", "y", "nothing"))
        let run = DryRun.report(forRuleAt: 0, in: [mention], over: held, sounds: sounds)
        XCTAssertEqual(EditorText.dryRunHeadline(run), "In this draft: matches 1 of the last 2 notifications.")

        let none = DryRun.report(forRuleAt: 0, in: [mention], over: entries(note("Teams", "x", "no")), sounds: sounds)
        XCTAssertEqual(EditorText.dryRunHeadline(none), "In this draft: matches none of the last 1 notification.")

        let empty = DryRun.report(forRuleAt: 0, in: [mention], over: [], sounds: sounds)
        XCTAssertEqual(EditorText.dryRunHeadline(empty), "No notifications captured yet to try this rule on.")
    }

    func testClaimedNotificationsAreNamedByTheRuleThatTakesThem() {
        let held = entries(note("Teams", "x", "@me"), note("Teams", "y", "@me"), note("Slack", "z", "@me"))
        let one = DryRun.report(forRuleAt: 1, in: [rule("All Teams", app: "Teams"), mention], over: held, sounds: sounds)
        XCTAssertEqual(EditorText.claimed(one), "2 more are taken first by “All Teams”, above it.")

        let two = DryRun.report(forRuleAt: 2, in: [rule("All Teams", app: "Teams"), rule("Slack", app: "Slack"), mention],
                                over: held, sounds: sounds)
        XCTAssertEqual(EditorText.claimed(two), "3 more are taken first by 2 rules above it.")
        XCTAssertNil(EditorText.claimed(DryRun.report(forRuleAt: 0, in: [mention], over: held, sounds: sounds)))
    }

    func testWhatIsNotInEffectSaysWhyTheMostSeriousReasonFirst() {
        XCTAssertEqual(EditorText.notInEffect(hasProblems: true, isOff: true, isUnsaved: true),
                       "Not in effect: this rule has problems, and will not run until they are fixed.")
        XCTAssertEqual(EditorText.notInEffect(hasProblems: false, isOff: true, isUnsaved: true),
                       "Not in effect: this rule is switched off.")
        XCTAssertEqual(EditorText.notInEffect(hasProblems: false, isOff: false, isUnsaved: true), "Not in effect until you save.")
        XCTAssertNil(EditorText.notInEffect(hasProblems: false, isOff: false, isUnsaved: false))
    }

    // MARK: - Seeding

    func testANewRuleSeedsOnlyTheAppAndStartsOffAndSilent() {
        let seeded = RuleSeed.rule(from: note("Microsoft Teams", "This is a test notification", "Message preview."))
        XCTAssertEqual(seeded.condition, .field(.app, .equals, "Microsoft Teams"))
        XCTAssertFalse(seeded.isEnabled)
        XCTAssertNil(seeded.alert)
        XCTAssertEqual(seeded.name, "New rule for Microsoft Teams", "named from the app alone, never from message text")
    }

    func testANotificationWithNoAppStillSeedsAnHonestRule() {
        let seeded = RuleSeed.rule(from: note("", "Title only"))
        XCTAssertEqual(seeded.name, "New rule")
        XCTAssertEqual(seeded.condition, .field(.app, .equals, ""), "matches what it matched: no app")
        XCTAssertFalse(seeded.name.contains("Title only"))
    }

    func testANewRuleIsPlacedAboveWhateverWouldTakeItsNotification() {
        let n = note("Teams", "x", "@me")
        let rules = [rule("Weather", app: "Weather"), rule("All Teams", app: "Teams"), mention]
        XCTAssertEqual(RuleSeed.insertionIndex(for: n, in: rules, sounds: sounds), 1)
        XCTAssertEqual(RuleSeed.insertionIndex(for: note("Slack"), in: rules, sounds: sounds), 3, "nothing takes it: last")

        let offOrBroken = [rule("Off", app: "Teams", on: false), rule("Broken", app: "Teams", alert: .sound(name: "Glas", gainDB: 0))]
        XCTAssertEqual(RuleSeed.insertionIndex(for: n, in: offOrBroken, sounds: sounds), 2, "neither will take it")
    }

    func testFieldOffersMatchFreeTextByContainsAndIdentityByEquals() {
        let offers = RuleSeed.offers(from: note("Microsoft Teams", "All Hands", "@Jamie are you there"))
        XCTAssertEqual(offers, [
            .field(.app, .equals, "Microsoft Teams"),
            .field(.title, .contains, "All Hands"),
            .field(.subtitle, .equals, ""),
            .field(.body, .contains, "@Jamie are you there"),
            .field(.raw, .contains, "Microsoft Teams, All Hands, @Jamie are you there"),
            .field(.subrole, .equals, "AXNotificationCenterBanner"),
        ])
        for offer in offers {
            XCTAssertEqual(RuleSetCodec.problems(in: Rule(name: "r", condition: offer)), [],
                           "every offer is valid as offered: \(offer)")
        }
    }

    // MARK: - Read-only and conflicts

    func testReadOnlyReasonsSayWhatToDo() {
        let undecodable = EditorText.readOnly(.undecodable([RuleSetCodec.Problem(index: 1, name: "Typo", reason: "unknown key \"alrt\"")]))
        XCTAssertEqual(undecodable.title, "1 rule in the file can't be read, so saving here would drop it. Fix it in a text editor.")
        XCTAssertEqual(undecodable.detail, ["Rule 2 (\"Typo\"): unknown key \"alrt\""])
        XCTAssertEqual(EditorText.readOnly(.newerVersion(3)).title, "The rules file was written by a newer SignalLadder (format 3).")
        XCTAssertEqual(EditorText.readOnly(.unreadable("not valid JSON: x")).detail, ["not valid JSON: x"])
    }

    func testAConflictSaysWhatSaveAnywayWouldReplace() {
        XCTAssertEqual(EditorText.conflictDetail(RulesChange(file: .edited, added: ["New"], removed: ["Old"], changed: ["Edited"])),
                       "Added: “New”. Removed: “Old”. Changed: “Edited”.")
        XCTAssertEqual(EditorText.conflictDetail(RulesChange(file: .edited, added: [], removed: [], changed: [])),
                       "Only its formatting changed.")
        XCTAssertEqual(EditorText.conflictDetail(RulesChange(file: .deleted, added: [], removed: ["A"], changed: [])),
                       "It was deleted with “A”.")
        XCTAssertEqual(EditorText.conflictDetail(RulesChange(file: .created, added: [], removed: [], changed: [])),
                       "It was created.")
        XCTAssertEqual(EditorText.conflictDetail(RulesChange(file: .unreadable, added: [], removed: [], changed: [])),
                       "It was edited into something that can no longer be read as rules.")
    }
}
