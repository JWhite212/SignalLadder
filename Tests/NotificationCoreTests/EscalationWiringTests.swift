import XCTest
@testable import NotificationCore

/// How a match starts its ladder, and what the pipeline, the menu and the
/// Inspector make of the ladder's progress (M4 Task 5). Fixtures are invented
/// text, never captured content (§10.1).
@MainActor
final class EscalationWiringTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    /// Each ladder started, with what the pipeline had recorded by then and what
    /// it handed over as tier 1's outcome.
    private var begun: [(rule: String, entry: UUID, lastMatch: CapturePipeline.LastMatch?,
                         failure: CapturePipeline.LastMatch?, row: AlertOutcome?, tier1: AlertOutcome,
                         notification: CapturedNotification)] = []
    private var soundAnswer: AlertOutcome = .played(sound: "Glass", gainDB: 0, outputSilent: false)

    override func setUp() {
        begun = []
        soundAnswer = .played(sound: "Glass", gainDB: 0, outputSilent: false)
    }

    private func pipeline(selfTest: String? = nil, history: CaptureRingBuffer = CaptureRingBuffer()) -> CapturePipeline {
        var p: CapturePipeline!
        p = CapturePipeline(ownAppName: "SignalLadder",
                            isSelfTest: { raw, _ in selfTest.map { raw.contains($0) } ?? false },
                            playSound: { [unowned self] _, _ in soundAnswer },
                            speak: { _, _ in .couldNotSpeak("unused") },
                            playAndSpeak: { _, _, _, _ in .couldNotSpeak("unused") },
                            beginEscalation: { [unowned self] rule, notification, entry, tier1 in
                                begun.append((rule.name, entry, p.lastMatch, p.unresolvedAlertFailure,
                                              p.history.entries.first { $0.id == entry }?.alertOutcome, tier1,
                                              notification))
                            },
                            holdForSnooze: { _ in false },
                            joinEscalation: { _, _ in nil },
                            history: history)
        return p
    }

    private let ladder = Escalation(tier3: RepeatAlert(action: .sound(name: "Hero", gainDB: 0)))

    private func escalating(_ name: String = "On-call mentions", app: String = "Microsoft Teams") -> Rule {
        Rule(name: name, condition: .field(.app, .equals, app), alert: .sound(name: "Glass", gainDB: 0), escalation: ladder)
    }

    @discardableResult
    private func feed(_ p: CapturePipeline, _ app: String, _ title: String, at offset: TimeInterval = 0) -> CapturePipeline.Outcome {
        p.process(RawCapture(timestamp: t0.addingTimeInterval(offset), rawText: "\(app), \(title), Placeholder body text",
                             subrole: "AXNotificationCenterBanner"),
                  textChildren: [title, "Placeholder body text"])
    }

    // MARK: - Starting the ladder

    func testAMatchWithALadderStartsItOnceFromItsRow() {
        let p = pipeline()
        p.setRules([escalating()])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        XCTAssertEqual(begun.map(\.rule), ["On-call mentions"])
        XCTAssertEqual(begun.first?.entry, p.history.entries.first?.id)
    }

    func testTheLadderIsHandedTheNotificationThatMatched() {
        // What tier 3 speaks and what the Shortcut is given.
        let p = pipeline()
        p.setRules([escalating()])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        let handed = begun.first?.notification
        XCTAssertEqual(handed, p.history.entries.first?.captured)
        XCTAssertEqual(handed?.appNameGuess, "Microsoft Teams")
        XCTAssertEqual(handed?.title, "Alex Example mentioned you")
        XCTAssertEqual(handed?.body, "Placeholder body text")
    }

    func testAMatchWithNoLadderStartsNothing() {
        let p = pipeline()
        p.setRules([Rule(name: "Plain", condition: .field(.app, .equals, "Microsoft Teams"), alert: .sound(name: "Glass", gainDB: 0))])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        XCTAssertEqual(begun.count, 0)
    }

    func testAPreviewARepeatOrTheAppsOwnTrafficStartsNothing() {
        let p = pipeline(selfTest: "canary-marker")
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        p.setRules([escalating()])
        XCTAssertEqual(begun.count, 0, "rules previewed against what was already captured never act")

        feed(p, "Microsoft Teams", "Second message", at: 10)
        feed(p, "Microsoft Teams", "Second message", at: 10.5)
        XCTAssertEqual(begun.count, 1, "a repeat inside dedupe's window is not a new match")

        feed(p, "Microsoft Teams", "canary-marker", at: 20)
        XCTAssertEqual(begun.count, 1)
    }

    func testTheAppsOwnAlarmsStartNothingEvenUnderACatchAllRule() {
        let p = pipeline()
        p.setRules([Rule(name: "Everything", condition: .field(.subrole, .equals, "AXNotificationCenterBanner"),
                         alert: .sound(name: "Glass", gainDB: 0), escalation: ladder)])
        feed(p, "SignalLadder", SelfNotification.blindTitle)
        XCTAssertEqual(begun.count, 0)
        feed(p, "Microsoft Teams", "Alex Example mentioned you", at: 10)
        XCTAssertEqual(begun.count, 1, "the same rule does start a ladder for anyone else's")
    }

    func testTheLadderStartsAfterTier1sOutcomeIsRecorded() {
        // The row, the last match and the glyph are complete before `begin`,
        // which records and redraws as it starts.
        let failed = AlertOutcome.failed("sound \"Glass\" was not found")
        soundAnswer = failed
        let p = pipeline()
        p.setRules([escalating()])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        let expected = CapturePipeline.LastMatch(ruleName: "On-call mentions", at: t0, alert: failed)
        XCTAssertEqual(begun.first?.lastMatch, expected)
        XCTAssertEqual(begun.first?.failure, expected)
        XCTAssertEqual(begun.first?.row, failed)
    }

    func testTheLadderIsHandedWhatTier1DidWhichIsTheRowsOwnOutcome() {
        // What a match that joins the ladder later will need to judge whether
        // anything audible has been heard from it (M5 plan, Ruling 14), given
        // by the pipeline and not read back from the row by the app.
        let answers: [AlertOutcome] = [
            AlertOutcome.played(sound: "Glass", gainDB: 0, outputSilent: false),
            AlertOutcome.played(sound: "Glass", gainDB: 0, outputSilent: true),
            AlertOutcome.failed("sound \"Glass\" was not found"),
        ]
        for answer in answers {
            begun = []
            soundAnswer = answer
            let p = pipeline()
            p.setRules([escalating()])
            feed(p, "Microsoft Teams", "Alex Example mentioned you")
            XCTAssertEqual(begun.count, 1, "\(answer)")
            XCTAssertEqual(begun.first?.tier1, answer)
            XCTAssertEqual(begun.first?.tier1, begun.first?.row, "the row's own outcome")
        }
        func handedOver(by alert: AlertAction?, is expected: AlertOutcome) {
            begun = []
            let p = pipeline()
            p.setRules([Rule(name: "Quiet", condition: .field(.app, .equals, "Microsoft Teams"), alert: alert,
                             escalation: ladder)])
            feed(p, "Microsoft Teams", "Alex Example mentioned you")
            XCTAssertEqual(begun.first?.tier1, expected, "a rule that makes no sound still hands over what it did")
            XCTAssertEqual(begun.first?.row, expected)
        }
        handedOver(by: AlertAction.silent, is: AlertOutcome.silentByRule)
        handedOver(by: nil, is: AlertOutcome.noAlertSet)
    }

    // MARK: - Recording the ladder's progress

    private func summary(repeats: Int, last: AlertOutcome?, status: EscalationSummary.Status = .live,
                         final: FinalOutcome? = nil) -> EscalationSummary {
        EscalationSummary(ruleName: "On-call mentions", startedAt: t0, status: status, tierReached: 3,
                          repeatCount: repeats, repeatCap: 20, lastRepeat: last, final: final)
    }

    private func recorded() -> (CapturePipeline, UUID) {
        let p = pipeline()
        p.setRules([escalating()])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        return (p, p.history.entries[0].id)
    }

    func testTheSummaryIsWrittenOnTheRow() {
        let (p, row) = recorded()
        let s = summary(repeats: 1, last: .played(sound: "Hero", gainDB: 0, outputSilent: false))
        p.recordEscalation(entryID: row, s, at: t0)
        XCTAssertEqual(p.history.entries[0].escalation, s)
    }

    func testAFailedRepeatIsHeldUntilARepeatPlays() {
        let (p, row) = recorded()
        p.recordEscalation(entryID: row, summary(repeats: 1, last: .failed("sound \"Hero\" was not found")), at: t0 + 30)
        XCTAssertEqual(p.unresolvedAlertFailure?.alert, .failed("sound \"Hero\" was not found"))
        XCTAssertEqual(p.unresolvedAlertFailure?.at, t0 + 30)
        p.recordEscalation(entryID: row, summary(repeats: 2, last: .played(sound: "Hero", gainDB: 0, outputSilent: false)), at: t0 + 60)
        XCTAssertNil(p.unresolvedAlertFailure)
    }

    func testARepeatRecordedAgainIsNotFoldedAgain() {
        // Recorded on every change: a cap or acknowledgement carries the last
        // repeat's outcome still, and must not set a failure again once a
        // later sound has cleared it.
        let (p, row) = recorded()
        p.recordEscalation(entryID: row, summary(repeats: 1, last: .failed("gone")), at: t0 + 30)
        feed(p, "Microsoft Teams", "Another mention", at: 40)   // tier 1 plays, and clears it
        XCTAssertNil(p.unresolvedAlertFailure)
        p.recordEscalation(entryID: row, summary(repeats: 1, last: .failed("gone"), status: .acknowledged(at: t0 + 45)), at: t0 + 45)
        XCTAssertNil(p.unresolvedAlertFailure)
    }

    func testARepeatNeverChangesTheLastMatch() {
        let (p, row) = recorded()
        let before = p.lastMatch
        p.recordEscalation(entryID: row, summary(repeats: 1, last: .played(sound: "Hero", gainDB: 0, outputSilent: false)), at: t0 + 30)
        XCTAssertEqual(p.lastMatch, before)
    }

    func testAFailedShortcutOutlivesAPlayedRepeatAndClearsOnlyWhenOneLaunches() {
        let (p, row) = recorded()
        p.recordEscalation(entryID: row, summary(repeats: 3, last: .played(sound: "Hero", gainDB: 0, outputSilent: false),
                                                  final: .shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed")),
                           at: t0 + 120)
        XCTAssertEqual(p.unresolvedShortcutFailure,
                       CapturePipeline.ShortcutFailure(ruleName: "On-call mentions", shortcutName: "Page me", at: t0 + 120,
                                                       reason: "the Shortcut \"Page me\" is not installed"))
        p.recordEscalation(entryID: row, summary(repeats: 4, last: .played(sound: "Hero", gainDB: 0, outputSilent: false),
                                                  final: .shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed")),
                           at: t0 + 150)
        XCTAssertEqual(p.unresolvedShortcutFailure?.at, t0 + 120,
                       "a repeat playing says nothing about the phone, and the failure is folded once")

        feed(p, "Microsoft Teams", "Later mention", at: 200)
        let later = p.history.entries[0].id
        p.recordEscalation(entryID: later, summary(repeats: 0, last: nil, final: .shortcutLaunched(name: "Page me")), at: t0 + 330)
        XCTAssertNil(p.unresolvedShortcutFailure)
    }

    func testAFailedFinalAlertIsHeldLikeTier1sAndFoldedOnce() {
        let (p, row) = recorded()
        p.recordEscalation(entryID: row, summary(repeats: 0, last: nil, final: .alerted(.failed("gone"))), at: t0 + 120)
        XCTAssertEqual(p.unresolvedAlertFailure?.alert, .failed("gone"))
        feed(p, "Microsoft Teams", "Another mention", at: 130)
        XCTAssertNil(p.unresolvedAlertFailure)
        p.recordEscalation(entryID: row, summary(repeats: 0, last: nil, status: .acknowledged(at: t0 + 140),
                                                  final: .alerted(.failed("gone"))), at: t0 + 140)
        XCTAssertNil(p.unresolvedAlertFailure, "folded once, when first set")
    }

    func testARowPushedOutOfTheHistoryDoesNotBringBackAClearedFailure() {
        // A busy channel can age a row out while its ladder still runs; what
        // was folded from it is kept until the ladder is retired.
        let p = pipeline(history: CaptureRingBuffer(capacity: 2))
        p.setRules([escalating()])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        let row = p.history.entries[0].id
        p.recordEscalation(entryID: row, summary(repeats: 1, last: .failed("gone")), at: t0 + 30)
        feed(p, "Microsoft Teams", "Second mention", at: 40)
        feed(p, "Microsoft Teams", "Third mention", at: 50)
        XCTAssertFalse(p.history.entries.contains { $0.id == row }, "aged out")
        XCTAssertNil(p.unresolvedAlertFailure, "cleared by a later tier 1")

        p.recordEscalation(entryID: row, summary(repeats: 1, last: .failed("gone"), status: .acknowledged(at: t0 + 60)), at: t0 + 60)
        XCTAssertNil(p.unresolvedAlertFailure)
    }

    func testANewRepeatOnAnAgedOutRowIsStillFolded() {
        let p = pipeline(history: CaptureRingBuffer(capacity: 1))
        p.setRules([escalating()])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        let row = p.history.entries[0].id
        feed(p, "Microsoft Teams", "Second mention", at: 10)
        p.recordEscalation(entryID: row, summary(repeats: 1, last: .failed("gone")), at: t0 + 30)
        XCTAssertEqual(p.unresolvedAlertFailure?.alert, .failed("gone"), "the glyph still warns")
    }

    func testARetiredEscalationIsForgotten() {
        let (p, row) = recorded()
        p.recordEscalation(entryID: row, summary(repeats: 1, last: .failed("gone")), at: t0 + 30)
        feed(p, "Microsoft Teams", "Another mention", at: 40)
        p.escalationRetired(entryID: row)
        // Nothing is recorded for a retired escalation; were it, it would be
        // news again.
        p.recordEscalation(entryID: row, summary(repeats: 1, last: .failed("gone")), at: t0 + 50)
        XCTAssertEqual(p.unresolvedAlertFailure?.at, t0 + 50)
    }

    func testARetiredEscalationsFinalOutcomeIsForgottenToo() {
        let (p, row) = recorded()
        let failed = FinalOutcome.shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed")
        p.recordEscalation(entryID: row, summary(repeats: 0, last: nil, final: failed), at: t0 + 30)
        p.escalationRetired(entryID: row)
        p.recordEscalation(entryID: row, summary(repeats: 0, last: nil, final: failed), at: t0 + 50)
        XCTAssertEqual(p.unresolvedShortcutFailure?.at, t0 + 50, "folded afresh: nothing of it was kept")

        let (q, other) = recorded()
        q.recordEscalation(entryID: other, summary(repeats: 0, last: nil, final: .alerted(.failed("gone"))), at: t0 + 30)
        feed(q, "Microsoft Teams", "Another mention", at: 40)
        q.escalationRetired(entryID: other)
        q.recordEscalation(entryID: other, summary(repeats: 0, last: nil, final: .alerted(.failed("gone"))), at: t0 + 50)
        XCTAssertEqual(q.unresolvedAlertFailure?.at, t0 + 50)
    }

    // MARK: - The held Shortcut failure, and what clears it

    private let notInstalled = "the Shortcut \"Page me\" is not installed"

    /// A rule whose last step runs `shortcut`.
    private func paging(_ shortcut: String = "Page me", enabled: Bool = true, id: UUID = UUID()) -> Rule {
        Rule(id: id, name: "On-call mentions", condition: .field(.app, .equals, "Microsoft Teams"), isEnabled: enabled,
             alert: .sound(name: "Glass", gainDB: 0),
             escalation: Escalation(tier4: FinalAlert(afterSeconds: 60, action: .shortcut(name: shortcut))))
    }

    private func shortcutOutcome(_ outcome: FinalOutcome, status: EscalationSummary.Status = .live) -> EscalationSummary {
        summary(repeats: 0, last: nil, status: status, final: outcome)
    }

    /// A pipeline holding a failure of the Shortcut "Page me", with the row it
    /// came from and the summary that reported it.
    private func holdingAFailure(rules: [Rule]? = nil) -> (pipeline: CapturePipeline, row: UUID, failed: EscalationSummary) {
        let p = pipeline()
        p.setRules(rules ?? [paging()])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        let row = p.history.entries[0].id
        let failed = shortcutOutcome(.shortcutFailed(name: "Page me", reason: notInstalled))
        p.recordEscalation(entryID: row, failed, at: t0 + 60)
        XCTAssertEqual(p.unresolvedShortcutFailure?.shortcutName, "Page me", "the failure is held to begin with")
        return (p, row, failed)
    }

    func testAFailureNamesTheShortcutThatDidNotRun() {
        // From what the escalation reported, and not from the rule, which can
        // be reloaded under it, nor from the reason's wording.
        let p = pipeline()
        p.setRules([paging("Page me")])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        p.recordEscalation(entryID: p.history.entries[0].id,
                           shortcutOutcome(.shortcutFailed(name: "Wake the phone", reason: "it could not be started")),
                           at: t0 + 60)
        XCTAssertEqual(p.unresolvedShortcutFailure,
                       CapturePipeline.ShortcutFailure(ruleName: "On-call mentions", shortcutName: "Wake the phone",
                                                       at: t0 + 60, reason: "it could not be started"))
    }

    func testATestThatStartedTheSameShortcutClearsItsFailure() {
        let (p, _, _) = holdingAFailure()
        p.shortcutStartedInTest(named: "Page me")
        XCTAssertNil(p.unresolvedShortcutFailure)
    }

    func testATestThatStartedAnotherShortcutClearsNothing() {
        // A launch of B is no evidence about A: saying so would tell the menu
        // that a page which did not reach the phone is fixed.
        let (p, _, _) = holdingAFailure()
        let held = p.unresolvedShortcutFailure
        p.shortcutStartedInTest(named: "Page the team")
        XCTAssertEqual(p.unresolvedShortcutFailure, held)
    }

    func testOnlyTheSameNameExactlyClearsAFailure() {
        // Whether the Shortcuts app forgives a difference in capitals was not
        // measured, so a different spelling is a different Shortcut.
        let (p, _, _) = holdingAFailure()
        let held = p.unresolvedShortcutFailure
        for other in ["page me", "PAGE ME", "Page me ", " Page me", "Page  me", ""] {
            p.shortcutStartedInTest(named: other)
            XCTAssertEqual(p.unresolvedShortcutFailure, held, "\"\(other)\"")
        }
        p.shortcutStartedInTest(named: "Page me")
        XCTAssertNil(p.unresolvedShortcutFailure)
    }

    func testATestWithNothingHeldChangesNothing() {
        // Not even a sound that did not play, which is held on its own account.
        soundAnswer = .failed("sound \"Glass\" was not found")
        let p = pipeline()
        p.setRules([paging()])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        let failure = p.unresolvedAlertFailure
        let last = p.lastMatch
        XCTAssertNotNil(failure)
        XCTAssertNil(p.unresolvedShortcutFailure)

        p.shortcutStartedInTest(named: "Page me")
        XCTAssertNil(p.unresolvedShortcutFailure)
        XCTAssertEqual(p.unresolvedAlertFailure, failure, "a Shortcut starting says nothing about a sound")
        XCTAssertEqual(p.lastMatch, last)
        XCTAssertEqual(p.captureCount, 1)
    }

    /// A pipeline holding a sound that did not play and, from a row after it,
    /// a Shortcut that did not run: the two failures are held apart, so that
    /// clearing the one can be seen not to clear the other.
    private func holdingASoundFailureAndAShortcutFailure() throws -> (pipeline: CapturePipeline, sound: CapturePipeline.LastMatch,
                                                                     last: CapturePipeline.LastMatch) {
        soundAnswer = .failed("sound \"Glass\" was not found")
        let (p, _, _) = holdingAFailure()
        // The match after the failed Shortcut, whose sound fails again, so that
        // what is held and what is last are the later match's and differ from
        // the earlier one's.
        feed(p, "Microsoft Teams", "Later mention", at: 200)
        let held = try XCTUnwrap(p.unresolvedAlertFailure)
        let last = try XCTUnwrap(p.lastMatch)
        XCTAssertEqual(held.at, t0 + 200)
        XCTAssertEqual(last, held, "the sound failure is the last match, to begin with")
        XCTAssertEqual(p.unresolvedShortcutFailure?.shortcutName, "Page me", "the Shortcut failure is still held")
        return (p, held, last)
    }

    func testClearingAShortcutFailureFromATestLeavesASoundFailureAndTheLastMatchAlone() throws {
        // The reverse of the held-apart rule: a Shortcut working is evidence
        // about that Shortcut and about no sound, and a test in the editor is
        // no match, so what the menu says about either must not move.
        let (p, sound, last) = try holdingASoundFailureAndAShortcutFailure()
        let captures = p.captureCount

        p.shortcutStartedInTest(named: "Page me")

        XCTAssertNil(p.unresolvedShortcutFailure, "the Shortcut's own failure goes")
        XCTAssertEqual(p.unresolvedAlertFailure, sound, "a Shortcut starting says nothing about a sound")
        XCTAssertEqual(p.lastMatch, last, "a test is not a match")
        XCTAssertEqual(p.captureCount, captures)
    }

    func testClearingAShortcutFailureByItsLaunchLeavesASoundFailureAndTheLastMatchAlone() throws {
        // The same through a launch the escalation reports, which is the
        // path that clears it in practice.
        let (p, sound, last) = try holdingASoundFailureAndAShortcutFailure()
        let captures = p.captureCount

        p.recordEscalation(entryID: p.history.entries[0].id, shortcutOutcome(.shortcutLaunched(name: "Page me")),
                           at: t0 + 330)

        XCTAssertNil(p.unresolvedShortcutFailure, "the Shortcut's own failure goes")
        XCTAssertEqual(p.unresolvedAlertFailure, sound, "a Shortcut launching says nothing about a sound")
        XCTAssertEqual(p.lastMatch, last, "an escalation's outcome never changes the last match")
        XCTAssertEqual(p.captureCount, captures)
    }

    func testAClearedFailureIsNotBroughtBackByTheSameSummaryRecordedAgain() {
        // Recorded on every change: an acknowledgement carries the final
        // outcome still, and must not hold a failure again once a launch
        // has cleared it.
        let (p, row, failed) = holdingAFailure()
        let line = { AlertMenuText.escalationLines(listed: [], shortcutFailure: p.unresolvedShortcutFailure,
                                                   time: { _ in "10:42" }) }
        XCTAssertEqual(line(), ["⚠︎ On-call mentions at 10:42: \(notInstalled)"])

        p.shortcutStartedInTest(named: "Page me")
        XCTAssertNil(p.unresolvedShortcutFailure)
        XCTAssertEqual(line(), [], "the menu's line goes with it")

        p.recordEscalation(entryID: row, failed, at: t0 + 70)
        var acknowledged = failed
        acknowledged.status = .acknowledged(at: t0 + 80)
        p.recordEscalation(entryID: row, acknowledged, at: t0 + 80)
        XCTAssertNil(p.unresolvedShortcutFailure)
        XCTAssertEqual(line(), [])
    }

    func testALaunchOfAnotherShortcutFromAnEscalationClearsNothing() {
        let (p, _, _) = holdingAFailure()
        let held = p.unresolvedShortcutFailure
        feed(p, "Microsoft Teams", "Later mention", at: 200)
        let later = p.history.entries[0].id
        p.recordEscalation(entryID: later, shortcutOutcome(.shortcutLaunched(name: "Page the team")), at: t0 + 330)
        XCTAssertEqual(p.unresolvedShortcutFailure, held)

        feed(p, "Microsoft Teams", "Latest mention", at: 400)
        p.recordEscalation(entryID: p.history.entries[0].id, shortcutOutcome(.shortcutLaunched(name: "Page me")), at: t0 + 530)
        XCTAssertNil(p.unresolvedShortcutFailure, "its own Shortcut launching does")
    }

    func testReloadingTheRulesClearsNoFailure() {
        // The default (O15b): nothing but a launch of that Shortcut clears it,
        // so a reload that renames it, deletes its rule or switches the rule
        // off leaves the line and the slashed bell where they were.
        let id = UUID()
        let cases: [(String, [Rule])] = [
            ("the same rules", [paging(id: id)]),
            ("a rule that names another Shortcut", [paging("Page me now", id: id)]),
            ("a rule that names no Shortcut", [Rule(id: id, name: "On-call mentions",
                                                    condition: .field(.app, .equals, "Microsoft Teams"),
                                                    alert: .sound(name: "Glass", gainDB: 0))]),
            ("the rule switched off", [paging(enabled: false, id: id)]),
            ("the rule deleted", []),
            ("another rule only", [Rule(name: "Mail", condition: .field(.app, .equals, "Mail"),
                                        alert: .sound(name: "Glass", gainDB: 0))]),
        ]
        for (what, reloaded) in cases {
            let (p, _, _) = holdingAFailure(rules: [paging(id: id)])
            let held = p.unresolvedShortcutFailure
            p.setRules(reloaded)
            XCTAssertEqual(p.unresolvedShortcutFailure, held, what)
        }
    }

    func testAFailureSurvivesAReloadOfARuleWithNoIdInTheFile() throws {
        // A rule with no `id` in the file gets a new one at every load. Were a
        // failure keyed on the rule's id, a reload would clear a real failure
        // and announce a fix nobody made.
        let file = Data("""
        {"version": 4, "rules": [{"name": "On-call mentions",
          "condition": {"field": "app", "op": "equals", "value": "Microsoft Teams"},
          "alert": {"sound": "Glass"},
          "escalation": {"tier4": {"afterSeconds": 60, "shortcut": "Page me"}}}]}
        """.utf8)
        let first = try RuleSetCodec.decode(file)
        let second = try RuleSetCodec.decode(file)
        XCTAssertEqual(first.problems, [])
        XCTAssertNotEqual(first.rules[0].id, second.rules[0].id, "each load mints its own")

        let (p, _, _) = holdingAFailure(rules: first.rules)
        let held = p.unresolvedShortcutFailure
        p.setRules(second.rules)
        XCTAssertEqual(p.unresolvedShortcutFailure, held)
    }

    // MARK: - The menu's words

    private func menu(_ listed: [EscalationSummary], _ failure: CapturePipeline.ShortcutFailure? = nil) -> [String] {
        AlertMenuText.escalationLines(listed: listed, shortcutFailure: failure, time: { _ in "10:42" })
    }

    func testTheMenuCountsWhatIsEscalatingAndWhatWasMissed() {
        let live = summary(repeats: 1, last: nil)
        let missed = summary(repeats: 1, last: nil, status: .missedWhileAsleep(convertedAt: t0, acknowledgedAt: nil))
        XCTAssertEqual(menu([live]), ["1 alert escalating"])
        XCTAssertEqual(menu([live, summary(repeats: 2, last: nil, status: .capped(at: t0)), missed]),
                       ["2 alerts escalating", "1 alert missed while asleep"])
        XCTAssertEqual(menu([]), [])
    }

    func testAMissAlreadySeenIsNotCountedAgain() {
        let seen = summary(repeats: 1, last: nil, status: .missedWhileAsleep(convertedAt: t0, acknowledgedAt: t0 + 5))
        let unseen = summary(repeats: 1, last: nil, status: .missedWhileAsleep(convertedAt: t0, acknowledgedAt: nil))
        XCTAssertEqual(menu([seen, unseen, summary(repeats: 1, last: nil, status: .acknowledged(at: t0))]),
                       ["1 alert missed while asleep"])
    }

    func testAFailedShortcutComesFirst() {
        let failure = CapturePipeline.ShortcutFailure(ruleName: "On-call mentions", shortcutName: "Page me", at: t0,
                                                      reason: "the Shortcut \"Page me\" is not installed")
        XCTAssertEqual(menu([summary(repeats: 1, last: nil)], failure),
                       ["⚠︎ On-call mentions at 10:42: the Shortcut \"Page me\" is not installed", "1 alert escalating"])
    }

    func testTheMenuNeverSaysWhatArrived() {
        let spoken = AlertOutcome.spoke(text: "Alex Example mentioned you", voice: "Daniel", gainDB: 0, outputSilent: false)
        let lines = menu([summary(repeats: 1, last: spoken, final: .alerted(spoken))])
        XCTAssertFalse(lines.joined().contains("Alex Example"), "\(lines)")
    }

    func testAcknowledgeWording() {
        XCTAssertEqual(AlertMenuText.acknowledgeTitle(listed: 1), "Acknowledge")
        XCTAssertEqual(AlertMenuText.acknowledgeTitle(listed: 3), "Acknowledge All (3)")
    }

    func testAFailedShortcutIsStillSaidWithNothingListed() {
        // Once the escalation whose Shortcut failed is acknowledged, this
        // line is the only thing saying why the bell is slashed.
        let failure = CapturePipeline.ShortcutFailure(ruleName: "On-call mentions", shortcutName: "Page me", at: t0,
                                                      reason: "the Shortcut \"Page me\" is not installed")
        XCTAssertEqual(menu([], failure), ["⚠︎ On-call mentions at 10:42: the Shortcut \"Page me\" is not installed"])
    }

    // MARK: - The Inspector's words

    private func row(_ summary: EscalationSummary) -> String {
        InspectorRowText.escalation(summary, time: { $0 == self.t0 ? "10:42" : "10:45" })
    }

    func testTheInspectorSaysWhereTheLadderGot() {
        XCTAssertEqual(row(summary(repeats: 3, last: .played(sound: "Hero", gainDB: 0, outputSilent: false))),
                       "Escalating — reached tier 3 — repeated 3 of 20")
        XCTAssertEqual(row(summary(repeats: 20, last: nil, status: .capped(at: t0 + 1))),
                       "Escalating, no longer repeating since 10:45 — reached tier 3 — repeated 20 of 20")
        XCTAssertEqual(row(summary(repeats: 3, last: nil, status: .acknowledged(at: t0 + 1))),
                       "Acknowledged at 10:45 — reached tier 3 — repeated 3 of 20")
        XCTAssertEqual(row(summary(repeats: 3, last: nil, status: .missedWhileAsleep(convertedAt: t0, acknowledgedAt: t0 + 1))),
                       "Missed while asleep, found on waking at 10:42, seen at 10:45 — reached tier 3 — repeated 3 of 20")
    }

    func testTheInspectorSaysWhatALaterTierFailedToDo() {
        XCTAssertEqual(row(summary(repeats: 1, last: .failed("sound \"Hero\" was not found"))),
                       "Escalating — reached tier 3 — repeated 1 of 20 — last repeat: Could not play: sound \"Hero\" was not found")
        XCTAssertEqual(row(summary(repeats: 0, last: nil, final: .shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed"))),
                       "Escalating — reached tier 3 — Shortcut did not run: the Shortcut \"Page me\" is not installed")
        XCTAssertEqual(row(summary(repeats: 0, last: nil, final: .shortcutLaunched(name: "Page me"))),
                       "Escalating — reached tier 3 — Shortcut “Page me” started")
    }

    func testTheInspectorsLadderLineNeverSaysWhatWasSpoken() {
        let spoken = AlertOutcome.spokeButNotPlayed(text: "Alex Example mentioned you", voice: "Daniel", gainDB: 0,
                                                    reason: "gone", outputSilent: false)
        let line = row(summary(repeats: 1, last: spoken, final: .alerted(spoken)))
        XCTAssertFalse(line.contains("Alex Example"), line)
    }

    func testTheInspectorSaysAMissStillToBeSeenAndARepeatWithNoLimit() {
        XCTAssertEqual(row(summary(repeats: 3, last: nil, status: .missedWhileAsleep(convertedAt: t0, acknowledgedAt: nil))),
                       "Missed while asleep, found on waking at 10:42 — reached tier 3 — repeated 3 of 20")
        var uncapped = summary(repeats: 3, last: nil)
        uncapped.repeatCap = nil
        XCTAssertEqual(row(uncapped), "Escalating — reached tier 3 — repeated 3")
        XCTAssertEqual(row(summary(repeats: 0, last: nil, final: .alerted(.played(sound: "Hero", gainDB: 0, outputSilent: false)))),
                       "Escalating — reached tier 3 — final alert: Played Hero")
    }

    func testTheInspectorWarnsExactlyWhenItsLineReportsAFailure() {
        let played = AlertOutcome.played(sound: "Hero", gainDB: 0, outputSilent: false)
        XCTAssertFalse(summary(repeats: 2, last: played).needsAttention)
        XCTAssertTrue(summary(repeats: 2, last: .failed("gone")).needsAttention)
        XCTAssertTrue(summary(repeats: 2, last: .played(sound: "Hero", gainDB: 0, outputSilent: true)).needsAttention,
                      "sounded into a muted output")
        XCTAssertTrue(summary(repeats: 0, last: nil, final: .alerted(.failed("gone"))).needsAttention)
        XCTAssertFalse(summary(repeats: 0, last: nil, final: .alerted(played)).needsAttention)
        XCTAssertTrue(summary(repeats: 0, last: nil, final: .shortcutFailed(name: "Page me", reason: "x")).needsAttention)
        XCTAssertFalse(summary(repeats: 0, last: nil, final: .shortcutLaunched(name: "Page me")).needsAttention)
        XCTAssertFalse(summary(repeats: 1, last: nil, status: .missedWhileAsleep(convertedAt: t0, acknowledgedAt: nil)).needsAttention,
                       "a miss is not a failure of anything")
    }

    // MARK: - Whose sound acknowledging stops

    func testAnAlertThatNeverReachedThePlayerLeavesItsOwnerAlone() {
        var owner = PlayerOwnership()
        owner.alertSetOff(.played(sound: "Glass", gainDB: 0, outputSilent: false), byEscalation: false)
        owner.alertSetOff(.failed("sound \"Hero\" was not found"), byEscalation: true)
        XCTAssertFalse(owner.escalationOwnsIt, "an ordinary alert still playing must not be cut off")

        owner.alertSetOff(.played(sound: "Hero", gainDB: 0, outputSilent: false), byEscalation: true)
        owner.alertSetOff(.couldNotSpeak("no voice"), byEscalation: false)
        owner.alertSetOff(.silentByRule, byEscalation: false)
        owner.alertSetOff(.noAlertSet, byEscalation: false)
        XCTAssertTrue(owner.escalationOwnsIt, "the escalation's sound is still what plays")
    }

    func testAMatchASnoozeHeldNeverReachedThePlayerAndLeavesItsOwnerAlone() {
        XCTAssertFalse(AlertOutcome.snoozed.tookThePlayer)

        var escalating = PlayerOwnership()
        escalating.alertSetOff(.played(sound: "Hero", gainDB: 0, outputSilent: false), byEscalation: true)
        escalating.alertSetOff(.snoozed, byEscalation: false)
        XCTAssertTrue(escalating.escalationOwnsIt, "the escalation's sound is still what plays")

        var ordinary = PlayerOwnership()
        ordinary.alertSetOff(.played(sound: "Glass", gainDB: 0, outputSilent: false), byEscalation: false)
        ordinary.alertSetOff(.snoozed, byEscalation: true)
        XCTAssertFalse(ordinary.escalationOwnsIt, "and an ordinary alert still playing is not made an escalation's")
    }

    func testAMatchThatJoinedAnEscalationAndStayedSilentNeverReachedThePlayerAndLeavesItsOwnerAlone() {
        // Its repeat is what plays, and the coordinator played that. Nothing of its
        // own went near the player, so whose sound it is does not change (M5 plan,
        // Ruling 14).
        let silentJoin = AlertOutcome.joinedEscalation(matchNumber: 3)
        XCTAssertFalse(silentJoin.tookThePlayer)

        var escalating = PlayerOwnership()
        escalating.alertSetOff(.played(sound: "Hero", gainDB: 0, outputSilent: false), byEscalation: true)
        escalating.alertSetOff(silentJoin, byEscalation: false)
        XCTAssertTrue(escalating.escalationOwnsIt, "the escalation's sound is still what plays")

        var ordinary = PlayerOwnership()
        ordinary.alertSetOff(.played(sound: "Glass", gainDB: 0, outputSilent: false), byEscalation: false)
        ordinary.alertSetOff(silentJoin, byEscalation: true)
        XCTAssertFalse(ordinary.escalationOwnsIt, "and an ordinary alert still playing is not made an escalation's")
    }

    func testAnyAlertThatStartedTakesThePlayer() {
        let started: [AlertOutcome] = [
            .played(sound: "Hero", gainDB: 0, outputSilent: false),
            .spoke(text: "x", voice: "Daniel", gainDB: 0, outputSilent: false),
            .playedAndSpoke(sound: "Hero", soundGainDB: 0, text: "x", voice: "Daniel", speechGainDB: 0, outputSilent: false),
            .playedButNotSpoken(sound: "Hero", gainDB: 0, reason: "x", outputSilent: false),
            .spokeButNotPlayed(text: "x", voice: "Daniel", gainDB: 0, reason: "x", outputSilent: false),
        ]
        for outcome in started {
            var owner = PlayerOwnership()
            owner.alertSetOff(outcome, byEscalation: true)
            XCTAssertTrue(owner.escalationOwnsIt, "\(outcome)")
            owner.alertSetOff(outcome, byEscalation: false)
            XCTAssertFalse(owner.escalationOwnsIt, "\(outcome)")
        }
    }

    // MARK: - The pipeline and the coordinator together, as the app wires them

    private var clock = ManualScheduler()
    private var sounds: [String: AlertOutcome] = [:]
    private var spokenLines: [String] = []
    /// Each run of a Shortcut: the notification whose fields it was given, the
    /// report a test delivers, and the Shortcut's name and the awake time it
    /// started at.
    private var shortcutRuns: [(fields: CapturedNotification, report: (FinalOutcome) -> Void,
                                name: String, awake: TimeInterval)] = []
    private var events: [String] = []
    /// Each sound a tier played, in order: "tier 1: Glass" for the first alert
    /// the pipeline played and "coordinator: Hero" for what the coordinator
    /// did, a repeat, a final alert or the alert of a match that joined.
    private var played: [String] = []
    /// Every list of rows the coordinator gave the panel, in order.
    private var panels: [[(EscalationID, EscalationSummary)]] = []
    /// Whose sound is playing, told as the app tells it, and how many times an
    /// idle escalation stopped the player, which the app does only when the
    /// escalation owns it.
    private var ownership = PlayerOwnership()
    private var playerStopped = 0
    /// The snooze the pipeline's gate asks, which a test makes on `clock` once
    /// `wired` has made it. With none, nothing is held.
    private var snooze: SnoozeController?
    /// How many times a snooze that ran out having held something announced it.
    private var announcements = 0

    /// The pipeline and the coordinator as the app wires them (`AppDelegate`): the
    /// pipeline asks the snooze, then the coordinator's join, before it plays
    /// tier 1, and begins a ladder only when nothing joined.
    private func wired(_ rules: [Rule]) -> (CapturePipeline, EscalationCoordinator) {
        clock = ManualScheduler(start: t0)
        spokenLines = []
        shortcutRuns = []
        events = []
        played = []
        panels = []
        ownership = PlayerOwnership()
        playerStopped = 0
        snooze = nil
        announcements = 0
        let answer: (String) -> AlertOutcome = { [unowned self] name in
            sounds[name] ?? .played(sound: name, gainDB: 0, outputSilent: false)
        }
        let firstAlert: CapturePipeline.SoundPlayer = { [unowned self] name, _ in
            played.append("tier 1: \(name)")
            let outcome = answer(name)
            ownership.alertSetOff(outcome, byEscalation: false)
            return outcome
        }
        let laterAlert: CapturePipeline.SoundPlayer = { [unowned self] name, _ in
            played.append("coordinator: \(name)")
            let outcome = answer(name)
            ownership.alertSetOff(outcome, byEscalation: true)
            return outcome
        }
        let speak: CapturePipeline.SpeechPlayer = { [unowned self] text, speech in
            spokenLines.append(text)
            return .spoke(text: text, voice: speech.voiceIdentifier, gainDB: 0, outputSilent: false)
        }
        var coordinator: EscalationCoordinator!
        var pipeline: CapturePipeline!
        pipeline = CapturePipeline(ownAppName: "SignalLadder", isSelfTest: { _, _ in false },
                                   playSound: firstAlert, speak: speak,
                                   playAndSpeak: { _, _, _, _ in .couldNotSpeak("unused") },
                                   beginEscalation: { [unowned self] rule, notification, entry, tier1 in
                                       ownership.alertSetOff(tier1, byEscalation: true)
                                       coordinator.begin(rule: rule, notification: notification, entryID: entry,
                                                         tier1Outcome: tier1)
                                   },
                                   holdForSnooze: { [unowned self] rule in snooze?.holds(rule) ?? false },
                                   joinEscalation: { rule, notification in
                                       coordinator.join(rule: rule, notification: notification)
                                   })
        coordinator = EscalationCoordinator(
            scheduler: clock, playSound: laterAlert, speak: speak, playAndSpeak: { _, _, _, _ in .couldNotSpeak("unused") },
            runShortcut: { [unowned self] name, notification, report in
                shortcutRuns.append((notification, report, name, clock.awakeTime()))
            },
            updatePanel: { [unowned self] rows in panels.append(rows) },
            recordSummary: { [unowned self] entry, summary in
                events.append("record")
                pipeline.recordEscalation(entryID: entry, summary, at: clock.now())
            },
            retired: { [unowned self] entry in
                events.append("retired")
                pipeline.escalationRetired(entryID: entry)
            },
            beginPowerAssertion: {}, endPowerAssertion: {},
            silenceIfIdle: { [unowned self] in
                if ownership.escalationOwnsIt { playerStopped += 1 }
            })
        pipeline.setRules(rules)
        return (pipeline, coordinator)
    }

    private func ladderRule(_ ladder: Escalation) -> Rule {
        Rule(name: "On-call mentions", condition: .field(.app, .equals, "Microsoft Teams"),
             alert: .sound(name: "Glass", gainDB: 0), escalation: ladder)
    }

    private let plain = Rule(name: "Mail", condition: .field(.app, .equals, "Mail"), alert: .sound(name: "Glass", gainDB: 0))

    func testAFailedRepeatClearedByALaterAlertStaysClearedWhenAcknowledged() {
        sounds = ["Hero": .failed("sound \"Hero\" was not found")]
        let (p, ladder) = wired([ladderRule(Escalation(tier3: RepeatAlert(action: .sound(name: "Hero", gainDB: 0),
                                                                          intervalSeconds: 30))), plain])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        clock.advance(by: 30)
        XCTAssertEqual(p.unresolvedAlertFailure?.alert, .failed("sound \"Hero\" was not found"))
        feed(p, "Mail", "Weekly report", at: 40)
        XCTAssertNil(p.unresolvedAlertFailure, "cleared by an alert that played")

        ladder.acknowledgeAll()
        XCTAssertNil(p.unresolvedAlertFailure, "the acknowledgement's record carries the old repeat, and must not fold it again")
        XCTAssertEqual(events.suffix(2), ["record", "retired"], "retired only after its last record")
        XCTAssertEqual(p.history.entries.last?.escalation?.status, .acknowledged(at: clock.now()))
    }

    func testAShortcutThatFailsAfterTheAcknowledgementIsStillReported() {
        let (p, ladder) = wired([ladderRule(Escalation(tier4: FinalAlert(afterSeconds: 1, action: .shortcut(name: "Page me"))))])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        clock.advance(by: 1)
        ladder.acknowledgeAll()
        XCTAssertFalse(events.contains("retired"), "held until the Shortcut reports")

        shortcutRuns[0].report(.shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed"))
        XCTAssertEqual(p.unresolvedShortcutFailure?.reason, "the Shortcut \"Page me\" is not installed")
        XCTAssertEqual(p.unresolvedShortcutFailure?.shortcutName, "Page me")
        XCTAssertEqual(events.suffix(2), ["record", "retired"])
        XCTAssertEqual(p.history.entries.first?.escalation?.final,
                       .shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed"))
    }

    func testAShortcutThatFailedIsClearedByItsOwnLaunchAndNotByAnothersFromAnotherRule() {
        let paging = { (name: String, app: String, shortcut: String) in
            Rule(name: name, condition: .field(.app, .equals, app), alert: .sound(name: "Glass", gainDB: 0),
                 escalation: Escalation(tier4: FinalAlert(afterSeconds: 1, action: .shortcut(name: shortcut))))
        }
        let (p, _) = wired([paging("On-call mentions", "Microsoft Teams", "Page me"),
                            paging("Build alerts", "Jenkins", "Page the team")])

        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        clock.advance(by: 1)
        shortcutRuns[0].report(.shortcutFailed(name: "Page me", reason: notInstalled))
        XCTAssertEqual(p.unresolvedShortcutFailure?.shortcutName, "Page me")

        feed(p, "Jenkins", "Build 42 failed", at: 10)
        clock.advance(by: 1)
        XCTAssertEqual(shortcutRuns.count, 2)
        shortcutRuns[1].report(.shortcutLaunched(name: "Page the team"))
        XCTAssertEqual(p.unresolvedShortcutFailure?.shortcutName, "Page me",
                       "another rule's Shortcut launching says nothing about this one")

        // A later escalation of the first rule, not a match that joins the first: the quiet gap
        // has passed since its last match, so this begins its own and does not run the failed
        // Shortcut at once, as a match that joined it would (M5 plan, Ruling 14).
        clock.advance(by: 100)
        feed(p, "Microsoft Teams", "Another mention", at: 120)
        XCTAssertEqual(shortcutRuns.count, 2, "nothing runs until its own tier 4")
        clock.advance(by: 1)
        XCTAssertEqual(shortcutRuns.count, 3)
        shortcutRuns[2].report(.shortcutLaunched(name: "Page me"))
        XCTAssertNil(p.unresolvedShortcutFailure)
    }

    func testTheNotificationThatMatchedIsWhatIsSpokenAndWhatTheShortcutGets() {
        let speech = SpeechAction(voiceIdentifier: "com.example.voice", template: "{title}")
        let (p, _) = wired([ladderRule(Escalation(tier3: RepeatAlert(action: .speak(speech), intervalSeconds: 30),
                                                  tier4: FinalAlert(afterSeconds: 60, action: .shortcut(name: "Page me"))))])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        clock.advance(by: 60)
        XCTAssertEqual(spokenLines.first, "Alex Example mentioned you")
        XCTAssertEqual(shortcutRuns.first?.fields, p.history.entries.first?.captured)
    }

    // MARK: - One burst, a snooze and the pages, wired together (M5 plan, Task 5)

    /// Three rules, as the plan's cross-feature test has them. The pager is a
    /// ladder shaped as Wake me (a panel at 5 seconds, a repeat every 15 with no
    /// limit) with a Shortcut at tier 4 after 120. The chatter rule alerts aloud
    /// and may be held by a snooze. The third has the same flag and a Shortcut as
    /// its last step, which a snooze never holds (M5 plan, Ruling 12).
    private struct Cast {
        let pager: Rule
        let chatter: Rule
        let paging: Rule
        var all: [Rule] { [pager, chatter, paging] }
    }

    private func cast() -> Cast {
        var wakeMe = EscalationEditing.Preset.wakeMe.ladder(repeating: .sound(name: "Hero", gainDB: 0)) ?? Escalation()
        wakeMe.tier4 = FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me"))
        return Cast(
            pager: Rule(name: "On-call mentions", condition: .field(.app, .equals, "Microsoft Teams"),
                        alert: .sound(name: "Glass", gainDB: 0), escalation: wakeMe),
            chatter: Rule(name: "Team chatter", condition: .field(.app, .equals, "Mail"),
                          alert: .sound(name: "Glass", gainDB: 0), quietWhenSnoozed: true),
            paging: Rule(name: "Build alerts", condition: .field(.app, .equals, "Jenkins"),
                         alert: .sound(name: "Glass", gainDB: 0),
                         escalation: Escalation(tier4: FinalAlert(afterSeconds: 30, action: .shortcut(name: "Page the team"))),
                         quietWhenSnoozed: true))
    }

    /// A snooze on the test's clock, which the pipeline's gate then asks, as the
    /// app's does. Nothing it saves is kept, and nothing is real.
    private func makeSnooze() -> SnoozeController {
        let controller = SnoozeController(scheduler: clock, storedUntil: nil, storedHeld: nil, save: { _, _ in },
                                          changed: {}, announce: { [unowned self] in announcements += 1 })
        snooze = controller
        return controller
    }

    /// Moves both clocks on to an absolute awake time, firing what falls due on the way.
    private func at(_ seconds: TimeInterval) {
        clock.advance(by: seconds - clock.awakeTime())
    }

    /// A banner arriving now, stamped by the clock the test moves, so that the
    /// pipeline's timestamps and the scheduler's clock move together.
    @discardableResult
    private func arrive(_ p: CapturePipeline, _ app: String, _ title: String) -> CapturePipeline.Outcome {
        feed(p, app, title, at: clock.now().timeIntervalSince(t0))
    }

    /// Each Shortcut run as "name at awake time for the title it was given".
    private var runs: [String] {
        shortcutRuns.map { "\($0.name) at \(Int($0.awake)) for \($0.fields.title)" }
    }

    /// The latest run reports that it started, as the runner does within its second.
    private func reportLatestRunStarted() {
        guard let run = shortcutRuns.last else { return XCTFail("no Shortcut has run") }
        run.report(.shortcutLaunched(name: run.name))
    }

    private func row(of coordinator: EscalationCoordinator, _ name: String) -> EscalationSummary? {
        coordinator.listedSummaries.first { $0.1.ruleName == name }?.1
    }

    /// The plan's one wired cross-feature test: a burst on a Wake me ladder through a snooze, the pages
    /// and a sleep, to an Acknowledge All, with the pipeline and the coordinator as the app wires them. Times
    /// are seconds from the first match. Where the plan's timings met the owed page, the intent is kept and
    /// the times are the ones the timers give (the plan's "11 minutes in" is 9 minutes after tier 4 ran, inside
    /// the 10, where a match is owed a page and the timer sends it: the match that runs the Shortcut itself is
    /// the first at or after 10 minutes from the run, so it is 11 minutes after the run, and the isolated match
    /// is 7 minutes after that one).
    func testABurstOnAWakeMeLadderThroughASnoozeThePagesAndASleepToAnAcknowledgeAll() throws {
        let c = cast()
        let (p, coordinator) = wired(c.all)
        let snooze = makeSnooze()
        snooze.start(.oneHour)
        let names = SnoozeText.names(of: c.all)

        // The ladder rule's first match begins an escalation and sounds its own first alert.
        arrive(p, "Microsoft Teams", "Incident 1")
        XCTAssertEqual(played, ["tier 1: Glass"])
        XCTAssertEqual(coordinator.listedSummaries.count, 1)
        at(5)
        XCTAssertEqual(panels.last?.map { $0.1.matchCount }, [1], "its row is on the panel, for one match")

        // The second joins it, silently, with a count of 2 and no tier-1 sound: a repeat is 5 seconds away.
        at(10)
        arrive(p, "Microsoft Teams", "Incident 2")
        XCTAssertEqual(played, ["tier 1: Glass"], "no tier-1 sound, and none of its own")
        XCTAssertEqual(p.history.entries[0].alertOutcome, .joinedEscalation(matchNumber: 2))
        XCTAssertEqual(p.history.entries[0].joinedMatch, 2)
        XCTAssertEqual(panels.last?.map { $0.1.matchCount }, [2], "the same row, with a count of 2")
        XCTAssertEqual(coordinator.listedSummaries.count, 1, "one escalation for the two")

        // The flagged rule's match is held while the snooze runs: counted, and in the summary.
        at(12)
        arrive(p, "Mail", "Weekly report 1")
        XCTAssertEqual(played, ["tier 1: Glass"], "it sounds nothing")
        XCTAssertEqual(p.history.entries[0].alertOutcome, .snoozed)
        XCTAssertEqual(coordinator.listedSummaries.count, 1, "and begins no escalation")
        XCTAssertEqual(snooze.summary.counts, [c.chatter.id: 1], "it is counted")
        XCTAssertEqual(SnoozeText.summaryLine(snooze.summary, names: names), "\(SnoozeText.heldOneMatchStem): Team chatter ×1",
                       "and the summary says so")

        // The third rule has the flag and a Shortcut as its last step: the snooze does not hold it, and its page goes.
        at(14)
        arrive(p, "Jenkins", "Build 1")
        XCTAssertEqual(played, ["tier 1: Glass", "tier 1: Glass"], "it sounds")
        XCTAssertEqual(p.history.entries[0].alertOutcome, .played(sound: "Glass", gainDB: 0, outputSilent: false))
        XCTAssertEqual(snooze.summary.total, 1, "and is not counted as held")
        XCTAssertEqual(coordinator.listedSummaries.count, 2)
        at(44)
        XCTAssertEqual(runs, ["Page the team at 44 for Build 1"], "its page goes at its own tier 4")
        reportLatestRunStarted()

        // A snooze started in the middle of the ladder leaves it repeating, and its tier 4 fires once, at 120.
        at(45)
        snooze.start(.twoHours)
        at(50)
        arrive(p, "Mail", "Weekly report 2")
        XCTAssertEqual(snooze.summary.counts, [c.chatter.id: 2], "what was held stays, and the new snooze adds to it")
        at(119)
        XCTAssertEqual(played.filter { $0 == "coordinator: Hero" }.count, 7, "the repeat goes on every 15 seconds: 15 to 105")
        XCTAssertEqual(runs, ["Page the team at 44 for Build 1"], "and tier 4 has not fired")
        at(120)
        XCTAssertEqual(runs, ["Page the team at 44 for Build 1", "Page me at 120 for Incident 1"],
                       "it fires once, with the first match's fields")
        reportLatestRunStarted()
        XCTAssertEqual(row(of: coordinator, "On-call mentions")?.status, .live)

        // A match 11 minutes after that run joins and runs the Shortcut a second time, with its own fields.
        at(779)
        XCTAssertEqual(runs.count, 2)
        at(780)
        arrive(p, "Microsoft Teams", "Incident 3")
        XCTAssertEqual(runs.last, "Page me at 780 for Incident 3")
        XCTAssertEqual(runs.count, 3)
        XCTAssertEqual(p.history.entries[0].alertOutcome, .joinedEscalation(matchNumber: 3), "it joined, silently")
        XCTAssertEqual(row(of: coordinator, "On-call mentions")?.matchCount, 3)
        reportLatestRunStarted()

        // An isolated match 7 minutes after that, with nothing after it, is paged when the 10 minutes are up.
        at(1200)
        arrive(p, "Microsoft Teams", "Incident 4")
        XCTAssertEqual(runs.count, 3, "nothing runs when it arrives")
        XCTAssertEqual(row(of: coordinator, "On-call mentions")?.matchCount, 4)
        at(1379)
        XCTAssertEqual(runs.count, 3)
        at(1380)
        XCTAssertEqual(runs, ["Page the team at 44 for Build 1", "Page me at 120 for Incident 1", "Page me at 780 for Incident 3",
                              "Page me at 1380 for Incident 4"], "10 minutes after the last run, with its fields")
        reportLatestRunStarted()
        at(1500)
        XCTAssertEqual(runs.count, 4, "and not again")
        XCTAssertEqual(snooze.summary.counts, [c.chatter.id: 2], "the held counts have not moved")

        // The Mac sleeps long enough for the ladder to be missed, so the next match begins a fresh one and sounds.
        clock.sleep(for: 600)
        arrive(p, "Microsoft Teams", "Incident 5")
        XCTAssertEqual(played.filter { $0 == "tier 1: Glass" }.count, 3, "it sounds its own first alert")
        XCTAssertEqual(p.history.entries[0].joinedMatch, nil, "and joined nothing")
        XCTAssertEqual(coordinator.listedSummaries.filter { $0.1.status.isUnseenMiss }.count, 2,
                       "the two escalations that were running are missed while asleep, and still to be seen")
        XCTAssertEqual(coordinator.listedSummaries.filter { $0.1.status == .live }.map { $0.1.matchCount }, [1],
                       "and a fresh one stands for one match")
        at(clock.awakeTime() + 6)
        XCTAssertEqual(panels.last?.count, 2, "the panel lists the fresh one and the pager's that was missed")

        // Acknowledge All silences it and empties the panel's rows.
        coordinator.acknowledgeAll()
        XCTAssertEqual(playerStopped, 1, "the escalation owns what is playing, and it is stopped")
        XCTAssertEqual(panels.last?.isEmpty, true, "the panel has no rows")
        XCTAssertEqual(coordinator.listedSummaries.count, 0)
        let sounded = played.count
        let ran = runs.count
        at(clock.awakeTime() + 3600)
        XCTAssertEqual(played.count, sounded, "nothing sounds after it")
        XCTAssertEqual(runs.count, ran, "and nothing is run")

        // The held counts survived all of it, and go only on dismissal.
        XCTAssertEqual(snooze.summary.counts, [c.chatter.id: 2])
        XCTAssertEqual(announcements, 0, "no snooze ran out")
        snooze.dismissSummary(shown: snooze.summary)
        XCTAssertTrue(snooze.summary.isEmpty)
    }

    /// The same cast, where the first run of the Shortcut fails: the next match to join, inside the 10 minutes,
    /// pages again at once, and never beside a run that is still pending, which owes the match a page instead.
    func testAVariantWhereTheFirstRunFailsRePagesAtTheNextJoiningMatchInsideTheTenMinutes() throws {
        let c = cast()
        let (p, coordinator) = wired(c.all)
        let snooze = makeSnooze()
        snooze.start(.oneHour)

        arrive(p, "Microsoft Teams", "Incident 1")
        at(10)
        arrive(p, "Microsoft Teams", "Incident 2")
        at(120)
        XCTAssertEqual(runs, ["Page me at 120 for Incident 1"])
        shortcutRuns[0].report(.shortcutFailed(name: "Page me", reason: notInstalled))
        XCTAssertEqual(p.unresolvedShortcutFailure?.shortcutName, "Page me", "the failure is held")

        at(200)
        arrive(p, "Microsoft Teams", "Incident 3")
        XCTAssertEqual(runs, ["Page me at 120 for Incident 1", "Page me at 200 for Incident 3"],
                       "the next joining match pages again at once, 80 seconds on, inside the 10 minutes")
        XCTAssertEqual(row(of: coordinator, "On-call mentions")?.matchCount, 3)

        at(210)
        arrive(p, "Microsoft Teams", "Incident 4")
        XCTAssertEqual(runs.count, 2, "and never beside a run still pending: this match is owed a page instead")
        shortcutRuns[1].report(.shortcutLaunched(name: "Page me"))
        XCTAssertNil(p.unresolvedShortcutFailure, "its launch clears the held failure")

        at(799)
        XCTAssertEqual(runs.count, 2)
        at(800)
        XCTAssertEqual(runs.last, "Page me at 800 for Incident 4", "the page it was owed goes 10 minutes after the last run began")
        XCTAssertEqual(runs.count, 3)
    }

    /// The status menu is held open while a banner joins an escalation it listed: its Acknowledge leaves that one
    /// escalating, and its page still goes. This goes beyond the plan, which holds the item to the ids it listed.
    func testAMatchThatJoinedWhileTheStatusMenuWasOpenIsNotEndedByThatMenusAcknowledgeAndItsPageStillGoes() throws {
        let c = cast()
        let (p, coordinator) = wired([c.pager])
        arrive(p, "Microsoft Teams", "Incident 1")
        at(130)
        XCTAssertEqual(runs, ["Page me at 120 for Incident 1"])
        reportLatestRunStarted()

        // The menu is built, and held open.
        let held = coordinator.listedSummaries.map(ListedEscalation.init(row:))
        XCTAssertEqual(menu(coordinator.listedSummaries.map(\.1)), ["1 alert escalating"])

        // A banner arrives in those seconds, and joins silently: nothing of its own sounded.
        at(200)
        let sounded = played.count
        arrive(p, "Microsoft Teams", "Incident 2")
        XCTAssertEqual(p.history.entries[0].alertOutcome, .joinedEscalation(matchNumber: 2))
        XCTAssertEqual(played.count, sounded, "it sounded nothing")

        coordinator.acknowledge(listed: held)
        XCTAssertEqual(coordinator.listedSummaries.map { $0.1.matchCount }, [2], "the click leaves it escalating")
        XCTAssertEqual(playerStopped, 0, "and nothing is stopped")
        XCTAssertEqual(menu(coordinator.listedSummaries.map(\.1)), ["1 alert escalating (2 matches)"],
                       "the next menu lists it with the match that joined")

        at(720)
        XCTAssertEqual(runs, ["Page me at 120 for Incident 1", "Page me at 720 for Incident 2"], "its page still goes")

        // And the next menu's click ends it, and stops what plays.
        coordinator.acknowledge(listed: coordinator.listedSummaries.map(ListedEscalation.init(row:)))
        XCTAssertEqual(coordinator.listedSummaries.count, 0)
        XCTAssertEqual(playerStopped, 1)
        at(3000)
        XCTAssertEqual(runs.count, 2)
    }
}
