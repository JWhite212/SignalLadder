import XCTest
@testable import NotificationCore

/// What a burst adds to the words of the panel line, the status menu and the
/// Inspector (M5 plan, Task 5, Ruling 14, Ruling 18): how many matches one
/// escalation stands for, hidden at 1 so that an escalation no match has joined
/// reads as it always did, and what an Inspector row says of a match that joined
/// and played its own alert. All of it is pure, so each line is built from a
/// summary or a row and read as the app reads it. A count is "matches", never
/// "messages", and none of it says what arrived (M4 Ruling 17).
final class BurstTextTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    /// The start of the escalation is 10:42, and any other moment 10:45, as the
    /// existing tests of these lines read them.
    private func time(_ date: Date) -> String { date == t0 ? "10:42" : "10:45" }

    private func summary(_ status: EscalationSummary.Status = .live, matches: Int = 1, tier: Int = 3, repeats: Int = 3,
                         cap: Int? = 20, last: AlertOutcome? = nil, final: FinalOutcome? = nil) -> EscalationSummary {
        EscalationSummary(ruleName: "On-call mentions", startedAt: t0, status: status, tierReached: tier,
                          repeatCount: repeats, repeatCap: cap, lastRepeat: last, final: final, matchCount: matches)
    }

    private let allStatuses: [EscalationSummary.Status] = [
        .live,
        .capped(at: Date(timeIntervalSince1970: 1_790_000_100)),
        .acknowledged(at: Date(timeIntervalSince1970: 1_790_000_100)),
        .missedWhileAsleep(convertedAt: Date(timeIntervalSince1970: 1_790_000_000), acknowledgedAt: nil),
        .missedWhileAsleep(convertedAt: Date(timeIntervalSince1970: 1_790_000_000),
                           acknowledgedAt: Date(timeIntervalSince1970: 1_790_000_100)),
    ]

    // MARK: - The count

    func testACountOfMatchesIsSaidFromTwoAndNeverInTheSingular() {
        XCTAssertNil(BurstText.matches(1), "one match is what every escalation was: nothing to say")
        XCTAssertNil(BurstText.matches(0), "nor does a count below one say anything")
        XCTAssertNil(BurstText.matches(-1))
        XCTAssertEqual(BurstText.matches(2), "2 matches")
        XCTAssertEqual(BurstText.matches(7), "7 matches")
        XCTAssertEqual(BurstText.matches(20), "20 matches")
        XCTAssertEqual(BurstText.matches(1000), "1000 matches")
    }

    func testNoWordOfItSaysMessages() {
        for count in 2...40 {
            let words = (BurstText.matches(count) ?? "") + " " + BurstText.joinedEscalation(matchNumber: count)
            XCTAssertFalse(words.lowercased().contains("message"), words)
        }
    }

    func testTheEndOfAnAudibleJoinsLineNamesTheMatchNumberAndSaysNothingOfRepeating() {
        XCTAssertEqual(BurstText.joinedEscalation(matchNumber: 2), "joined an escalation (match 2)")
        XCTAssertEqual(BurstText.joinedEscalation(matchNumber: 3), "joined an escalation (match 3)")
        XCTAssertEqual(BurstText.joinedEscalation(matchNumber: 20), "joined an escalation (match 20)")
        XCTAssertFalse(BurstText.joinedEscalation(matchNumber: 3).contains("repeat"),
                       "a ladder with no repeat can be joined too, so it does not say that this one does")
    }

    // MARK: - The panel line

    private func panel(_ summary: EscalationSummary) -> String {
        EscalationPanelText.line(for: summary, time: time)
    }

    func testAnEscalationNoMatchHasJoinedReadsAsItAlwaysDid() {
        XCTAssertEqual(panel(summary()), "On-call mentions — since 10:42 — tier 3, repeat 3 of 20")
        XCTAssertEqual(panel(summary(tier: 2, repeats: 0)), "On-call mentions — since 10:42 — tier 2")
        XCTAssertEqual(panel(summary(.capped(at: t0), repeats: 20)),
                       "On-call mentions — since 10:42 — tier 3, repeat 20 of 20, no longer repeating")
        XCTAssertEqual(panel(summary(.missedWhileAsleep(convertedAt: t0, acknowledgedAt: nil))),
                       "On-call mentions — since 10:42 — missed while asleep")
        let built = EscalationSummary(ruleName: "On-call mentions", startedAt: t0, tierReached: 3, repeatCount: 3,
                                      repeatCap: 20)
        XCTAssertEqual(built.matchCount, 1, "a summary built without a count is a one-match escalation")
        XCTAssertEqual(panel(built), "On-call mentions — since 10:42 — tier 3, repeat 3 of 20")
    }

    func testTheCountIsSaidAfterTheStartTimeFromTwoMatches() {
        XCTAssertEqual(panel(summary(matches: 2)), "On-call mentions — since 10:42 — 2 matches — tier 3, repeat 3 of 20")
        XCTAssertEqual(panel(summary(matches: 7)), "On-call mentions — since 10:42 — 7 matches — tier 3, repeat 3 of 20")
        XCTAssertEqual(panel(summary(matches: 20)), "On-call mentions — since 10:42 — 20 matches — tier 3, repeat 3 of 20")
    }

    func testTheCountSitsInTheSamePlaceWhateverTheLineSaysAfterIt() {
        XCTAssertEqual(panel(summary(matches: 7, tier: 2, repeats: 0)), "On-call mentions — since 10:42 — 7 matches — tier 2")
        XCTAssertEqual(panel(summary(.capped(at: t0), matches: 7, repeats: 20)),
                       "On-call mentions — since 10:42 — 7 matches — tier 3, repeat 20 of 20, no longer repeating")
        XCTAssertEqual(panel(summary(.missedWhileAsleep(convertedAt: t0, acknowledgedAt: nil), matches: 7)),
                       "On-call mentions — since 10:42 — 7 matches — missed while asleep")
        XCTAssertEqual(panel(summary(.acknowledged(at: t0), matches: 7)),
                       "On-call mentions — since 10:42 — 7 matches — acknowledged")
        let failed = FinalOutcome.shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed")
        XCTAssertEqual(panel(summary(matches: 7, tier: 4, final: failed)),
                       "On-call mentions — since 10:42 — 7 matches — tier 4, repeat 3 of 20, its Shortcut failed")
    }

    func testThePanelLineSaysOneMatchNeverAndAMatchCountForEveryCountFromTwo() {
        for status in allStatuses {
            for count in 0...1 {
                XCTAssertFalse(panel(summary(status, matches: count)).contains("match"), "\(status), \(count)")
            }
            for count in 2...40 {
                let line = panel(summary(status, matches: count))
                XCTAssertTrue(line.contains(" — \(count) matches — "), "\(status), \(count): \(line)")
                XCTAssertFalse(line.lowercased().contains("message"), line)
            }
        }
    }

    // MARK: - The menu's line

    private func menu(_ listed: [EscalationSummary],
                      failure: CapturePipeline.ShortcutFailure? = nil) -> [String] {
        AlertMenuText.escalationLines(listed: listed, shortcutFailure: failure, time: time)
    }

    func testTheLineForOneEscalationIsTheStemItIsHeldToAndWithNoMatchJoinedItIsAllThereIs() {
        XCTAssertEqual(AlertMenuText.singleEscalatingStem, "1 alert escalating")
        XCTAssertEqual(menu([summary()]), [AlertMenuText.singleEscalatingStem])
        XCTAssertEqual(menu([summary()]), ["1 alert escalating"], "as it always read")
        XCTAssertFalse(AlertMenuText.singleEscalatingStem.contains("("), "the stem has no count in it")
    }

    func testTheLineForOneEscalationWithSeveralMatchesIsTheStemAndTheCountInBrackets() {
        for count in [2, 7, 20, 1000] {
            let lines = menu([summary(matches: count)])
            XCTAssertEqual(lines, ["\(AlertMenuText.singleEscalatingStem) (\(count) matches)"])
            XCTAssertTrue(lines[0].hasPrefix(AlertMenuText.singleEscalatingStem),
                          "the harness finds the line by its stem, which the count leaves in front")
        }
        XCTAssertEqual(menu([summary(matches: 7)]), ["1 alert escalating (7 matches)"])
    }

    func testTheMenuTotalsTheMatchesOfEverythingEscalatingWhenTheyOutnumberTheEscalations() {
        XCTAssertEqual(menu([summary(matches: 7), summary(matches: 4), summary(matches: 3)]),
                       ["3 alerts escalating (14 matches)"])
        XCTAssertEqual(menu([summary(matches: 2), summary(matches: 1)]), ["2 alerts escalating (3 matches)"])
        XCTAssertEqual(menu([summary(matches: 1), summary(matches: 1), summary(matches: 12)]),
                       ["3 alerts escalating (14 matches)"], "one burst among others is still counted")
    }

    func testTheMenuHasNoBracketsWhenEveryEscalationStandsForOneMatch() {
        XCTAssertEqual(menu([summary(), summary()]), ["2 alerts escalating"])
        XCTAssertEqual(menu([summary(), summary(), summary()]), ["3 alerts escalating"],
                       "three matches do not outnumber three escalations")
    }

    func testOnlyWhatIsStillEscalatingIsCountedAndTheMissedLineIsAsItWas() {
        let missedUnseen = summary(.missedWhileAsleep(convertedAt: t0, acknowledgedAt: nil), matches: 4)
        let missedSeen = summary(.missedWhileAsleep(convertedAt: t0, acknowledgedAt: t0 + 5), matches: 6)
        let listed = [summary(matches: 5), summary(.capped(at: t0), matches: 3), summary(.acknowledged(at: t0), matches: 9),
                      missedUnseen, missedSeen]
        XCTAssertEqual(menu(listed), ["2 alerts escalating (8 matches)", "1 alert missed while asleep"],
                       "a capped escalation is still escalating and counts; acknowledged and missed ones do not")
        XCTAssertEqual(menu([missedUnseen]), ["1 alert missed while asleep"], "nothing escalating, no count")
        XCTAssertEqual(menu([summary(.acknowledged(at: t0), matches: 9)]), [])
    }

    func testAFailedShortcutStillComesFirstAndTheCountDoesNotMoveIt() {
        let failure = CapturePipeline.ShortcutFailure(ruleName: "On-call mentions", shortcutName: "Page me", at: t0,
                                                      reason: "the Shortcut \"Page me\" is not installed")
        XCTAssertEqual(menu([summary(matches: 3)], failure: failure),
                       ["⚠︎ On-call mentions at 10:42: the Shortcut \"Page me\" is not installed",
                        "1 alert escalating (3 matches)"])
    }

    /// Whether a line says "1 match" as a number of its own, which "11 matches"
    /// does not.
    private func saysOneMatch(_ line: String) -> Bool {
        line.range(of: #"(?<![0-9])1 match\b"#, options: .regularExpression) != nil
    }

    func testTheMenusCountIsNeverTheSingularOrMessages() {
        for count in 1...40 {
            let line = menu([summary(matches: count)])[0]
            XCTAssertFalse(saysOneMatch(line), line)
            XCTAssertFalse(line.lowercased().contains("message"), line)
            XCTAssertEqual(line.contains("match"), count > 1, "\(count): \(line)")
        }
        XCTAssertTrue(saysOneMatch("a line that says 1 match"), "the check itself sees one")
        XCTAssertFalse(saysOneMatch("a line that says 11 matches"), "and is not fooled by eleven")
    }

    // MARK: - The Inspector's escalation line

    private func inspector(_ summary: EscalationSummary) -> String {
        InspectorRowText.escalation(summary, time: time)
    }

    func testTheFirstRowsLineSaysHowManyMatchesAfterItsStatusAndBeforeHowFarItGot() {
        XCTAssertEqual(inspector(summary(matches: 7)), "Escalating — 7 matches — reached tier 3 — repeated 3 of 20")
        XCTAssertEqual(inspector(summary(.capped(at: t0 + 3), matches: 7, repeats: 20)),
                       "Escalating, no longer repeating since 10:45 — 7 matches — reached tier 3 — repeated 20 of 20")
        XCTAssertEqual(inspector(summary(.acknowledged(at: t0 + 3), matches: 7)),
                       "Acknowledged at 10:45 — 7 matches — reached tier 3 — repeated 3 of 20")
        XCTAssertEqual(inspector(summary(.missedWhileAsleep(convertedAt: t0, acknowledgedAt: t0 + 3), matches: 7)),
                       "Missed while asleep, found on waking at 10:42, seen at 10:45 — 7 matches — reached tier 3 — repeated 3 of 20")
        let failed = FinalOutcome.shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed")
        XCTAssertEqual(inspector(summary(matches: 7, tier: 4, final: failed)),
                       "Escalating — 7 matches — reached tier 4 — repeated 3 of 20 — Shortcut did not run: the Shortcut \"Page me\" is not installed")
        XCTAssertEqual(inspector(summary(matches: 2, tier: 2, repeats: 0)), "Escalating — 2 matches — reached tier 2")
    }

    func testTheFirstRowsLineIsAsItAlwaysWasForAnEscalationOfOneMatch() {
        XCTAssertEqual(inspector(summary()), "Escalating — reached tier 3 — repeated 3 of 20")
        XCTAssertEqual(inspector(summary(.acknowledged(at: t0 + 3))), "Acknowledged at 10:45 — reached tier 3 — repeated 3 of 20")
        for status in allStatuses {
            for count in 0...1 {
                XCTAssertFalse(inspector(summary(status, matches: count)).contains("match"), "\(status), \(count)")
            }
            for count in 2...40 {
                let line = inspector(summary(status, matches: count))
                XCTAssertTrue(line.contains(" — \(count) matches — "), "\(status), \(count): \(line)")
                XCTAssertFalse(line.lowercased().contains("message"), line)
            }
        }
    }

    // MARK: - The Inspector's alert line for a row that joined

    private func row(_ outcome: AlertOutcome?, joined: Int?) -> InspectorEntry {
        var entry = InspectorEntry(
            captured: CapturedNotification(timestamp: t0, appNameGuess: "Teams", title: "Alex Example mentioned you",
                                           subtitle: "", body: "Placeholder body text",
                                           rawText: "Teams, Alex Example mentioned you, Placeholder body text",
                                           subrole: "AXNotificationCenterBanner"),
            context: ContextSnapshot(date: t0, recentCountForApp: 1), suppressedRepeatCount: 0)
        entry.alertOutcome = outcome
        entry.joinedMatch = joined
        return entry
    }

    func testAMatchThatJoinedAndStayedSilentKeepsItsOwnSentenceAndIsNotGivenItsNumberTwice() {
        XCTAssertEqual(InspectorRowText.alert(row(.joinedEscalation(matchNumber: 3), joined: 3)),
                       "Joined an escalation that repeats (match 3), no alert of its own")
        XCTAssertEqual(InspectorRowText.alert(row(.joinedEscalation(matchNumber: 20), joined: 20)),
                       "Joined an escalation that repeats (match 20), no alert of its own")
    }

    func testAMatchThatJoinedAndPlayedItsOwnAlertSaysWhatItDidAndThenWhichMatchItWas() {
        XCTAssertEqual(InspectorRowText.alert(row(.played(sound: "Glass", gainDB: 0, outputSilent: false), joined: 3)),
                       "Played Glass — joined an escalation (match 3)")
        XCTAssertEqual(InspectorRowText.alert(row(.played(sound: "Glass", gainDB: 6, outputSilent: false), joined: 2)),
                       "Played Glass (+6 dB) — joined an escalation (match 2)")
        XCTAssertEqual(InspectorRowText.alert(row(.played(sound: "Glass", gainDB: 0, outputSilent: true), joined: 4)),
                       "Played Glass — but the Mac's sound output was muted or at zero volume — joined an escalation (match 4)")
        XCTAssertEqual(InspectorRowText.alert(row(.spoke(text: "Alex Example mentioned you", voice: "Daniel", gainDB: 0,
                                                         outputSilent: false), joined: 3)),
                       "Spoke (Daniel) — joined an escalation (match 3)")
        XCTAssertEqual(InspectorRowText.alert(row(.playedAndSpoke(sound: "Glass", soundGainDB: 0, text: "x", voice: "Daniel",
                                                                  speechGainDB: 0, outputSilent: false), joined: 3)),
                       "Played Glass and spoke (Daniel) — joined an escalation (match 3)")
        XCTAssertEqual(InspectorRowText.alert(row(.failed("sound \"Glas\" was not found"), joined: 5)),
                       "Could not play: sound \"Glas\" was not found — joined an escalation (match 5)")
        XCTAssertEqual(InspectorRowText.alert(row(.silentByRule, joined: 3)), "Silent by rule — joined an escalation (match 3)")
        XCTAssertEqual(InspectorRowText.alert(row(.noAlertSet, joined: 3)),
                       "Silent — this rule has no alert — joined an escalation (match 3)")
    }

    /// One outcome of each case a join can record besides the silent join, whose
    /// sentence is its own.
    private var outcomesAJoinCanRecord: [AlertOutcome] {
        [
            .played(sound: "Glass", gainDB: 0, outputSilent: false),
            .played(sound: "Glass", gainDB: -3.5, outputSilent: true),
            .spoke(text: "Alex Example mentioned you", voice: "Daniel", gainDB: 0, outputSilent: false),
            .spoke(text: "Alex Example mentioned you", voice: "Daniel", gainDB: 0, outputSilent: true),
            .playedAndSpoke(sound: "Glass", soundGainDB: 0, text: "Alex Example mentioned you", voice: "Daniel",
                            speechGainDB: 0, outputSilent: false),
            .playedButNotSpoken(sound: "Glass", gainDB: 0, reason: "voice \"x\" is not installed", outputSilent: false),
            .spokeButNotPlayed(text: "Alex Example mentioned you", voice: "Daniel", gainDB: 0,
                               reason: "sound \"Glas\" was not found", outputSilent: false),
            .failed("sound \"Glass\" was not found"),
            .couldNotSpeak("voice \"x\" is not installed"),
            .silentByRule,
            .noAlertSet,
        ]
    }

    func testEveryOutcomeAJoinCanRecordKeepsItsOwnWordsAndEndsWithTheJoin() {
        for outcome in outcomesAJoinCanRecord {
            XCTAssertEqual(InspectorRowText.alert(row(outcome, joined: 6)),
                           InspectorRowText.alert(outcome) + " — joined an escalation (match 6)", "\(outcome)")
        }
    }

    func testARowThatJoinedNothingSaysWhatItsOutcomeSaysAndNothingOfJoining() {
        let others: [AlertOutcome] = [AlertOutcome.snoozed, AlertOutcome.joinedEscalation(matchNumber: 4)]
        for outcome in outcomesAJoinCanRecord + others {
            XCTAssertEqual(InspectorRowText.alert(row(outcome, joined: nil)), InspectorRowText.alert(outcome), "\(outcome)")
        }
        XCTAssertFalse(InspectorRowText.alert(row(.played(sound: "Glass", gainDB: 0, outputSilent: false), joined: nil))!
            .contains("joined"))
    }

    func testARowWithANumberAndNothingActedOnHasNoAlertLine() {
        XCTAssertNil(InspectorRowText.alert(row(nil, joined: 3)))
        XCTAssertNil(InspectorRowText.alert(row(nil, joined: nil)))
    }

    // MARK: - None of it holds what arrived

    private let fixtures = ["Alex Example", "Placeholder", "mentioned you"]

    /// A summary that carries notification text wherever it can: a spoken repeat,
    /// a spoken final alert and a failure are all in `final` or `last`, one at a time.
    private func summaries(_ status: EscalationSummary.Status, matches: Int) -> [EscalationSummary] {
        let spoken = AlertOutcome.spokeButNotPlayed(text: "Alex Example mentioned you", voice: "Daniel", gainDB: 0,
                                                    reason: "gone", outputSilent: false)
        let said = AlertOutcome.spoke(text: "Placeholder body text", voice: "Daniel", gainDB: 0, outputSilent: false)
        let failed = FinalOutcome.shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed")
        return [
            summary(status, matches: matches, last: spoken, final: .alerted(said)),
            summary(status, matches: matches, last: said, final: failed),
            summary(status, matches: matches, last: spoken, final: .shortcutLaunched(name: "Page me")),
        ]
    }

    func testNoLineOfThePanelTheMenuOrTheInspectorCarriesWhatArrivedForAnyStatusOrCount() {
        for status in allStatuses {
            for count in [1, 2, 7, 20] {
                for candidate in summaries(status, matches: count) {
                    let panelLine = panel(candidate)
                    let menuLines = menu([candidate]).joined(separator: "\n")
                    let inspectorLine = inspector(candidate)
                    for fixture in fixtures {
                        XCTAssertFalse(panelLine.contains(fixture), "\(status), \(count): \(panelLine)")
                        XCTAssertFalse(menuLines.contains(fixture), "\(status), \(count): \(menuLines)")
                        XCTAssertFalse(inspectorLine.contains(fixture), "\(status), \(count): \(inspectorLine)")
                    }
                    XCTAssertFalse(panelLine.contains("Daniel"), "the panel names no voice either: \(panelLine)")
                    XCTAssertFalse(menuLines.contains("Daniel"), "nor does the menu: \(menuLines)")
                }
            }
        }
    }

    func testNoAlertLineOfARowThatJoinedCarriesWhatWasSaid() {
        for outcome in outcomesAJoinCanRecord {
            let line = InspectorRowText.alert(row(outcome, joined: 3)) ?? ""
            for fixture in fixtures {
                XCTAssertFalse(line.contains(fixture), "\(outcome): \(line)")
            }
        }
        // What was said stays where it was: on its own line, for the Inspector alone.
        let spoke = AlertOutcome.spoke(text: "Alex Example mentioned you", voice: "Daniel", gainDB: 0, outputSilent: false)
        XCTAssertEqual(row(spoke, joined: 3).alertOutcome?.spokenText, "Alex Example mentioned you")
    }
}
