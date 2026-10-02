import XCTest
@testable import NotificationCore

/// The dry-run must answer for the rules as they will be once saved — order,
/// switches and problems included — and its wording must never read as
/// protection that is not yet in force.
final class DryRunTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_757_000_000)
    private let sounds = RuleSetCodec.SoundCheck(available: ["Glass"], unplayable: nil, voices: nil, shortcuts: nil)

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
        XCTAssertEqual(EditorText.dryRunHeadline(empty), "In this draft: no notifications captured yet to try this rule on.")
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

    func testARowSummarisesItsAlertInAWordOrTwo() {
        XCTAssertEqual(EditorText.alertSummary(nil), "No alert")
        XCTAssertEqual(EditorText.alertSummary(.silent), "Silent")
        XCTAssertEqual(EditorText.alertSummary(.sound(name: "Glass", gainDB: 0)), "Glass")
        XCTAssertEqual(EditorText.alertSummary(.sound(name: "Glass", gainDB: 6)), "Glass (+6 dB)")
        XCTAssertEqual(EditorText.alertSummary(.sound(name: "Played Out", gainDB: -3)), "Played Out (−3 dB)",
                       "a sound's own name is never trimmed")
    }

    func testADryRunIsUnsavedWhenAnythingAboveTheRuleChanged() {
        let a = rule("A", app: "Teams"), b = rule("B", app: "Slack"), c = mention
        let saved = [a, b, c]
        XCTAssertFalse(DryRun.isUnsaved(c.id, draft: saved, saved: saved, fileVersion: nil, sounds: sounds))

        XCTAssertTrue(DryRun.isUnsaved(c.id, draft: [c, a, b], saved: saved, fileVersion: nil, sounds: sounds), "moved above: its verdicts changed")
        XCTAssertTrue(DryRun.isUnsaved(c.id, draft: [b, a, c], saved: saved, fileVersion: nil, sounds: sounds), "rules above it reordered")
        var offA = a
        offA.isEnabled = false
        XCTAssertTrue(DryRun.isUnsaved(c.id, draft: [offA, b, c], saved: saved, fileVersion: nil, sounds: sounds), "a rule above it switched off")
        XCTAssertFalse(DryRun.isUnsaved(a.id, draft: [a, b, c, rule("New", app: "x")], saved: saved, fileVersion: nil, sounds: sounds),
                       "a change below it does not touch its verdicts")
        XCTAssertFalse(DryRun.isUnsaved(UUID(), draft: [a], saved: saved, fileVersion: nil, sounds: sounds), "a rule no longer in the draft")
        let new = rule("New", app: "x")
        XCTAssertTrue(DryRun.isUnsaved(new.id, draft: [a, new], saved: saved, fileVersion: nil, sounds: sounds), "never saved")
    }

    // MARK: - A rule the loader refuses for its file's version (M5 ruling 2)

    // The dry-run judges the draft as a save would write it, and a save writes
    // the version a ladder needs. Until then the loader has the rule out of
    // effect, so what the dry-run shows must say it is not in effect yet.

    private let teamsCondition = #""condition": {"field": "app", "op": "equals", "value": "Teams"}"#
    private let ladder = #""escalation": {"tier2": {"delaySeconds": 10}}"#

    /// A ladder, which only a file that declares version 4 holds.
    private var pagerJSON: String { #"{"name": "Pager", \#(teamsCondition), "alert": "silent", \#(ladder)}"# }
    private var pagerSwitchedOffJSON: String {
        #"{"name": "Pager", \#(teamsCondition), "enabled": false, "alert": "silent", \#(ladder)}"#
    }
    /// A ladder with a sound that is not there: a fault a save would not fix.
    private var pagerWithATypoJSON: String { #"{"name": "Pager", \#(teamsCondition), "alert": {"sound": "Glas"}, \#(ladder)}"# }
    private var mentionsJSON: String {
        #"{"name": "Mentions", "condition": {"field": "raw", "op": "contains", "value": "@me"}}"#
    }

    private func file(version: Int, _ rules: String...) -> Data {
        Data("{\"version\": \(version), \"rules\": [\(rules.joined(separator: ", "))]}".utf8)
    }

    /// The rules the app runs from this file, by name, as the menu has them.
    private func namesInEffect(_ data: Data) -> [String] {
        RuleStoreStatus.load(data, availableSounds: ["Glass"], unplayable: nil, availableVoices: nil).rules.map(\.name)
    }

    private struct NotEditable: Error {}

    private func edited(_ data: Data) throws -> (rules: [Rule], version: Int?) {
        guard case .editable(let rules, let version) = RulesDocument.load(data) else { throw NotEditable() }
        return (rules, version)
    }

    /// What the dry-run says of the rule at `index`, put together as the
    /// editor puts it together: the report, and whether it is unsaved.
    private func said(ofRuleAt index: Int, in data: Data, over held: [InspectorEntry]) throws -> String? {
        let (rules, version) = try edited(data)
        let run = DryRun.report(forRuleAt: index, in: rules, over: held, sounds: sounds)
        let unsaved = DryRun.isUnsaved(rules[index].id, draft: rules, saved: rules, fileVersion: version, sounds: sounds)
        return EditorText.notInEffect(hasProblems: run.ruleHasProblems, isOff: run.ruleIsOff, isUnsaved: unsaved)
    }

    private let notInEffectUntilSaved = "Not in effect until you save."

    func testARuleTheLoaderRefusesForItsFilesVersionIsNotInEffectUntilYouSave() throws {
        let data = file(version: 3, pagerJSON)
        XCTAssertEqual(namesInEffect(data), [], "the menu has it off")
        let (rules, _) = try edited(data)
        XCTAssertEqual(rules.map(\.name), ["Pager"], "and the editor holds it")

        let held = entries(note("Teams", "x", "@me"))
        XCTAssertEqual(try DryRun.report(forRuleAt: 0, in: edited(data).rules, over: held, sounds: sounds).matchedCount, 1,
                       "judged as a save would write it")
        XCTAssertEqual(try said(ofRuleAt: 0, in: data, over: held), notInEffectUntilSaved)
    }

    func testARuleBelowARefusedRuleIsNotInEffectUntilYouSaveEither() throws {
        // The dry-run has the Pager take what Mentions matches, as it will once
        // saved. The loader is not running the Pager, so today Mentions takes it.
        let data = file(version: 3, pagerJSON, mentionsJSON)
        XCTAssertEqual(namesInEffect(data), ["Mentions"])

        let held = entries(note("Teams", "x", "@me"))
        let run = DryRun.report(forRuleAt: 1, in: try edited(data).rules, over: held, sounds: sounds)
        XCTAssertEqual(run.rows.map(\.verdict), [.claimedBy(index: 0, name: "Pager")])
        XCTAssertEqual(try said(ofRuleAt: 1, in: data, over: held), notInEffectUntilSaved)
    }

    func testNothingIsSaidOfAFileThatDeclaresEnough() throws {
        let data = file(version: 4, pagerJSON, mentionsJSON)
        XCTAssertEqual(namesInEffect(data), ["Pager", "Mentions"])
        let held = entries(note("Teams", "x", "@me"))
        XCTAssertNil(try said(ofRuleAt: 0, in: data, over: held))
        XCTAssertNil(try said(ofRuleAt: 1, in: data, over: held))
    }

    func testARuleSwitchedOffAboveTakesNoPartWhetherOrNotTheFileIsRewritten() throws {
        let data = file(version: 3, pagerSwitchedOffJSON, mentionsJSON)
        XCTAssertEqual(namesInEffect(data), ["Mentions"])
        let held = entries(note("Teams", "x", "@me"))
        XCTAssertNil(try said(ofRuleAt: 1, in: data, over: held), "it claims nothing before a save or after one")
        XCTAssertEqual(try said(ofRuleAt: 0, in: data, over: held), "Not in effect: this rule is switched off.",
                       "and for itself, off is the reason said")
    }

    func testARuleBelowItDoesNotMakeItsVerdictsUnsaved() throws {
        let data = file(version: 3, mentionsJSON, pagerJSON)
        let held = entries(note("Teams", "x", "@me"))
        XCTAssertNil(try said(ofRuleAt: 0, in: data, over: held), "its verdicts do not rest on a rule below it")
        XCTAssertEqual(try said(ofRuleAt: 1, in: data, over: held), notInEffectUntilSaved)
    }

    func testARuleRefusedForMoreThanTheVersionIsStillAProblemAndASaveDoesNotFixIt() throws {
        let data = file(version: 3, pagerWithATypoJSON, mentionsJSON)
        XCTAssertEqual(namesInEffect(data), ["Mentions"])
        let (rules, version) = try edited(data)
        XCTAssertFalse(DryRun.isUnsaved(rules[1].id, draft: rules, saved: rules, fileVersion: version, sounds: sounds),
                       "a save would not put the Pager into effect, so Mentions does not wait for one")
        XCTAssertFalse(DryRun.isUnsaved(rules[0].id, draft: rules, saved: rules, fileVersion: version, sounds: sounds))

        let held = entries(note("Teams", "x", "@me"))
        XCTAssertEqual(try said(ofRuleAt: 0, in: data, over: held),
                       "Not in effect: this rule has problems, and will not run until they are fixed.")
        XCTAssertEqual(DryRun.report(forRuleAt: 1, in: rules, over: held, sounds: sounds).rows.map(\.verdict), [.matched])
        XCTAssertNil(try said(ofRuleAt: 1, in: data, over: held))
    }

    func testOnceTheFileIsSavedAndReadBackThereIsNothingLeftToSay() throws {
        // What the editor does after a save: it reads back what it wrote, at
        // the version the rules need.
        let before = file(version: 3, pagerJSON, mentionsJSON)
        let written = try RuleSetCodec.encode(try edited(before).rules)
        XCTAssertEqual(try edited(written).version, 4)
        XCTAssertEqual(namesInEffect(written), ["Pager", "Mentions"], "the loader runs both now")

        let held = entries(note("Teams", "x", "@me"))
        XCTAssertNil(try said(ofRuleAt: 0, in: written, over: held))
        XCTAssertNil(try said(ofRuleAt: 1, in: written, over: held))
    }

    func testTheSaveStateFollowsTheDraftTheFileAndWhatIsRunning() {
        let a = rule("A", app: "Teams"), broken = rule("Broken", app: "x", alert: .sound(name: "Glas", gainDB: 0))
        var brokenOff = broken
        brokenOff.isEnabled = false
        let isBroken: (Rule) -> Bool = { !RulesDocument.problems(in: $0, sounds: self.sounds, fileVersion: nil).isEmpty }

        XCTAssertEqual(EditorText.saveState(draft: [a, broken], saved: [a], fileIsInEffect: true, fileVersion: nil, broken: isBroken), .unsaved)
        XCTAssertEqual(EditorText.saveState(draft: [a], saved: [a], fileIsInEffect: false, fileVersion: nil, broken: isBroken), .fileNotInEffect)
        XCTAssertEqual(EditorText.saveState(draft: [a, broken], saved: [a, broken], fileIsInEffect: true, fileVersion: nil, broken: isBroken),
                       .inEffect(notRunning: 1))
        XCTAssertEqual(EditorText.saveState(draft: [a, brokenOff], saved: [a, brokenOff], fileIsInEffect: true, fileVersion: nil, broken: isBroken),
                       .inEffect(notRunning: 0), "a rule switched off is not expected to run")
    }

    func testTheSaveBarOnlySaysInEffectWhenItIs() {
        XCTAssertEqual(EditorText.saveState(.unsaved).text, EditorText.unsavedChanges)
        XCTAssertTrue(EditorText.saveState(.unsaved).isWarning)
        XCTAssertTrue(EditorText.saveState(.fileNotInEffect).isWarning,
                      "a file edited by hand and not reloaded is not what the app runs")
        XCTAssertTrue(EditorText.saveState(.fileNotInEffect).text.contains("not running"))
        XCTAssertEqual(EditorText.saveState(.inEffect(notRunning: 0)).text, "Saved and in effect")
        XCTAssertFalse(EditorText.saveState(.inEffect(notRunning: 0)).isWarning)
        XCTAssertEqual(EditorText.saveState(.inEffect(notRunning: 1)).text, "Saved and in effect — except that 1 rule has problems and does not run")
        XCTAssertEqual(EditorText.saveState(.inEffect(notRunning: 2)).text, "Saved and in effect — except that 2 rules have problems and do not run")
        XCTAssertTrue(EditorText.saveState(.inEffect(notRunning: 2)).isWarning)
    }

    func testEveryFieldAndOperatorHasItsOwnName() {
        XCTAssertEqual(Set(Field.allCases.map(EditorText.fieldName)).count, Field.allCases.count)
        XCTAssertEqual(Set(Operator.allCases.map(EditorText.operatorName)).count, Operator.allCases.count)
    }

    func testAConditionIsDescribedInWordsAndOnlyItsDisplayIsShortened() {
        XCTAssertEqual(EditorText.describe(.field(.title, .contains, "All Hands")), "Title contains “All Hands”")
        XCTAssertEqual(EditorText.describe(.field(.subtitle, .equals, "")), "Subtitle is empty")
        XCTAssertEqual(EditorText.describe(.field(.raw, .contains, "abcdefghij"), limit: 4), "Any text contains “abcd…”")
        XCTAssertEqual(EditorText.describe(.not(.field(.app, .equals, "Weather"))), "Not: App is “Weather”")
        XCTAssertEqual(EditorText.describe(.and([.blank, .blank])), "All of 2 conditions")
    }

    func testEachKindOfAlertSaysWhatItDoes() {
        XCTAssertNotEqual(EditorText.alertMeaning(nil), EditorText.alertMeaning(.silent),
                          "no alert and a silent alert must read differently")
        XCTAssertTrue(EditorText.alertMeaning(.silent).contains("no rule below"))
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

    func testARenameReadsAsARename() {
        let rename = RulesChange(file: .edited, added: [], removed: [], changed: [],
                                 renamed: [RulesChange.Rename(from: "Nested", to: "Nested (edited by hand)")])
        XCTAssertEqual(EditorText.conflictDetail(rename), "Renamed: “Nested” to “Nested (edited by hand)”.")
        let both = RulesChange(file: .edited, added: ["New"], removed: [], changed: ["B2"],
                               renamed: [RulesChange.Rename(from: "A", to: "A2"), RulesChange.Rename(from: "B", to: "B2")])
        XCTAssertEqual(EditorText.conflictDetail(both),
                       "Added: “New”. Renamed: “A” to “A2”, “B” to “B2”. Changed: “B2”.")
    }
}
