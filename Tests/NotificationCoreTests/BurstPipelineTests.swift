import XCTest
@testable import NotificationCore

/// What the capture pipeline does with a match whose rule has a ladder: it asks
/// whether the match joins an escalation already running for its rule, after the
/// snooze gate and before tier 1, and what it records when the answer is yes
/// (M5 plan, Task 5, Ruling 14, O11). The join is a closure the app gives, so
/// the first half gives a stub that says what it was asked and when and answers
/// as told; the second half wires the pipeline to a real `EscalationCoordinator`
/// on `ManualScheduler`, as `EscalationWiringTests` wires one, with the
/// pipeline's timestamps and the scheduler's clock moving together. Nothing
/// plays, nothing is shown, no process runs and nothing waits on a real clock:
/// sounds and Shortcut runs are lists, and each Shortcut reports when a test
/// says. Fixtures are invented text (§10.1).
@MainActor
final class BurstPipelineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let marker = "SignalLadder canary TEST-MARKER"
    private let voice = "com.example.voice"
    private let notInstalled = "the Shortcut \"Page me\" is not installed"

    /// In the order they happened: "gate", "join", each alert as "play:Glass" or
    /// "say:<line>", and "begin".
    private var events: [String] = []
    /// What the join was asked, with what the row held at the time.
    private var asked: [(rule: String, notification: CapturedNotification, annotation: String?,
                         outcome: AlertOutcome?)] = []
    /// Each ladder begun, with what tier 1 did.
    private var begun: [(rule: String, entry: UUID, tier1: AlertOutcome)] = []
    private var held = false
    private var joinAnswer: EscalationJoin?
    private var soundAnswer: (String) -> AlertOutcome = { .played(sound: $0, gainDB: 0, outputSilent: false) }

    override func setUp() {
        events = []
        asked = []
        begun = []
        held = false
        joinAnswer = nil
        soundAnswer = { .played(sound: $0, gainDB: 0, outputSilent: false) }
    }

    // MARK: - Fixtures

    /// The pipeline as the app builds it, with a gate that says what `held` says
    /// and a join that records what it is asked and answers as `joinAnswer` says.
    private func pipeline(history: CaptureRingBuffer = CaptureRingBuffer()) -> CapturePipeline {
        var p: CapturePipeline!
        p = CapturePipeline(
            ownAppName: "SignalLadder",
            isSelfTest: { [marker] raw, children in raw.contains(marker) || children.contains { $0.contains(marker) } },
            playSound: { [unowned self] name, _ in
                events.append("play:\(name)")
                return soundAnswer(name)
            },
            speak: { [unowned self] text, speech in
                events.append("say:\(text)")
                return .spoke(text: text, voice: "Daniel", gainDB: speech.gainDB, outputSilent: false)
            },
            playAndSpeak: { [unowned self] name, _, text, speech in
                events.append("play:\(name)+say:\(text)")
                return .playedAndSpoke(sound: name, soundGainDB: 0, text: text, voice: "Daniel",
                                       speechGainDB: speech.gainDB, outputSilent: false)
            },
            beginEscalation: { [unowned self] rule, _, entry, tier1 in
                events.append("begin")
                begun.append((rule.name, entry, tier1))
            },
            holdForSnooze: { [unowned self] _ in
                events.append("gate")
                return held
            },
            joinEscalation: { [unowned self] rule, notification in
                events.append("join")
                let row = p.history.entries.first
                asked.append((rule.name, notification, row?.annotation?.ruleName, row?.alertOutcome))
                return joinAnswer
            },
            history: history)
        return p
    }

    private let ladder = Escalation(tier3: RepeatAlert(action: .sound(name: "Hero", gainDB: 0)))

    private func speech() -> SpeechAction { SpeechAction(voiceIdentifier: voice, template: "{title}") }

    /// A rule with a ladder whose first alert is a sound and a spoken line, so that
    /// a match that plays its own is plain to see, and one that does not is too.
    private func ladderRule(_ name: String = "On-call mentions", app: String = "Microsoft Teams",
                            alert: AlertAction? = nil, ladder: Escalation? = nil) -> Rule {
        Rule(name: name, condition: .field(.app, .equals, app),
             alert: alert ?? .soundAndSpeak(soundName: "Glass", soundGainDB: 0, speech: speech()),
             escalation: ladder ?? self.ladder)
    }

    private func plainRule(_ app: String = "Mail") -> Rule {
        Rule(name: "Mail", condition: .field(.app, .equals, app), alert: .sound(name: "Glass", gainDB: 0))
    }

    @discardableResult
    private func feed(_ p: CapturePipeline, _ app: String, _ title: String, at offset: TimeInterval = 0)
        -> CapturePipeline.Outcome {
        p.process(RawCapture(timestamp: t0.addingTimeInterval(offset), rawText: "\(app), \(title), Placeholder body text",
                             subrole: "AXNotificationCenterBanner"),
                  textChildren: [title, "Placeholder body text"])
    }

    private let heard = AlertOutcome.played(sound: "Glass", gainDB: 0, outputSilent: false)

    private func silentJoin(_ number: Int) -> EscalationJoin {
        EscalationJoin(matchNumber: number, alert: nil, ranShortcut: false)
    }

    // MARK: - A match that joins and stays silent

    func testAMatchThatJoinedAndStayedSilentPlaysNoFirstAlertAndBeginsNoLadderButIsAnnotatedAndCounted() {
        let p = pipeline()
        p.setRules([ladderRule()])
        joinAnswer = silentJoin(3)

        XCTAssertEqual(feed(p, "Microsoft Teams", "Alex Example mentioned you"), .recorded(matchedRule: "On-call mentions"))

        XCTAssertEqual(events, ["gate", "join"], "no sound, no spoken line and no ladder: only the two questions were asked")
        XCTAssertEqual(p.captureCount, 1, "counted")
        let row = p.history.entries[0]
        XCTAssertEqual(InspectorRowText.outcome(row), "Matched On-call mentions", "annotated")
        XCTAssertEqual(row.alertOutcome, .joinedEscalation(matchNumber: 3))
        XCTAssertEqual(row.joinedMatch, 3)
        XCTAssertEqual(InspectorRowText.alert(row), "Joined an escalation that repeats (match 3), no alert of its own")
        XCTAssertEqual(InspectorRowText.symbol(.joinedEscalation(matchNumber: 3)), "arrow.triangle.merge")
        XCTAssertEqual(p.lastMatch, CapturePipeline.LastMatch(ruleName: "On-call mentions", at: t0,
                                                              alert: .joinedEscalation(matchNumber: 3)))
        XCTAssertEqual(p.appsThatAlerted, ["Microsoft Teams"], "the mute walkthrough still knows the app was in play")
        XCTAssertTrue(begun.isEmpty)
    }

    func testASilentJoinLeavesAnUnresolvedFailureAloneAndSetsNoneOfItsOwn() {
        // The failure state is neither set nor cleared: nothing was played, so a
        // repeat that is about to sound is no evidence that an earlier sound works.
        let p = pipeline()
        p.setRules([ladderRule(alert: .sound(name: "Glass", gainDB: 0))])
        soundAnswer = { _ in .failed("sound \"Glass\" was not found") }
        feed(p, "Microsoft Teams", "First", at: 0)
        let earlier = p.unresolvedAlertFailure
        XCTAssertEqual(earlier?.alert, .failed("sound \"Glass\" was not found"), "a failure is held to begin with")

        joinAnswer = silentJoin(2)
        feed(p, "Microsoft Teams", "Second", at: 10)
        XCTAssertEqual(p.unresolvedAlertFailure, earlier, "left as it was")
        XCTAssertEqual(p.lastMatch?.alert, .joinedEscalation(matchNumber: 2))

        // And with none held, a silent join sets none.
        setUp()
        let q = pipeline()
        q.setRules([ladderRule(alert: .sound(name: "Glass", gainDB: 0))])
        feed(q, "Microsoft Teams", "First", at: 0)
        XCTAssertNil(q.unresolvedAlertFailure)
        joinAnswer = silentJoin(2)
        feed(q, "Microsoft Teams", "Second", at: 10)
        XCTAssertNil(q.unresolvedAlertFailure, "a silent join is not a failure of anything")
        XCTAssertEqual(q.lastMatch?.alert, .joinedEscalation(matchNumber: 2))
    }

    func testNothingTheMatchSaidReachesTheRowsLineOrTheMenuForASilentJoin() {
        let title = "Zyxwv-4417 quartzite sundial"
        let p = pipeline()
        p.setRules([ladderRule()])
        joinAnswer = silentJoin(5)
        p.process(RawCapture(timestamp: t0, rawText: "Microsoft Teams, \(title), ledger-9f2c obsidian",
                             subrole: "AXNotificationCenterBanner"),
                  textChildren: [title, "ledger-9f2c obsidian"])

        let row = p.history.entries[0]
        let menu = AlertMenuText.lines(lastMatch: p.lastMatch, unresolvedFailure: p.unresolvedAlertFailure,
                                       anyRulePlaysSound: true, outputSilent: false, time: { _ in "10:42" })
        let shown = ([InspectorRowText.alert(row) ?? "no alert line"] + menu).joined(separator: "\n")
        for word in ["Zyxwv", "quartzite", "sundial", "ledger", "obsidian"] {
            XCTAssertFalse(shown.contains(word), "\(word) in \(shown)")
        }
        XCTAssertNil(row.alertOutcome?.spokenText, "nothing was said, so there is no line for the Inspector either")
        XCTAssertTrue(shown.contains("match 5"), shown)
        XCTAssertFalse(shown.lowercased().contains("message"), "a count is of matches")
    }

    // MARK: - A match that joins and plays its own alert

    func testAMatchThatJoinedAndPlayedItsOwnAlertRecordsThatOutcomeAndItsNumberOnItsRow() {
        let p = pipeline()
        p.setRules([ladderRule()])
        joinAnswer = EscalationJoin(matchNumber: 2, alert: heard, ranShortcut: false)

        feed(p, "Microsoft Teams", "Alex Example mentioned you")

        XCTAssertEqual(events, ["gate", "join"], "the coordinator played it: the pipeline played nothing of its own")
        let row = p.history.entries[0]
        XCTAssertEqual(row.alertOutcome, heard, "the alert's own outcome")
        XCTAssertEqual(row.joinedMatch, 2, "and the number, so that it still says it joined")
        XCTAssertEqual(p.lastMatch, CapturePipeline.LastMatch(ruleName: "On-call mentions", at: t0, alert: heard))
        XCTAssertTrue(begun.isEmpty, "no ladder: it is part of the one already running")
        XCTAssertEqual(p.captureCount, 1)
    }

    func testAJoinedMatchsOwnAlertClearsOrSetsTheFailureAsAnyAlertDoes() {
        enum Folded { case sets, clears, leaves }
        struct Case {
            let alert: AlertOutcome
            let folded: Folded
        }
        let cases: [Case] = [
            Case(alert: .played(sound: "Glass", gainDB: 0, outputSilent: false), folded: .clears),
            Case(alert: .spoke(text: "x", voice: "Daniel", gainDB: 0, outputSilent: false), folded: .clears),
            Case(alert: .playedAndSpoke(sound: "Glass", soundGainDB: 0, text: "x", voice: "Daniel", speechGainDB: 0,
                                        outputSilent: false), folded: .clears),
            Case(alert: .failed("sound \"Glass\" was not found"), folded: .sets),
            Case(alert: .couldNotSpeak("voice \"x\" is not installed"), folded: .sets),
            Case(alert: .playedButNotSpoken(sound: "Glass", gainDB: 0, reason: "x", outputSilent: false), folded: .sets),
            Case(alert: .spokeButNotPlayed(text: "x", voice: "Daniel", gainDB: 0, reason: "x", outputSilent: false),
                 folded: .sets),
            Case(alert: .silentByRule, folded: .leaves),
            Case(alert: .noAlertSet, folded: .leaves),
        ]
        for c in cases {
            // A failure held from an earlier match, and then one that joins.
            setUp()
            let p = pipeline()
            p.setRules([ladderRule(alert: .sound(name: "Glass", gainDB: 0))])
            soundAnswer = { _ in .failed("sound \"Glass\" was not found") }
            feed(p, "Microsoft Teams", "First", at: 0)
            let earlier = p.unresolvedAlertFailure
            XCTAssertNotNil(earlier, "\(c.alert)")

            joinAnswer = EscalationJoin(matchNumber: 2, alert: c.alert, ranShortcut: false)
            feed(p, "Microsoft Teams", "Second", at: 10)
            switch c.folded {
            case .clears:
                XCTAssertNil(p.unresolvedAlertFailure, "\(c.alert)")
            case .sets:
                XCTAssertEqual(p.unresolvedAlertFailure,
                               CapturePipeline.LastMatch(ruleName: "On-call mentions", at: t0 + 10, alert: c.alert),
                               "\(c.alert)")
            case .leaves:
                XCTAssertEqual(p.unresolvedAlertFailure, earlier, "\(c.alert)")
            }
            XCTAssertEqual(p.history.entries[0].alertOutcome, c.alert, "\(c.alert)")
            XCTAssertEqual(p.history.entries[0].joinedMatch, 2, "\(c.alert)")
        }
    }

    // MARK: - What is asked, and when

    func testAHeldMatchNeverAsksToJoin() {
        let p = pipeline()
        p.setRules([ladderRule()])
        held = true
        joinAnswer = silentJoin(2)

        feed(p, "Microsoft Teams", "Alex Example mentioned you")

        XCTAssertEqual(events, ["gate"], "the gate was asked, and nothing after it")
        XCTAssertTrue(asked.isEmpty)
        XCTAssertEqual(p.history.entries[0].alertOutcome, .snoozed)
        XCTAssertNil(p.history.entries[0].joinedMatch, "a held match never joins a ladder (Ruling 13)")
        XCTAssertTrue(begun.isEmpty)

        held = false
        feed(p, "Microsoft Teams", "Another mention", at: 10)
        XCTAssertEqual(asked.count, 1, "and a match no snooze held does")
    }

    func testARuleWithNoLadderNeverAsksAndPlaysItsOwnAlertAsBefore() {
        let p = pipeline()
        p.setRules([plainRule()])
        joinAnswer = silentJoin(2)

        feed(p, "Mail", "Weekly report", at: 0)
        feed(p, "Mail", "Another report", at: 10)

        XCTAssertTrue(asked.isEmpty, "rules with no ladder are never coalesced")
        XCTAssertEqual(events, ["gate", "play:Glass", "gate", "play:Glass"])
        XCTAssertEqual(p.history.entries.map(\.joinedMatch), [nil, nil])
        XCTAssertEqual(p.history.entries.map(\.alertOutcome), [heard, heard])
    }

    func testADedupeRepeatAPreviewTheSelfTestAndTheAppsOwnTrafficNeverReachTheJoin() {
        // Under a rule that would match every one of them, so that only the
        // pipeline's own order keeps them from being asked.
        let catchAll = Rule(name: "Everything", condition: .field(.subrole, .equals, "AXNotificationCenterBanner"),
                            alert: .sound(name: "Glass", gainDB: 0), escalation: ladder)
        let p = pipeline()
        feed(p, "Microsoft Teams", "Alex Example mentioned you", at: 0)
        p.setRules([catchAll])
        XCTAssertTrue(asked.isEmpty, "a preview of the rules over what was already captured acts on nothing")

        feed(p, "Microsoft Teams", "Second mention", at: 10)
        XCTAssertEqual(asked.count, 1)
        feed(p, "Microsoft Teams", "Second mention", at: 10.5)
        XCTAssertEqual(asked.count, 1, "a repeat inside dedupe's window is not a new match")

        feed(p, "Microsoft Teams", marker, at: 20)
        XCTAssertEqual(asked.count, 1, "the self-test is the app talking to itself")
        feed(p, "SignalLadder", SelfNotification.blindTitle, at: 30)
        XCTAssertEqual(asked.count, 1, "and so is an alarm it posted")

        feed(p, "Microsoft Teams", "Third mention", at: 40)
        XCTAssertEqual(asked.count, 2, "the same rule is asked about anyone else's")
    }

    func testAMatchOfNoRuleAsksNothingWhetherOrNotRulesAreLoaded() {
        let p = pipeline()
        feed(p, "Weather", "Rain", at: 0)
        p.setRules([ladderRule()])
        feed(p, "Weather", "Snow", at: 10)
        XCTAssertTrue(asked.isEmpty)
        XCTAssertEqual(events, [], "no rule matched, so not even the gate was asked")
    }

    func testWhenNothingJoinsTheMatchIsAskedOnceAfterTheGateAndBeforeTier1AndBeginsAsItAlwaysDid() {
        let p = pipeline()
        p.setRules([ladderRule()])
        joinAnswer = nil

        feed(p, "Microsoft Teams", "Alex Example mentioned you")

        XCTAssertEqual(events, ["gate", "join", "play:Glass+say:Alex Example mentioned you", "begin"],
                       "the gate, then the join, then tier 1, then the ladder: the join before tier 1, because a decision after it " +
                       "would have played tier 1 for every match of a burst")
        XCTAssertEqual(asked.count, 1, "once")
        XCTAssertEqual(asked.first?.rule, "On-call mentions")
        XCTAssertEqual(asked.first?.notification, p.history.entries[0].captured, "the notification that matched")
        XCTAssertEqual(asked.first?.annotation, "On-call mentions", "by then the row reads as a match")
        XCTAssertNil(asked.first?.outcome, "and nothing had yet been done about it")
        XCTAssertNil(p.history.entries[0].joinedMatch)
        XCTAssertEqual(begun.count, 1)
        XCTAssertEqual(begun.first?.tier1, p.history.entries[0].alertOutcome, "begun with the row's own outcome")
        XCTAssertEqual(begun.first?.entry, p.history.entries[0].id)
    }

    // MARK: - The pipeline and the coordinator together, as the app wires them

    private var clock = ManualScheduler()
    /// Each sound or line either played, as "pipeline:Glass" for tier 1 and
    /// "coordinator:Hero" for what the coordinator played.
    private var played: [String] = []
    private var panels: [[(EscalationID, EscalationSummary)]] = []
    private var shortcutRuns: [(fields: CapturedNotification, report: (FinalOutcome) -> Void)] = []
    /// What a Shortcut run reports the moment it starts; nil for none, so that
    /// a test reports it.
    private var shortcutAnswer: FinalOutcome?
    private var ladders = 0

    private func wired(_ rules: [Rule], history: CaptureRingBuffer = CaptureRingBuffer())
        -> (CapturePipeline, EscalationCoordinator) {
        clock = ManualScheduler(start: t0)
        played = []
        panels = []
        shortcutRuns = []
        shortcutAnswer = nil
        ladders = 0
        var coordinator: EscalationCoordinator!
        var p: CapturePipeline!
        p = CapturePipeline(
            ownAppName: "SignalLadder", isSelfTest: { _, _ in false },
            playSound: { [unowned self] name, _ in
                played.append("pipeline:\(name)")
                return .played(sound: name, gainDB: 0, outputSilent: false)
            },
            speak: { _, _ in .couldNotSpeak("unused") },
            playAndSpeak: { _, _, _, _ in .couldNotSpeak("unused") },
            beginEscalation: { [unowned self] rule, notification, entry, tier1 in
                ladders += 1
                coordinator.begin(rule: rule, notification: notification, entryID: entry, tier1Outcome: tier1)
            },
            holdForSnooze: { _ in false },
            joinEscalation: { rule, notification in coordinator.join(rule: rule, notification: notification) },
            history: history)
        coordinator = EscalationCoordinator(
            scheduler: clock,
            playSound: { [unowned self] name, _ in
                played.append("coordinator:\(name)")
                return .played(sound: name, gainDB: 0, outputSilent: false)
            },
            speak: { _, _ in .couldNotSpeak("unused") },
            playAndSpeak: { _, _, _, _ in .couldNotSpeak("unused") },
            runShortcut: { [unowned self] _, notification, report in
                shortcutRuns.append((notification, report))
                if let answer = shortcutAnswer { report(answer) }
            },
            updatePanel: { [unowned self] rows in panels.append(rows) },
            recordSummary: { [unowned self] entry, summary in p.recordEscalation(entryID: entry, summary, at: clock.now()) },
            retired: { entry in p.escalationRetired(entryID: entry) },
            beginPowerAssertion: {}, endPowerAssertion: {}, silenceIfIdle: {})
        p.setRules(rules)
        return (p, coordinator)
    }

    /// Moves both clocks on to an absolute time, firing what falls due on the way,
    /// so that the next banner is fed at the time the scheduler is at.
    private func at(_ seconds: TimeInterval) {
        clock.advance(by: seconds - clock.awakeTime())
    }

    /// On call, as the editor's preset has it, with a Shortcut after two minutes
    /// as a Custom ladder holds one, and the repeat a different sound from the
    /// first alert so that each can be told from the other.
    private func onCallWithAShortcut() -> Escalation {
        var onCall = EscalationEditing.Preset.onCall.ladder(repeating: .sound(name: "Hero", gainDB: 0))
            ?? Escalation()
        onCall.tier4 = FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me"))
        return onCall
    }

    private func firstAlertRule(_ ladder: Escalation) -> Rule {
        Rule(name: "On-call mentions", condition: .field(.app, .equals, "Microsoft Teams"),
             alert: .sound(name: "Glass", gainDB: 0), escalation: ladder)
    }

    func testATwentyMatchStormOnAnOnCallLadderIsOneBeginOneRowWithACountOfTwentyAndOneShortcutCall() {
        let (p, _) = wired([firstAlertRule(onCallWithAShortcut())])
        for n in 0..<20 {
            let seconds = TimeInterval(n * 5)
            at(seconds)
            feed(p, "Microsoft Teams", "Incident \(n)", at: seconds)
        }
        at(130)

        XCTAssertEqual(ladders, 1, "one begin")
        XCTAssertEqual(played.filter { $0 == "pipeline:Glass" }.count, 1, "one first alert")
        XCTAssertFalse(played.contains("coordinator:Glass"), "no joined match played its own: a repeat was about to sound")
        XCTAssertEqual(played.filter { $0 == "coordinator:Hero" }.count, 4, "the repeats at 30, 60, 90 and 120, and none for a match")
        XCTAssertEqual(Set(panels.flatMap { $0.map { $0.0 } }).count, 1, "one panel row, ever")
        XCTAssertEqual(panels.last?.count, 1)
        XCTAssertEqual(panels.last?.first?.1.matchCount, 20, "with a count of 20")
        XCTAssertEqual(shortcutRuns.count, 1, "one Shortcut call")
        XCTAssertEqual(shortcutRuns.first?.fields, p.history.entries.last?.captured,
                       "with the fields of the match that began it, which tier 4 pages with")

        XCTAssertEqual(p.captureCount, 20)
        let rows = Array(p.history.entries.reversed())
        XCTAssertEqual(rows.count, 20)
        XCTAssertEqual(rows[0].escalation?.matchCount, 20, "the escalation's trail is on the first row")
        XCTAssertNil(rows[0].joinedMatch)
        XCTAssertEqual(rows[0].alertOutcome, .played(sound: "Glass", gainDB: 0, outputSilent: false))
        for (index, row) in rows.enumerated().dropFirst() {
            XCTAssertEqual(row.joinedMatch, index + 1, "match \(index + 1)")
            XCTAssertEqual(row.alertOutcome, .joinedEscalation(matchNumber: index + 1))
            XCTAssertNil(row.escalation, "the others have no trail of their own")
            XCTAssertEqual(InspectorRowText.outcome(row), "Matched On-call mentions")
        }
    }

    func testATwentyMatchStormOnALadderWithNoRepeatPlaysEachMatchsOwnAlertAndStillPagesOnce() {
        // A panel and a Shortcut only: nothing repeats, so nothing stands in for
        // a match's alert, and each is heard. Within a quiet gap of the last, so
        // each joins.
        let (p, _) = wired([firstAlertRule(Escalation(tier2: PanelAlert(delaySeconds: 10),
                                                      tier4: FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me"))))])
        for n in 0..<20 {
            let seconds = TimeInterval(n * 5)
            at(seconds)
            feed(p, "Microsoft Teams", "Incident \(n)", at: seconds)
        }
        at(130)

        XCTAssertEqual(ladders, 1)
        XCTAssertEqual(played.filter { $0 == "pipeline:Glass" }.count, 1)
        XCTAssertEqual(played.filter { $0 == "coordinator:Glass" }.count, 19, "each of the others played its own")
        XCTAssertEqual(panels.last?.first?.1.matchCount, 20)
        XCTAssertEqual(shortcutRuns.count, 1, "and the Shortcut was run once")
        let rows = Array(p.history.entries.reversed())
        for (index, row) in rows.enumerated().dropFirst() {
            XCTAssertEqual(row.alertOutcome, .played(sound: "Glass", gainDB: 0, outputSilent: false), "match \(index + 1)")
            XCTAssertEqual(row.joinedMatch, index + 1, "an audible join still says it joined")
        }
    }

    func testAMatchAfterAcknowledgeStartsAfresh() {
        let (p, coordinator) = wired([firstAlertRule(onCallWithAShortcut())])
        at(0)
        feed(p, "Microsoft Teams", "Incident 0", at: 0)
        at(15)
        feed(p, "Microsoft Teams", "Incident 1", at: 15)
        XCTAssertEqual(ladders, 1)
        XCTAssertEqual(p.history.entries[0].joinedMatch, 2)

        coordinator.acknowledgeAll()
        at(20)
        feed(p, "Microsoft Teams", "Incident 2", at: 20)

        XCTAssertEqual(ladders, 2, "closed by the acknowledgement: this begins a new one")
        XCTAssertEqual(played.filter { $0 == "pipeline:Glass" }.count, 2, "and sounds its own first alert")
        let fresh = p.history.entries[0]
        XCTAssertNil(fresh.joinedMatch)
        XCTAssertEqual(fresh.alertOutcome, .played(sound: "Glass", gainDB: 0, outputSilent: false))

        at(40)
        XCTAssertEqual(panels.last?.count, 1, "one row, the new escalation's")
        XCTAssertEqual(panels.last?.first?.1.matchCount, 1)
        at(45)
        feed(p, "Microsoft Teams", "Incident 3", at: 45)
        XCTAssertEqual(ladders, 2, "the next joins the new one")
        XCTAssertEqual(p.history.entries[0].joinedMatch, 2, "as its second match")
        XCTAssertEqual(panels.last?.first?.1.matchCount, 2)
    }

    func testAMatchAfterAcknowledgeStartsAfreshEvenWhereNothingRepeatsAndTheQuietGapHasNotPassed() {
        // A panel and a Shortcut only: the last match was 5 seconds ago, well inside
        // the quiet gap, so only the acknowledgement keeps the next one from
        // joining. Acknowledging closes the burst (Ruling 14).
        let (p, coordinator) = wired([firstAlertRule(Escalation(tier2: PanelAlert(delaySeconds: 10),
                                                                tier4: FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me"))))])
        at(0)
        feed(p, "Microsoft Teams", "Incident 0", at: 0)
        at(10)
        feed(p, "Microsoft Teams", "Incident 1", at: 10)
        XCTAssertEqual(p.history.entries[0].joinedMatch, 2)
        XCTAssertEqual(ladders, 1)

        coordinator.acknowledgeAll()
        at(15)
        feed(p, "Microsoft Teams", "Incident 2", at: 15)

        XCTAssertEqual(ladders, 2, "5 seconds after the last match, and it still begins its own")
        XCTAssertNil(p.history.entries[0].joinedMatch)
        XCTAssertEqual(played, ["pipeline:Glass", "coordinator:Glass", "pipeline:Glass"],
                       "each ladder's first match sounded its own first alert, and the one that joined between them played its own")
        XCTAssertTrue(shortcutRuns.isEmpty, "nothing was paged: the acknowledgement came first")
    }

    func testTheCountSurvivesTheFirstRowAgeingOutOfTheHistory() {
        let (p, _) = wired([firstAlertRule(onCallWithAShortcut())], history: CaptureRingBuffer(capacity: 3))
        at(0)
        feed(p, "Microsoft Teams", "Incident 0", at: 0)
        let first = p.history.entries[0].id
        for n in 1..<6 {
            let seconds = TimeInterval(n * 5)
            at(seconds)
            feed(p, "Microsoft Teams", "Incident \(n)", at: seconds)
        }
        at(30)

        XCTAssertFalse(p.history.entries.contains { $0.id == first }, "the first row has aged out")
        XCTAssertEqual(p.history.entries.map(\.joinedMatch), [6, 5, 4], "the rows that are left say which they were")
        XCTAssertEqual(panels.last?.count, 1)
        XCTAssertEqual(panels.last?.first?.1.matchCount, 6, "the count lives in the coordinator, and is right")
        XCTAssertEqual(ladders, 1)
    }

    func testABannerReadTwiceIsOneMatchBecauseDedupeCollapsesItBeforeAnyRule() {
        let (p, _) = wired([firstAlertRule(onCallWithAShortcut())])
        at(0)
        feed(p, "Microsoft Teams", "Incident 0", at: 0)
        at(10)
        feed(p, "Microsoft Teams", "Incident 1", at: 10)
        feed(p, "Microsoft Teams", "Incident 1", at: 10.5)
        at(11)
        feed(p, "Microsoft Teams", "Incident 2", at: 11)

        XCTAssertEqual(p.captureCount, 3, "the second read of Incident 1 is not a capture")
        XCTAssertEqual(panels.last?.first?.1.matchCount, 3, "and is not counted")
        XCTAssertEqual(p.history.entries[1].suppressedRepeatCount, 1, "it is noted on the row it duplicates")
        XCTAssertEqual(p.history.entries.map(\.joinedMatch), [3, 2, nil])
    }

    // MARK: - Each run's outcome is folded once

    private func pagingRule() -> Rule {
        Rule(name: "On-call mentions", condition: .field(.app, .equals, "Microsoft Teams"),
             alert: .sound(name: "Glass", gainDB: 0),
             escalation: Escalation(tier4: FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me"))))
    }

    private func summary(_ final: FinalOutcome?, count: Int) -> EscalationSummary {
        EscalationSummary(ruleName: "On-call mentions", startedAt: t0, tierReached: 4, final: final, matchCount: 4,
                          finalCount: count)
    }

    func testEachRunsOutcomeIsFoldedOnceAndARepageThatFailsIsHeldLikeTheFirst() {
        let p = pipeline()
        p.setRules([pagingRule()])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        let row = p.history.entries[0].id
        let failed = FinalOutcome.shortcutFailed(name: "Page me", reason: notInstalled)

        p.recordEscalation(entryID: row, summary(.shortcutLaunched(name: "Page me"), count: 1), at: t0 + 120)
        XCTAssertNil(p.unresolvedShortcutFailure, "the first run started")

        p.recordEscalation(entryID: row, summary(failed, count: 2), at: t0 + 720)
        XCTAssertEqual(p.unresolvedShortcutFailure,
                       CapturePipeline.ShortcutFailure(ruleName: "On-call mentions", shortcutName: "Page me",
                                                       at: t0 + 720, reason: notInstalled),
                       "the re-page did not run: held as the first would have been (Ruling 6)")

        p.recordEscalation(entryID: row, summary(failed, count: 2), at: t0 + 800)
        XCTAssertEqual(p.unresolvedShortcutFailure?.at, t0 + 720, "the same run's outcome, recorded again, is not news")

        p.recordEscalation(entryID: row, summary(.shortcutFailed(name: "Page me", reason: "it could not be started"), count: 3),
                           at: t0 + 810)
        XCTAssertEqual(p.unresolvedShortcutFailure?.at, t0 + 810, "a later run that fails is a new outcome, folded once")
        XCTAssertEqual(p.unresolvedShortcutFailure?.reason, "it could not be started")
    }

    func testARepageThatStartsClearsTheHeldFailureOnlyByItsName() {
        let p = pipeline()
        p.setRules([pagingRule()])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        let row = p.history.entries[0].id
        p.recordEscalation(entryID: row, summary(.shortcutFailed(name: "Page me", reason: notInstalled), count: 1),
                           at: t0 + 120)
        let held = p.unresolvedShortcutFailure
        XCTAssertNotNil(held)

        p.recordEscalation(entryID: row, summary(.shortcutLaunched(name: "Page the team"), count: 2), at: t0 + 720)
        XCTAssertEqual(p.unresolvedShortcutFailure, held, "another Shortcut starting says nothing about this one")

        p.recordEscalation(entryID: row, summary(.shortcutLaunched(name: "Page me"), count: 3), at: t0 + 1320)
        XCTAssertNil(p.unresolvedShortcutFailure, "its own name does")
    }

    func testAFinalAlertsOutcomeIsStillFoldedOnceAndAFinalRecordedAfterRetiringIsFoldedAfresh() {
        let p = pipeline()
        p.setRules([pagingRule()])
        feed(p, "Microsoft Teams", "Alex Example mentioned you")
        let row = p.history.entries[0].id
        let failed = FinalOutcome.alerted(.failed("sound \"Hero\" was not found"))

        p.recordEscalation(entryID: row, summary(failed, count: 1), at: t0 + 120)
        XCTAssertEqual(p.unresolvedAlertFailure?.at, t0 + 120)
        feed(p, "Microsoft Teams", "Another mention", at: 130)
        XCTAssertNil(p.unresolvedAlertFailure, "cleared by a later alert that played")
        p.recordEscalation(entryID: row, summary(failed, count: 1), at: t0 + 140)
        XCTAssertNil(p.unresolvedAlertFailure, "the same outcome again is not set again")

        p.escalationRetired(entryID: row)
        p.recordEscalation(entryID: row, summary(failed, count: 1), at: t0 + 150)
        XCTAssertEqual(p.unresolvedAlertFailure?.at, t0 + 150, "nothing of a retired escalation is kept")
    }

    func testAShortcutThatKeepsFailingIsHeldAtEachFailureAndOneThatStartsClearsIt() {
        // Wired: a panel and a Shortcut only, matches within the quiet gap of one
        // another so that each joins, and a Shortcut that reports a failure the
        // moment it is run. A run that failed is tried again at once by the next
        // match (O11b), and each failure is held where it happened.
        let (p, _) = wired([firstAlertRule(Escalation(tier2: PanelAlert(delaySeconds: 10),
                                                      tier4: FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me"))))])
        shortcutAnswer = .shortcutFailed(name: "Page me", reason: notInstalled)
        let times: [TimeInterval] = [0, 50, 100]
        for seconds in times {
            at(seconds)
            feed(p, "Microsoft Teams", "Incident \(Int(seconds))", at: seconds)
        }
        at(120)
        XCTAssertEqual(shortcutRuns.count, 1, "tier 4 ran it once")
        XCTAssertEqual(p.unresolvedShortcutFailure?.at, t0 + 120)
        XCTAssertEqual(p.unresolvedShortcutFailure?.reason, notInstalled)
        XCTAssertEqual(p.history.entries.last?.escalation?.final, .shortcutFailed(name: "Page me", reason: notInstalled))
        XCTAssertEqual(p.history.entries.last?.escalation?.finalCount, 1)

        at(140)
        feed(p, "Microsoft Teams", "Incident 140", at: 140)
        XCTAssertEqual(shortcutRuns.count, 2, "the next match tries it again at once, inside the ten minutes")
        XCTAssertEqual(p.history.entries.last?.escalation?.finalCount, 2)
        XCTAssertEqual(p.unresolvedShortcutFailure?.at, t0 + 140,
                       "the re-page failed too, and is held as the first was, where it happened")
        XCTAssertEqual(p.unresolvedShortcutFailure?.shortcutName, "Page me")

        shortcutAnswer = .shortcutLaunched(name: "Page me")
        at(150)
        feed(p, "Microsoft Teams", "Incident 150", at: 150)
        XCTAssertEqual(shortcutRuns.count, 3)
        XCTAssertNil(p.unresolvedShortcutFailure, "a run of the same Shortcut that started clears it")
        XCTAssertEqual(ladders, 1, "all of it one escalation")
    }
}
