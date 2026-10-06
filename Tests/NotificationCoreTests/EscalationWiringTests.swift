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
    private var shortcutRuns: [(fields: CapturedNotification, report: (FinalOutcome) -> Void)] = []
    private var events: [String] = []

    private func wired(_ rules: [Rule]) -> (CapturePipeline, EscalationCoordinator) {
        clock = ManualScheduler(start: t0)
        spokenLines = []
        shortcutRuns = []
        events = []
        let play: CapturePipeline.SoundPlayer = { [unowned self] name, _ in
            sounds[name] ?? .played(sound: name, gainDB: 0, outputSilent: false)
        }
        let speak: CapturePipeline.SpeechPlayer = { [unowned self] text, speech in
            spokenLines.append(text)
            return .spoke(text: text, voice: speech.voiceIdentifier, gainDB: 0, outputSilent: false)
        }
        var coordinator: EscalationCoordinator!
        var pipeline: CapturePipeline!
        pipeline = CapturePipeline(ownAppName: "SignalLadder", isSelfTest: { _, _ in false },
                                   playSound: play, speak: speak, playAndSpeak: { _, _, _, _ in .couldNotSpeak("unused") },
                                   beginEscalation: { rule, notification, entry, tier1 in
                                       coordinator.begin(rule: rule, notification: notification, entryID: entry,
                                                         tier1Outcome: tier1)
                                   },
                                   holdForSnooze: { _ in false },
                                   joinEscalation: { _, _ in nil })
        coordinator = EscalationCoordinator(
            scheduler: clock, playSound: play, speak: speak, playAndSpeak: { _, _, _, _ in .couldNotSpeak("unused") },
            runShortcut: { [unowned self] _, notification, report in shortcutRuns.append((notification, report)) },
            updatePanel: { _ in },
            recordSummary: { [unowned self] entry, summary in
                events.append("record")
                pipeline.recordEscalation(entryID: entry, summary, at: clock.now())
            },
            retired: { [unowned self] entry in
                events.append("retired")
                pipeline.escalationRetired(entryID: entry)
            },
            beginPowerAssertion: {}, endPowerAssertion: {}, silenceIfIdle: {})
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

        feed(p, "Microsoft Teams", "Another mention", at: 20)
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
}
