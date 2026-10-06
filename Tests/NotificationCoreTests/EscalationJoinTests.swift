import XCTest
@testable import NotificationCore

private let glass = AlertAction.sound(name: "Glass", gainDB: 0)
private let hero = AlertAction.sound(name: "Hero", gainDB: 0)

/// A match joining an escalation already running for its rule, as the
/// coordinator decides it (M5 plan, Task 5, Ruling 14, O11). Every clock is
/// `ManualScheduler`'s, and every closure a fake that records what it was
/// called with: no player, panel, process or timer is real. Fixtures are
/// invented text (§10.1).
///
/// These test the coordinator alone, and the pipeline's asking is tested in
/// `BurstPipelineTests`, so `match` below does what the pipeline does with a
/// match: ask first, and when nothing joins, play tier 1, which is the
/// pipeline's own alert and is counted in `firstAlerts` and not in `sounds`,
/// and begin. What the coordinator's closures played, a repeat, a final alert
/// or the alert of a match that joined and was not silent, is `sounds`.
@MainActor
final class EscalationJoinTests: XCTestCase {
    private var clock: ManualScheduler!
    private var sounds: [String] = []
    private var spoken: [String] = []
    private var soundOutcome: (String) -> AlertOutcome = { .played(sound: $0, gainDB: 0, outputSilent: false) }
    private var soundAndSpeakOutcome: AlertOutcome?
    private var panels: [[(EscalationID, EscalationSummary)]] = []
    private var records: [(UUID, EscalationSummary)] = []
    private var retirements: [UUID] = []
    private var power: [String] = []
    /// How many times an idle escalation stopped the player, which it does only when it owns it.
    private var playerStopped = 0
    private var ownership = PlayerOwnership()
    private var shortcutRuns: [(name: String, report: (FinalOutcome) -> Void)] = []
    private var shortcutNotifications: [CapturedNotification] = []
    /// The awake time at which each Shortcut run started.
    private var shortcutTimes: [TimeInterval] = []
    private var shortcutsReportAtOnce: FinalOutcome?
    private var onSound: (() -> Void)?
    private var onRecord: ((UUID, EscalationSummary) -> Void)?
    /// What tier 1 played, for the pipeline, which the coordinator does not see.
    private var firstAlerts = 0
    private var begun: [(id: EscalationID, entry: UUID)] = []

    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let heard = AlertOutcome.played(sound: "Glass", gainDB: 0, outputSilent: false)
    private let pageMe = FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me"))

    override func setUp() {
        clock = ManualScheduler()
        sounds = []
        spoken = []
        soundOutcome = { .played(sound: $0, gainDB: 0, outputSilent: false) }
        soundAndSpeakOutcome = nil
        panels = []
        records = []
        retirements = []
        power = []
        playerStopped = 0
        ownership = PlayerOwnership()
        shortcutRuns = []
        shortcutNotifications = []
        shortcutTimes = []
        shortcutsReportAtOnce = nil
        onSound = nil
        onRecord = nil
        firstAlerts = 0
        begun = []
    }

    // MARK: - The harness

    /// Wired as the app wires it: the sound closures tell the player's ownership
    /// that an escalation's alert is what plays, and an idle escalation stops
    /// the player only when it owns it.
    private func coordinator(threshold: TimeInterval = 300, policy: BurstPolicy = .standard) -> EscalationCoordinator {
        EscalationCoordinator(
            scheduler: clock,
            playSound: { [unowned self] name, _ in
                sounds.append(name)
                onSound?()
                let outcome = soundOutcome(name)
                ownership.alertSetOff(outcome, byEscalation: true)
                return outcome
            },
            speak: { [unowned self] text, speech in
                sounds.append("speech:\(speech.voiceIdentifier)")
                spoken.append(text)
                onSound?()
                let outcome = AlertOutcome.spoke(text: text, voice: speech.voiceIdentifier, gainDB: 0, outputSilent: false)
                ownership.alertSetOff(outcome, byEscalation: true)
                return outcome
            },
            playAndSpeak: { [unowned self] name, _, text, speech in
                sounds.append("\(name)+speech")
                spoken.append(text)
                onSound?()
                let outcome = soundAndSpeakOutcome ?? .playedAndSpoke(
                    sound: name, soundGainDB: 0, text: text, voice: speech.voiceIdentifier, speechGainDB: 0,
                    outputSilent: false)
                ownership.alertSetOff(outcome, byEscalation: true)
                return outcome
            },
            runShortcut: { [unowned self] name, notification, report in
                shortcutNotifications.append(notification)
                shortcutTimes.append(clock.awakeTime())
                if let outcome = shortcutsReportAtOnce { report(outcome) } else { shortcutRuns.append((name, report)) }
            },
            updatePanel: { [unowned self] rows in panels.append(rows) },
            recordSummary: { [unowned self] entry, summary in
                records.append((entry, summary))
                onRecord?(entry, summary)
            },
            retired: { [unowned self] entry in retirements.append(entry) },
            beginPowerAssertion: { [unowned self] in power.append("begin") },
            endPowerAssertion: { [unowned self] in power.append("end") },
            silenceIfIdle: { [unowned self] in
                if ownership.escalationOwnsIt { playerStopped += 1 }
            },
            stalenessThreshold: threshold,
            burstPolicy: policy)
    }

    private func rule(_ name: String, _ ladder: Escalation?, id: UUID = UUID(), alert: AlertAction? = glass) -> Rule {
        Rule(id: id, name: name, condition: .field(.app, .equals, "Microsoft Teams"), alert: alert, escalation: ladder)
    }

    private func rule(_ ladder: Escalation?) -> Rule { rule("On-call mentions", ladder) }

    private func repeating(every interval: TimeInterval = 30, maxRepeats: Int? = nil,
                           maxDuration: TimeInterval? = nil) -> RepeatAlert {
        RepeatAlert(action: hero, intervalSeconds: interval, maxRepeats: maxRepeats, maxDurationSeconds: maxDuration)
    }

    /// A match, told apart from every other by what each of its four fields says.
    private func notification(_ n: Int) -> CapturedNotification {
        CapturedNotification(
            timestamp: start, appNameGuess: "Microsoft Teams", title: "Incident \(n)", subtitle: "Channel \(n)",
            body: "Body \(n)", rawText: "Microsoft Teams, Incident \(n), Body \(n)", subrole: "AXNotificationCenterAlert")
    }

    private enum Arrival: Equatable {
        case joined(EscalationJoin)
        case began(EscalationID)

        var join: EscalationJoin? {
            if case .joined(let join) = self { return join }
            return nil
        }

        var beganID: EscalationID? {
            if case .began(let id) = self { return id }
            return nil
        }
    }

    /// What the pipeline will do with a match: ask whether it joins, and when
    /// nothing does, play tier 1 and begin.
    @discardableResult
    private func match(_ ladder: EscalationCoordinator, _ rule: Rule, _ n: Int = 0,
                       tier1: AlertOutcome? = AlertOutcome.played(sound: "Glass", gainDB: 0, outputSilent: false),
                       file: StaticString = #filePath, line: UInt = #line) -> Arrival {
        if let join = ladder.join(rule: rule, notification: notification(n)) { return .joined(join) }
        firstAlerts += 1
        if let tier1 { ownership.alertSetOff(tier1, byEscalation: true) }
        let entry = UUID()
        guard let id = ladder.begin(rule: rule, notification: notification(n), entryID: entry, tier1Outcome: tier1) else {
            XCTFail("a rule with a ladder begins one", file: file, line: line)
            return .began(EscalationID())
        }
        begun.append((id, entry))
        return .began(id)
    }

    /// Moves both clocks on to an absolute awake time, firing what falls due on
    /// the way.
    private func at(_ seconds: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(seconds, clock.awakeTime(), "time only goes forward", file: file, line: line)
        clock.advance(by: seconds - clock.awakeTime())
    }

    /// A new clock and nothing recorded, for a test that tries several cases in
    /// turn: a ladder left on an old clock would go on repeating into the next
    /// case's `sounds`.
    private func freshWorld(lateness: TimeInterval = 0) {
        setUp()
        clock.lateness = lateness
    }

    private func latest(_ entry: UUID) -> EscalationSummary? { records.last { $0.0 == entry }?.1 }

    /// Delivers the report of the Shortcut run that started `index`th (from 0). A run that has not started fails
    /// the test where it is asked for, and does not stop the others by indexing past the end.
    private func report(run index: Int, _ outcome: FinalOutcome, file: StaticString = #filePath, line: UInt = #line) {
        guard index < shortcutRuns.count else {
            return XCTFail("run \(index + 1) never started: only \(shortcutRuns.count) did", file: file, line: line)
        }
        shortcutRuns[index].report(outcome)
    }

    private var repeats: Int { sounds.filter { $0 == "Hero" }.count }
    private var ownAlerts: Int { sounds.filter { $0 == "Glass" }.count }

    private func kept(_ ladder: EscalationCoordinator, _ id: EscalationID) throws -> EscalationCoordinator.Bookkeeping {
        try XCTUnwrap(ladder.bookkeeping(of: id), "the escalation is no longer held")
    }

    // MARK: - One repeating ladder

    func testAMatchEveryThirtySecondsForAnHourOnAWakeMeShapedLadderIsOneEscalationWithItsCapKept() throws {
        let ladder = coordinator()
        // Wake me's timing, with the time limit that keeps the cap under test.
        let theRule = rule(Escalation(tier2: PanelAlert(delaySeconds: 5),
                                      tier3: repeating(every: 15, maxRepeats: nil, maxDuration: 3600)))
        for index in 0..<120 {
            at(Double(index) * 30)
            let arrival = match(ladder, theRule, index)
            if index == 0 {
                XCTAssertEqual(begun.count, 1)
            } else {
                XCTAssertEqual(arrival.join?.matchNumber, index + 1, "match \(index) joins and is counted")
            }
        }
        at(3599)
        let entry = try XCTUnwrap(begun.first).entry
        XCTAssertEqual(begun.count, 1, "one begin")
        XCTAssertEqual(firstAlerts, 1, "one tier 1 sound")
        XCTAssertEqual(ladder.trackedCount, 1, "one repeating ladder throughout")
        XCTAssertEqual(latest(entry)?.matchCount, 120)
        XCTAssertEqual(clock.pendingCount, 1, "only its repeat is armed: a join arms nothing")
        at(3600)
        XCTAssertEqual(repeats, 240, "one repeat every 15 seconds for the hour, and not one more for any match")
        XCTAssertEqual(latest(entry)?.status, .capped(at: start + 3600))
        XCTAssertEqual(sounds.filter { $0 != "Hero" }, [], "and no joined match played an alert of its own: a repeat was always near")

        let second = match(ladder, theRule, 120)
        guard case .began = second else { return XCTFail("a capped escalation is never joined: \(second)") }
        XCTAssertEqual(begun.count, 2, "the next match begins a second ladder")
        XCTAssertEqual(firstAlerts, 2, "and sounds tier 1")
        XCTAssertEqual(ladder.trackedCount, 2)
        at(3630)
        XCTAssertEqual(match(ladder, theRule, 121).join?.matchNumber, 2, "and that one is joined in its turn")
    }

    func testWakeMeItselfOverTheSameHourAndAMatchAt61MinutesIsStillOneRepeatingJoinedEscalation() throws {
        let ladder = coordinator()
        let wakeMe = try XCTUnwrap(EscalationEditing.Preset.wakeMe.ladder(repeating: hero))
        XCTAssertNil(wakeMe.tier3?.maxDurationSeconds, "Wake me has no time limit")
        XCTAssertNil(wakeMe.tier3?.maxRepeats, "and no limit on repeats")
        let theRule = rule(wakeMe)
        for index in 0..<120 {
            at(Double(index) * 30)
            match(ladder, theRule, index)
        }
        at(3660)
        XCTAssertEqual(match(ladder, theRule, 120).join?.matchNumber, 121, "a match at 61 minutes joins")
        XCTAssertEqual(begun.count, 1, "still one begin")
        XCTAssertEqual(firstAlerts, 1)
        XCTAssertEqual(repeats, 244, "still repeating, every 15 seconds")
        XCTAssertEqual(records.last?.1.status, .live, "and it never caps")

        at(86_400)
        XCTAssertEqual(match(ladder, theRule, 121).join?.matchNumber, 122, "a day on it is the same escalation")
        XCTAssertEqual(repeats, 5760)
        XCTAssertEqual(records.last?.1.status, .live)
        XCTAssertEqual(ladder.trackedCount, 1)
    }

    func testAShortcutAfter120SecondsOverTheHourRunsAt120AndThenNoMoreOftenThanEvery600WithTheFieldsOfTheMatchThatCausedIt() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier2: PanelAlert(delaySeconds: 5),
                                      tier3: repeating(every: 15, maxRepeats: nil, maxDuration: 3600), tier4: pageMe))
        var ran: [Int] = []
        for index in 0..<120 {
            at(Double(index) * 30)
            if let join = match(ladder, theRule, index).join, join.ranShortcut { ran.append(join.matchNumber) }
        }
        at(3600)
        XCTAssertEqual(shortcutTimes, [120, 720, 1320, 1920, 2520, 3120],
                       "tier 4 at 120 s, and then the page owed to the matches since, 600 s or more after the last run started")
        XCTAssertEqual(shortcutNotifications, [0, 23, 43, 63, 83, 103].map(notification),
                       "tier 4's with the first match's fields, and each later run with the fields of the newest match since the last run")
        XCTAssertEqual(ran, [], "a match every 30 s is always owed its page, which its timer sends at the 600 s: no join runs it")
        XCTAssertEqual(begun.count, 1)
    }

    // MARK: - No repeat, one escalation, every alert heard

    func testAGentleLadderUnderABurstOf20MatchesFiveSecondsApartSoundsForEachBeginsOneAndCounts20() throws {
        let ladder = coordinator()
        let gentle = try XCTUnwrap(EscalationEditing.Preset.gentle.ladder(repeating: hero))
        XCTAssertNil(gentle.tier3, "nothing repeats")
        let theRule = rule(gentle)
        var arrivals: [Arrival] = []
        for index in 0..<20 {
            at(Double(index) * 5)
            arrivals.append(match(ladder, theRule, index))
        }
        XCTAssertEqual(begun.count, 1)
        XCTAssertEqual(firstAlerts, 1, "the first match sounded tier 1")
        XCTAssertEqual(ownAlerts, 19, "and each of the other 19 played its own alert: nothing repeats, so none is covered")
        XCTAssertEqual(arrivals.dropFirst().compactMap { $0.join?.alert }.count, 19, "and each join says what its alert did")
        XCTAssertEqual(arrivals.dropFirst().compactMap { $0.join?.matchNumber }, Array(2...20))
        XCTAssertEqual(latest(try XCTUnwrap(begun.first).entry)?.matchCount, 20)
        XCTAssertEqual(ladder.trackedCount, 1)
        XCTAssertEqual(panels.last?.map(\.1.matchCount), [20], "the panel row's count was republished in place")
    }

    func testAPanelAndAShortcutOnlyDoTheSameAndRunTheShortcutOnce() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier2: PanelAlert(delaySeconds: 10),
                                      tier4: FinalAlert(afterSeconds: 30, action: .shortcut(name: "Page me"))))
        for index in 0..<20 {
            at(Double(index) * 5)
            match(ladder, theRule, index)
        }
        XCTAssertEqual(begun.count, 1)
        XCTAssertEqual(ownAlerts, 19, "every match is heard")
        XCTAssertEqual(latest(try XCTUnwrap(begun.first).entry)?.matchCount, 20)
        XCTAssertEqual(shortcutTimes, [30], "and one page for the burst, at tier 4's time")
        XCTAssertEqual(shortcutNotifications, [notification(0)])
    }

    func testAMatchTheQuietGapAfterTheLastJoinsAndOneMoreThanThatAfterBeginsItsOwnAndPagesAgain() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier2: PanelAlert(delaySeconds: 10),
                                      tier4: FinalAlert(afterSeconds: 30, action: .shortcut(name: "Page me"))))
        match(ladder, theRule, 0)
        at(60)
        XCTAssertNotNil(match(ladder, theRule, 1).join, "60 seconds after the last is no longer ago than the gap")
        at(110)
        XCTAssertNotNil(match(ladder, theRule, 2).join, "and the gap rolls: it is measured from the last match, not the first")
        at(171)
        guard case .began = match(ladder, theRule, 3) else { return XCTFail("61 seconds after the last begins its own") }
        XCTAssertEqual(begun.count, 2)
        XCTAssertEqual(firstAlerts, 2)
        at(300)
        XCTAssertEqual(shortcutTimes, [30, 201], "and the new escalation pages again at its own tier 4")
        XCTAssertEqual(shortcutNotifications, [notification(0), notification(3)])
        XCTAssertEqual(latest(begun[0].entry)?.matchCount, 3)
        XCTAssertEqual(latest(begun[1].entry)?.matchCount, 1)
    }

    func testAMatchEveryFiftySecondsForAnHourIsOneEscalationPagedAtTier4AndThenNoMoreOftenThanEveryTenMinutes() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier2: PanelAlert(delaySeconds: 10), tier4: pageMe))
        for index in 0..<72 {
            at(Double(index) * 50)
            match(ladder, theRule, index)
        }
        XCTAssertEqual(begun.count, 1, "no match of the hour is more than the gap after the one before")
        XCTAssertEqual(latest(try XCTUnwrap(begun.first).entry)?.matchCount, 72)
        XCTAssertEqual(shortcutTimes, [120, 720, 1320, 1920, 2520, 3120],
                       "tier 4, and then the page owed to the matches since, 600 seconds after each run started")
        XCTAssertEqual(shortcutNotifications, [0, 14, 26, 38, 50, 62].map(notification),
                       "each with the fields of the newest match to have come before it")
    }

    func testALadderWhoseTimeLimitIsShorterThanOneIntervalIsCappedAtOnceAndEachMatchBeginsItsOwn() {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 30, maxRepeats: nil, maxDuration: 10)))
        for index in 0..<3 {
            at(Double(index) * 5)
            guard case .began = match(ladder, theRule, index) else { return XCTFail("there is no repeat to cover a match") }
        }
        XCTAssertEqual(begun.count, 3)
        XCTAssertEqual(firstAlerts, 3, "each sounded as a match did before there was joining")
        XCTAssertEqual(ladder.trackedCount, 3)
    }

    // MARK: - Joining is not silence

    func testWithARepeatEvery300SecondsAMatchPlaysItsOwnAlertUntilARepeatIsDueWithin60AndThenJoinsSilently() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 300)))
        match(ladder, theRule, 0)
        for (time, index) in [(10.0, 1), (100.0, 2), (239.0, 3)] {
            at(time)
            let join = try XCTUnwrap(match(ladder, theRule, index).join, "joins at \(time)")
            XCTAssertEqual(join.alert, heard, "and plays its own first alert: the repeat is more than 60 seconds away")
        }
        XCTAssertEqual(sounds, ["Glass", "Glass", "Glass"])
        for (time, index) in [(240.0, 4), (299.0, 5)] {
            at(time)
            let join = try XCTUnwrap(match(ladder, theRule, index).join, "joins at \(time)")
            XCTAssertNil(join.alert, "a repeat is due within 60 seconds and tier 1 was heard: it stands in")
        }
        XCTAssertEqual(sounds, ["Glass", "Glass", "Glass"], "nothing was played for those two")
        XCTAssertEqual(firstAlerts, 1)
        at(300)
        XCTAssertEqual(sounds.last, "Hero", "the repeat itself")
        at(301)
        XCTAssertEqual(try XCTUnwrap(match(ladder, theRule, 6).join).alert, heard,
                       "and the next is 300 seconds away again, so a match after it plays its own")
        at(540)
        XCTAssertNil(try XCTUnwrap(match(ladder, theRule, 7).join).alert, "and is silent again 60 seconds before")
    }

    func testWithAnIntervalOf120SecondsTheThresholdIsExactAtARepeatDueIn61AndIn59() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 120)))
        match(ladder, theRule, 0)
        at(59)
        XCTAssertEqual(try XCTUnwrap(match(ladder, theRule, 1).join).alert, heard, "due in 61 s: audible")
        at(60)
        XCTAssertNil(try XCTUnwrap(match(ladder, theRule, 2).join).alert, "due in exactly 60 s: within the window, silent")
        at(61)
        XCTAssertNil(try XCTUnwrap(match(ladder, theRule, 3).join).alert, "due in 59 s: silent")
    }

    func testTheSilentJoinWindowIsTheOneThePolicyGivesAndNotAFixedSixty() throws {
        let ladder = coordinator(policy: BurstPolicy(quietGap: 60, silentJoinWindow: 10, repageTime: 600))
        let theRule = rule(Escalation(tier3: repeating(every: 30)))
        match(ladder, theRule, 0)
        at(19)
        XCTAssertEqual(try XCTUnwrap(match(ladder, theRule, 1).join).alert, heard, "due in 11 s, and the window is 10")
        at(20)
        XCTAssertNil(try XCTUnwrap(match(ladder, theRule, 2).join).alert, "due in 10 s")
    }

    func testAJoinedMatchSpeaksItsOwnLineWhenItIsNotSilentAndAMatchThatIsSilentVoicesNothing() throws {
        let line = SpeechAction(voiceIdentifier: "com.example.voice", template: "{title}")
        let ladder = coordinator()
        let theRule = rule("On-call mentions", Escalation(tier3: repeating(every: 300)),
                           alert: .soundAndSpeak(soundName: "Glass", soundGainDB: 0, speech: line))
        match(ladder, theRule, 0)
        at(10)
        XCTAssertNotNil(match(ladder, theRule, 1).join?.alert)
        XCTAssertEqual(spoken, ["Incident 1"], "its spoken line, rendered from its own notification")
        XCTAssertEqual(sounds, ["Glass+speech"])
        at(250)
        XCTAssertNil(match(ladder, theRule, 2).join?.alert)
        XCTAssertEqual(spoken, ["Incident 1"], "a silent join is not voiced at all")
        XCTAssertEqual(sounds, ["Glass+speech"])
    }

    func testAfterARepeatThatWasNotHeardTheNextMatchPlaysItsOwnWhateverTheIntervalAndAfterAGoodOneItIsSilentAgain() throws {
        let line = SpeechAction(voiceIdentifier: "com.example.voice", template: "{title}")
        let repeatWithSpeech = AlertAction.soundAndSpeak(soundName: "Hero", soundGainDB: 0, speech: line)
        // Only the repeat's own sound is spoiled: the joined match's alert is Glass.
        let cases: [(label: String, action: AlertAction, spoil: () -> Void)] = [
            ("a failed repeat", hero, {
                self.soundOutcome = { $0 == "Hero" ? .failed("sound \"Hero\" was not found")
                    : .played(sound: $0, gainDB: 0, outputSilent: false) }
            }),
            ("a repeat into a muted output", hero, {
                self.soundOutcome = { .played(sound: $0, gainDB: 0, outputSilent: $0 == "Hero") }
            }),
            ("a repeat whose speech was not said", repeatWithSpeech, {
                self.soundAndSpeakOutcome = .playedButNotSpoken(sound: "Hero", gainDB: 0, reason: "no voice",
                                                                outputSilent: false)
            }),
        ]
        for (label, action, spoil) in cases {
            freshWorld()
            let base = clock.awakeTime()
            let ladder = coordinator()
            let theRule = rule(Escalation(tier3: RepeatAlert(action: action, intervalSeconds: 30, maxRepeats: nil,
                                                             maxDurationSeconds: nil)))
            match(ladder, theRule, 0)
            spoil()
            at(base + 30)
            XCTAssertEqual(sounds.count, 1, "\(label): the repeat played")
            at(base + 40)
            XCTAssertEqual(try XCTUnwrap(match(ladder, theRule, 1).join).alert, heard,
                           "\(label): the repeat is 20 s away, and the next match still plays its own")
            soundOutcome = { .played(sound: $0, gainDB: 0, outputSilent: false) }
            soundAndSpeakOutcome = nil
            at(base + 60)
            at(base + 70)
            XCTAssertNil(try XCTUnwrap(match(ladder, theRule, 2).join).alert,
                         "\(label): after a repeat that was heard, the next is silent again")
        }
    }

    func testBeforeAnyRepeatTier1sOutcomeDecidesAndOnlyAnAudibleOneLetsAMatchJoinSilently() throws {
        let sound = AlertOutcome.played(sound: "Glass", gainDB: 0, outputSilent: false)
        let said = AlertOutcome.spoke(text: "x", voice: "v", gainDB: 0, outputSilent: false)
        let both = AlertOutcome.playedAndSpoke(sound: "Glass", soundGainDB: 0, text: "x", voice: "v", speechGainDB: 0,
                                               outputSilent: false)
        let audible: [AlertOutcome] = [sound, said, both]
        let notHeard: [AlertOutcome?] = [
            nil,
            .played(sound: "Glass", gainDB: 0, outputSilent: true),
            .spoke(text: "x", voice: "v", gainDB: 0, outputSilent: true),
            .playedAndSpoke(sound: "Glass", soundGainDB: 0, text: "x", voice: "v", speechGainDB: 0, outputSilent: true),
            .failed("sound \"Glass\" was not found"), .couldNotSpeak("no voice"), .silentByRule, .noAlertSet,
            .playedButNotSpoken(sound: "Glass", gainDB: 0, reason: "no voice", outputSilent: false),
            .spokeButNotPlayed(text: "x", voice: "v", gainDB: 0, reason: "no sound", outputSilent: false),
        ]
        for outcome in audible {
            freshWorld()
            let ladder = coordinator()
            let theRule = rule(Escalation(tier3: repeating(every: 30)))
            match(ladder, theRule, 0, tier1: outcome)
            at(clock.awakeTime() + 10)
            XCTAssertNil(try XCTUnwrap(match(ladder, theRule, 1).join).alert,
                         "a repeat is 20 s away and tier 1 was heard: \(outcome)")
        }
        for outcome in notHeard {
            freshWorld()
            let ladder = coordinator()
            let theRule = rule(Escalation(tier3: repeating(every: 30)))
            match(ladder, theRule, 0, tier1: outcome)
            at(clock.awakeTime() + 10)
            XCTAssertEqual(try XCTUnwrap(match(ladder, theRule, 1).join).alert, heard,
                           "a repeat is 20 s away, but nothing is shown to have been heard: \(String(describing: outcome))")
        }
    }

    func testASilentRepeatStandsInForNothingSoAMatchBeforeItsFirstPlaysItsOwnAlertAndSpeaksItsLine() throws {
        // A Custom ladder can repeat nothing (`EscalationEditing.Preset.matches`
        // says a silent repeat "repeats nothing"). Its repeat is known to be
        // inaudible, so tier 1 having been heard is no proof that anything is
        // about to sound for a match that joins just before it.
        let line = SpeechAction(voiceIdentifier: "com.example.voice", template: "{title}")
        let silentRepeat = RepeatAlert(action: .silent, intervalSeconds: 30, maxRepeats: nil, maxDurationSeconds: nil)
        let ladder = coordinator()
        let theRule = rule("On-call mentions", Escalation(tier3: silentRepeat),
                           alert: .soundAndSpeak(soundName: "Glass", soundGainDB: 0, speech: line))
        match(ladder, theRule, 0)
        at(10)
        XCTAssertNotNil(match(ladder, theRule, 1).join?.alert,
                        "the repeat is due in 20 s and tier 1 was heard, but the repeat is silent: the match plays its own")
        XCTAssertEqual(spoken, ["Incident 1"], "and its spoken line is voiced")
        at(30)
        XCTAssertEqual(sounds, ["Glass+speech"], "the silent repeat sounded nothing")
        at(40)
        XCTAssertNotNil(match(ladder, theRule, 2).join?.alert, "and after it, the last repeat was not heard either")
        XCTAssertEqual(spoken, ["Incident 1", "Incident 2"])
    }

    func testAJoinedMatchesOwnAlertIsTheEscalationsToThePlayerAndASilentOneTakesNothing() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 300)))
        match(ladder, theRule, 0)
        XCTAssertTrue(ownership.escalationOwnsIt, "tier 1, as the app tells it")
        ownership.alertSetOff(heard, byEscalation: false)
        XCTAssertFalse(ownership.escalationOwnsIt, "an ordinary rule's alert has played since")
        at(10)
        XCTAssertNotNil(match(ladder, theRule, 1).join?.alert)
        XCTAssertTrue(ownership.escalationOwnsIt, "the joined match's alert went through the coordinator's own closures")
        ladder.acknowledgeAll()
        XCTAssertEqual(playerStopped, 1, "so Acknowledge All stops it")

        // And a silent join plays nothing, so it takes nothing from whoever has the player.
        let quiet = coordinator()
        let nearRepeat = rule(Escalation(tier3: repeating(every: 30)))
        match(quiet, nearRepeat, 1)
        ownership.alertSetOff(heard, byEscalation: false)
        at(clock.awakeTime() + 10)
        XCTAssertNil(match(quiet, nearRepeat, 2).join?.alert)
        XCTAssertFalse(ownership.escalationOwnsIt, "the silent join left the player to its owner")
        quiet.acknowledgeAll()
        XCTAssertEqual(playerStopped, 1, "and Acknowledge All stopped nothing more")
    }

    // MARK: - Boundaries

    func testWithALimitOfThreeRepeatsAMatchAt89SecondsJoinsAndOneAfterTheThirdFiresAt90BeginsANewLadder() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 30, maxRepeats: 3)))
        match(ladder, theRule, 0)
        at(89)
        let join = try XCTUnwrap(match(ladder, theRule, 1).join, "the third repeat is still to come")
        XCTAssertEqual(join.alert, heard, "and it is the last, so the match plays its own")
        at(90)
        XCTAssertEqual(repeats, 3)
        XCTAssertEqual(records.last?.1.status, .capped(at: start + 90))
        guard case .began = match(ladder, theRule, 2) else { return XCTFail("a capped escalation is never joined") }
        XCTAssertEqual(firstAlerts, 2, "the new ladder sounded tier 1")
        XCTAssertEqual(begun.count, 2)
        at(120)
        XCTAssertEqual(repeats, 4, "and it repeats on its own account")
    }

    func testAMatchAtTheInstantOfTheFirstRepeatBeforeItFiresJoinsSilentlyOnlyIfTier1WasHeard() throws {
        // A real timer is a few milliseconds late, so a match can be handled
        // while a repeat that is due has not run.
        let table: [(label: String, tier1: AlertOutcome, silent: Bool)] = [
            ("heard", heard, true),
            ("silent", .silentByRule, false),
            ("failed", .failed("sound \"Glass\" was not found"), false),
            ("into a muted output", .played(sound: "Glass", gainDB: 0, outputSilent: true), false),
        ]
        for row in table {
            freshWorld(lateness: 0.0035)
            let base = clock.awakeTime()
            let ladder = coordinator()
            let theRule = rule(Escalation(tier3: repeating(every: 30, maxRepeats: 3)))
            match(ladder, theRule, 0, tier1: row.tier1)
            at(base + 30)
            let before = repeats
            let join = try XCTUnwrap(match(ladder, theRule, 1).join, row.label)
            XCTAssertEqual(repeats, before, "\(row.label): the repeat is due and has not fired")
            XCTAssertEqual(join.alert == nil, row.silent, "tier 1 \(row.label)")
        }
    }

    func testAMatchFiveSecondsBeforeTheLastRepeatPlaysItsOwnAndOneFiveBeforeTheSecondJoinsSilently() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 30, maxRepeats: 3)))
        match(ladder, theRule, 0)
        at(55)
        XCTAssertNil(try XCTUnwrap(match(ladder, theRule, 1).join).alert, "the second of three: not the last")
        at(85)
        XCTAssertEqual(try XCTUnwrap(match(ladder, theRule, 2).join).alert, heard,
                       "the third of three: after it nothing would sound for this match")
    }

    func testTheTimeLimitMakesTheLastRepeatToo() throws {
        let ladder = coordinator()
        // Repeats at 30, 60 and 90; 120 is past the limit of 100.
        let theRule = rule(Escalation(tier3: repeating(every: 30, maxRepeats: nil, maxDuration: 100)))
        match(ladder, theRule, 0)
        at(55)
        XCTAssertNil(try XCTUnwrap(match(ladder, theRule, 1).join).alert, "the second repeat is not the last")
        at(85)
        XCTAssertEqual(try XCTUnwrap(match(ladder, theRule, 2).join).alert, heard, "the third is the last by time")
    }

    // MARK: - The same ladder

    func testAMatchWhoseRuleNowCarriesADifferentLadderBeginsItsOwnWhileTheOldKeepsRepeating() throws {
        let ladder = coordinator()
        let original = rule(Escalation(tier3: repeating(every: 30)))
        match(ladder, original, 0)
        var otherInterval = original
        otherInterval.escalation = Escalation(tier3: repeating(every: 45))
        var withFinalAdded = original
        withFinalAdded.escalation = Escalation(tier3: repeating(every: 30), tier4: pageMe)

        at(10)
        guard case .began = match(ladder, otherInterval, 1) else { return XCTFail("another interval is another ladder") }
        guard case .began = match(ladder, withFinalAdded, 2) else { return XCTFail("a tier 4 added is another ladder") }
        XCTAssertEqual(begun.count, 3)
        XCTAssertEqual(firstAlerts, 3)
        at(60)
        XCTAssertEqual(repeats, 2 + 1 + 1,
                       "the old one repeated at 30 and 60, and the others on their own timers, at 55 and at 40")

        // An equal ladder, built apart, joins; each rule's ladder joins its own.
        var equal = original
        equal.escalation = Escalation(tier3: RepeatAlert(action: hero, intervalSeconds: 30, maxRepeats: nil,
                                                         maxDurationSeconds: nil))
        XCTAssertEqual(try XCTUnwrap(match(ladder, equal, 3).join).matchNumber, 2)
        XCTAssertEqual(try XCTUnwrap(match(ladder, otherInterval, 4).join).matchNumber, 2)
        XCTAssertEqual(try XCTUnwrap(match(ladder, withFinalAdded, 5).join).matchNumber, 2)
        XCTAssertEqual(begun.count, 3)
    }

    // MARK: - Tier 4 and re-paging, whether a join runs the Shortcut

    func testAMatchThatJoinsBeforeTier4RunsRaisesTheCountAndRunsNothingAndIsOwedNothing() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(60)
        let timers = clock.pendingCount
        let join = try XCTUnwrap(match(ladder, theRule, 1).join)
        XCTAssertEqual(join.matchNumber, 2)
        XCTAssertFalse(join.ranShortcut)
        XCTAssertEqual(shortcutNotifications, [], "tier 4 has not run, and will")
        XCTAssertNil(try kept(ladder, id).owedPage, "and it will page with the first match's fields: nothing is owed")
        XCTAssertEqual(clock.pendingCount, timers, "no re-page timer is armed")
        XCTAssertEqual(latest(try XCTUnwrap(begun.first).entry)?.matchCount, 2)
        at(120)
        XCTAssertEqual(shortcutNotifications, [notification(0)], "and when it does it is given the first match's fields")
    }

    func testTheFirstJoinAtTenMinutesRunsTheShortcutOnceMoreWithItsOwnFourFieldsAndAnotherAtOnceDoesNot() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        XCTAssertEqual(shortcutTimes, [120])
        // No match came before it, so none is owed a page and no timer is armed: this join is the first.
        at(720)
        let join = try XCTUnwrap(match(ladder, theRule, 3).join)
        XCTAssertTrue(join.ranShortcut, "600 s: at least the re-page time")
        XCTAssertEqual(shortcutTimes, [120, 720])
        let given = try XCTUnwrap(shortcutNotifications.last)
        XCTAssertEqual([given.appNameGuess, given.title, given.subtitle, given.body],
                       ["Microsoft Teams", "Incident 3", "Channel 3", "Body 3"], "the four fields of the joining match")
        XCTAssertEqual(try kept(ladder, id).lastShortcutRunAt, EscalationCoordinator.Stamp(wall: start + 720, awake: 720),
                       "and the run's time is recorded, on both clocks")
        XCTAssertNil(try kept(ladder, id).owedPage, "and it left nothing owed")
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 4).join).ranShortcut, "another at once does not")
        at(725)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 5).join).ranShortcut)
        XCTAssertEqual(shortcutTimes, [120, 720])

        // 599 s is not enough: on a clock of its own, so that nothing that came before it is owed a page.
        freshWorld()
        let early = coordinator()
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        match(early, theRule, 0)
        at(120)
        at(719)
        XCTAssertFalse(try XCTUnwrap(match(early, theRule, 1).join).ranShortcut, "599 s after the run began")
        XCTAssertEqual(shortcutTimes, [120])
    }

    func testAMatchThatJoinsAfterAFailedRunRunsItAgainAtOnceAndNeverWhileARunIsPending() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        XCTAssertEqual(shortcutRuns.count, 1)
        report(run: 0, .shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed"))
        at(125)
        let again = try XCTUnwrap(match(ladder, theRule, 1).join)
        XCTAssertTrue(again.ranShortcut, "the last run failed: tried again at once, inside the 10 minutes")
        XCTAssertEqual(shortcutNotifications.last, notification(1))
        XCTAssertEqual(shortcutRuns.count, 2)

        at(131)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 2).join).ranShortcut,
                       "a run is pending, though the report that is held is still a failure")
        XCTAssertEqual(shortcutRuns.count, 2)
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(2), "and the match is owed a page instead")

        report(run: 1, .shortcutLaunched(name: "Page me"))
        at(140)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 3).join).ranShortcut,
                       "a run that started is not retried: it needs the re-page time")
        XCTAssertEqual(shortcutRuns.count, 2)
        XCTAssertEqual(latest(try XCTUnwrap(begun.first).entry)?.finalCount, 2, "each report that came was counted once")
    }

    func testAStormOf20MatchesHasOneRunInFlightAtATimeWhateverItsOutcome() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        match(ladder, theRule, 0)
        at(120)
        for index in 1...20 {
            at(120 + Double(index))
            XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, index).join).ranShortcut, "the run is still pending")
        }
        XCTAssertEqual(shortcutRuns.count, 1, "one in flight")

        // A Shortcut that always fails and reports at once. The page owed to the storm goes the moment the first run
        // reports its failure, and each match that arrives after the last reported is then tried again.
        shortcutsReportAtOnce = .shortcutFailed(name: "Page me", reason: "x")
        report(run: 0, .shortcutFailed(name: "Page me", reason: "x"))
        XCTAssertEqual(shortcutTimes.count, 2, "the owed page, run once however many matches were owed it")
        let before = shortcutTimes.count
        for index in 21...40 {
            at(120 + Double(index))
            XCTAssertTrue(try XCTUnwrap(match(ladder, theRule, index).join).ranShortcut, "the last run failed and none is pending")
        }
        XCTAssertEqual(shortcutTimes.count - before, 20)
        XCTAssertEqual(latest(try XCTUnwrap(begun.first).entry)?.finalCount, 22,
                       "the first report, the owed page's and one for each retry")
    }

    func testALadderWhoseTier4IsAnAlertRunsNothingWhenAMatchJoins() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: FinalAlert(afterSeconds: 60, action: .alert(glass))))
        match(ladder, theRule, 0)
        at(700)
        XCTAssertEqual(ownAlerts, 1, "tier 4's alert sounded once")
        let join = try XCTUnwrap(match(ladder, theRule, 1).join)
        XCTAssertFalse(join.ranShortcut)
        XCTAssertEqual(shortcutNotifications, [])
        XCTAssertEqual(ownAlerts, 1, "the repeat covers the match, and tier 4 is not fired again by a match")
    }

    func testARunsTimeIsReadOnBothClocksSoASetBackWallClockDoesNotHoldBackAPageAndASleepCountsTowardIt() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        match(ladder, theRule, 0)
        at(120)
        XCTAssertEqual(shortcutTimes, [120])

        clock.stepBack(by: 3600)
        at(719)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut, "599 s by the awake clock")
        at(720)
        XCTAssertEqual(shortcutTimes, [120, 720],
                       "600 s by the awake clock, whatever the wall clock was set to: an hour back does not hold the page off for an hour")

        // A sleep too short to convert, which only the wall clock counts, is time too.
        at(1000)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 2).join).ranShortcut, "280 s after the last run")
        clock.sleep(for: 250)
        at(1100)
        XCTAssertTrue(try XCTUnwrap(match(ladder, theRule, 3).join).ranShortcut,
                      "380 s awake and 630 s by the wall clock: a sleep that converts nothing still makes the run older")
        XCTAssertEqual(shortcutTimes, [120, 720, 1100])
        XCTAssertEqual(shortcutNotifications.last, notification(3))
    }

    // MARK: - Tier 4 and re-paging, where a page is owed

    /// A match that joins after tier 4 has run, and may not run it again, is owed
    /// a page, which one timer sends once the re-page time has passed since the
    /// last run started (M5 plan, Ruling 14, O11b). Times below are seconds from
    /// the start, so that 10:00 is 0 and 10:12 is 720.

    func testTheIsolatedIncidentIsPagedOnceAtTenTwelveWithTheTenSevenMatchsFieldsAndNotAgain() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        XCTAssertEqual(shortcutTimes, [120], "10:02: tier 4 runs the Shortcut")

        at(420)
        let timers = clock.pendingCount
        let join = try XCTUnwrap(match(ladder, theRule, 1).join)
        XCTAssertEqual(join.matchNumber, 2, "10:07: it joins, with a count of 2")
        XCTAssertFalse(join.ranShortcut, "and nothing runs now")
        XCTAssertEqual(shortcutTimes, [120])
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(1), "it is owed a page, and its notification is kept for it")
        XCTAssertEqual(clock.pendingCount, timers + 1, "and the one re-page timer is armed")
        XCTAssertEqual(latest(try XCTUnwrap(begun.first).entry)?.matchCount, 2)

        at(719)
        XCTAssertEqual(shortcutTimes, [120], "nothing follows it before 10:12")
        at(720)
        XCTAssertEqual(shortcutTimes, [120, 720], "10:12: the Shortcut runs once")
        XCTAssertEqual(shortcutNotifications, [notification(0), notification(1)], "with the 10:07 match's four fields")
        XCTAssertNil(try kept(ladder, id).owedPage, "and nothing is owed any more")
        XCTAssertEqual(clock.pendingCount, timers, "the re-page timer has gone")

        at(7200)
        XCTAssertEqual(shortcutTimes, [120, 720], "and not again")
        XCTAssertEqual(latest(try XCTUnwrap(begun.first).entry)?.finalCount, 2, "tier 4's report and the page's, each counted once")
    }

    func testMatchesAtTenFiveAndTenEightOweOnePageSentAtTenTwelveWithTheLaterMatchsFields() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        at(300)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut)
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(1))
        let timers = clock.pendingCount
        at(480)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 2).join).ranShortcut)
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(2), "the newer match replaces the older")
        XCTAssertEqual(clock.pendingCount, timers, "and the one timer already armed is the one that sends it")

        at(719)
        XCTAssertEqual(shortcutTimes, [120])
        at(720)
        XCTAssertEqual(shortcutTimes, [120, 720], "one page, at 10:12")
        XCTAssertEqual(shortcutNotifications, [notification(0), notification(2)], "with the later match's fields")
        at(3000)
        XCTAssertEqual(shortcutTimes, [120, 720])
    }

    func testAcknowledgingAtTenTenCancelsThePageOwedAndNothingRunsAtTenTwelve() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        at(420)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut)
        XCTAssertNotNil(try kept(ladder, id).owedPage)

        at(600)
        ladder.acknowledge(id)
        XCTAssertEqual(clock.pendingCount, 0, "every timer is cancelled, the re-page timer with the rest")
        XCTAssertNil(ladder.bookkeeping(of: id), "its Shortcut had reported, so it is retired and nothing of it is kept")
        XCTAssertEqual(ladder.trackedCount, 0)
        XCTAssertEqual(power, ["begin", "end"])

        // A timer already on its way when the acknowledgement came does nothing either.
        clock.runCancelled()
        at(720)
        at(3000)
        XCTAssertEqual(shortcutTimes, [120], "nothing runs at 10:12")
        XCTAssertEqual(shortcutNotifications, [notification(0)])
    }

    func testASleepPastTheStalenessThresholdConvertsTheEscalationAndCancelsThePageOwed() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        at(420)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut)
        XCTAssertNotNil(try kept(ladder, id).owedPage)

        // The app's wake step.
        clock.sleep(for: 400)
        ladder.checkForSleep()
        XCTAssertTrue(try XCTUnwrap(ladder.listedSummaries.first { $0.0 == id }).1.status.isUnseenMiss, "it is missed")
        XCTAssertNil(try kept(ladder, id).owedPage, "and nothing is owed for it, though it is still held and listed")
        XCTAssertEqual(clock.pendingCount, 0)
        XCTAssertEqual(power, ["begin", "end"])
        at(720)
        at(3000)
        XCTAssertEqual(shortcutTimes, [120], "so the page is not sent")
    }

    func testTheRepageTimersOwnSleepCheckConvertsAnEscalationAndSendsNothing() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        // No repeat: the only timer left to notice the sleep is the re-page's.
        let theRule = rule(Escalation(tier2: PanelAlert(delaySeconds: 10), tier4: FinalAlert(afterSeconds: 30, action: .shortcut(name: "Page me"))))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(40)
        XCTAssertEqual(shortcutTimes, [30])
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut, "10 s after the run, within the gap")
        XCTAssertEqual(clock.pendingCount, 1, "the re-page timer is all there is")

        clock.sleep(for: 400)
        at(630)
        XCTAssertEqual(shortcutTimes, [30], "the timer looked for a sleep first, found one and sent nothing")
        XCTAssertTrue(try XCTUnwrap(ladder.listedSummaries.first { $0.0 == id }).1.status.isUnseenMiss)
        XCTAssertNil(try kept(ladder, id).owedPage)
    }

    func testTheTier3CapDoesNotCancelThePageOwedSoAPageOwedWhenItFallsStillGoes() throws {
        // By the time limit.
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        var ladder = coordinator()
        var theRule = rule(Escalation(tier3: repeating(every: 15, maxRepeats: nil, maxDuration: 400), tier4: pageMe))
        var id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        at(300)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut)
        at(400)
        XCTAssertEqual(try XCTUnwrap(ladder.listedSummaries.first { $0.0 == id }).1.status, .capped(at: start + 390),
                       "the last repeat the limit allows fell at 390")
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(1), "and the page is still owed")
        XCTAssertEqual(clock.pendingCount, 1, "with its timer armed")
        XCTAssertTrue(ladder.hasPendingTiers)
        at(719)
        XCTAssertEqual(shortcutTimes, [120])
        at(720)
        XCTAssertEqual(shortcutTimes, [120, 720], "it goes")
        XCTAssertEqual(shortcutNotifications.last, notification(1))

        // By the limit on repeats.
        freshWorld()
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        ladder = coordinator()
        theRule = rule(Escalation(tier3: repeating(every: 15, maxRepeats: 20), tier4: pageMe))
        id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        at(200)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut)
        at(400)
        XCTAssertEqual(try XCTUnwrap(ladder.listedSummaries.first { $0.0 == id }).1.status, .capped(at: start + 300),
                       "the twentieth repeat fell at 300")
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(1))
        at(720)
        XCTAssertEqual(shortcutTimes, [120, 720])
        XCTAssertEqual(shortcutNotifications.last, notification(1))
    }

    func testAMatchAfterTheOwedPageRanIsOwedTheNextNoSoonerThanTenMinutesAfterIt() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        at(420)
        match(ladder, theRule, 1)
        at(720)
        XCTAssertEqual(shortcutTimes, [120, 720], "the owed page ran")

        at(800)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 2).join).ranShortcut, "80 s after the page")
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(2))
        at(1319)
        XCTAssertEqual(shortcutTimes, [120, 720], "not before 600 s after the page")
        at(1320)
        XCTAssertEqual(shortcutTimes, [120, 720, 1320], "and then")
        XCTAssertEqual(shortcutNotifications, [notification(0), notification(1), notification(2)])
        XCTAssertNil(try kept(ladder, id).owedPage)
    }

    func testAMatchThatJoinsWhileARunIsPendingIsOwedAPageAndItsTimerLooksAgainEveryFiveSecondsUntilTheRunHasReported() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        XCTAssertEqual(shortcutRuns.count, 1, "the first run has not reported")
        at(420)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut, "a run is pending")
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(1), "so the match is owed a page instead")

        at(720)
        XCTAssertEqual(shortcutRuns.count, 1, "the timer found the run still pending, and started nothing beside it")
        at(724)
        XCTAssertEqual(shortcutRuns.count, 1)
        at(725)
        XCTAssertEqual(shortcutRuns.count, 1, "five seconds on it looked again, and the run was still pending")
        at(729)
        XCTAssertEqual(shortcutRuns.count, 1)

        report(run: 0, .shortcutLaunched(name: "Page me"))
        XCTAssertEqual(shortcutRuns.count, 1, "a run that went is not a reason to send the page sooner than its timer")
        at(730)
        XCTAssertEqual(shortcutRuns.count, 2, "the next look, five seconds after the last, found it reported and sent the page")
        XCTAssertEqual(shortcutNotifications.last, notification(1))
        XCTAssertEqual(shortcutTimes, [120, 730])
        XCTAssertNil(try kept(ladder, id).owedPage)
        at(2000)
        XCTAssertEqual(shortcutRuns.count, 2)
    }

    func testAPageOwedWhileARunHasBeenPendingForTenMinutesIsLookedForAtOnceAndNotInThePast() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        match(ladder, theRule, 0)
        at(120)
        at(800)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut, "680 s on, and still pending")
        // The 10 minutes have long passed, so the timer is armed for no time at all and not for a time before now.
        report(run: 0, .shortcutLaunched(name: "Page me"))
        at(800)
        XCTAssertEqual(shortcutTimes, [120, 800], "at once, now, and never at a time that has gone")
        XCTAssertEqual(clock.awakeTime(), 800)
        XCTAssertEqual(shortcutNotifications.last, notification(1))
    }

    func testARunThatReportsAFailureWhileAPageIsOwedRunsTheOwedPageAtOnceAndOnce() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        at(420)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut)
        at(450)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 2).join).ranShortcut)
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(2))
        let timers = clock.pendingCount

        report(run: 0, .shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed"))
        XCTAssertEqual(shortcutRuns.count, 2, "the owed page runs at once")
        XCTAssertEqual(shortcutNotifications.last, notification(2), "with the newest owed match's fields")
        XCTAssertEqual(shortcutTimes, [120, 450], "not at 10:12")
        XCTAssertNil(try kept(ladder, id).owedPage)
        XCTAssertEqual(clock.pendingCount, timers - 1, "and its timer is cancelled")
        XCTAssertEqual(try kept(ladder, id).lastShortcutRunAt, EscalationCoordinator.Stamp(wall: start + 450, awake: 450),
                       "recorded as any run is")

        // Once: a second failure has nothing left owed to it.
        report(run: 1, .shortcutFailed(name: "Page me", reason: "x"))
        XCTAssertEqual(shortcutRuns.count, 2)
        // And the timer that was cancelled does not come back, even if it was already on its way.
        clock.runCancelled()
        at(1000)
        XCTAssertEqual(shortcutRuns.count, 2)
        XCTAssertEqual(latest(try XCTUnwrap(begun.first).entry)?.finalCount, 2, "each report was counted once")
        XCTAssertEqual(ladder.trackedCount, 1)
    }

    func testAShortcutThatAlwaysFailsUnderAStormOf20MatchesHasOneRunInFlightAtATime() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        var reports = 0
        func inFlight() -> Int { shortcutRuns.count - reports }
        func fail() {
            report(run: reports, .shortcutFailed(name: "Page me", reason: "x"))
            reports += 1
        }
        var mostInFlight = inFlight()
        for index in 1...20 {
            at(120 + Double(index) * 5)
            match(ladder, theRule, index)
            mostInFlight = max(mostInFlight, inFlight())
            // Every fourth match arrives as the run in flight fails.
            if index % 4 == 0 {
                fail()
                mostInFlight = max(mostInFlight, inFlight())
            }
        }
        XCTAssertEqual(mostInFlight, 1, "never more than one run in flight")
        XCTAssertEqual(shortcutRuns.count, 6, "tier 4's, and one page for each of the five failures that found a page owed")
        XCTAssertEqual(shortcutNotifications.map { $0.title },
                       ["Incident 0", "Incident 4", "Incident 8", "Incident 12", "Incident 16", "Incident 20"],
                       "each with the fields of the newest match owed")
        XCTAssertEqual(inFlight(), 1)
        fail()
        XCTAssertEqual(shortcutRuns.count, 6, "and when nothing is owed a failure starts nothing")
        XCTAssertEqual(latest(try XCTUnwrap(begun.first).entry)?.finalCount, 6, "every failure was counted once")
        XCTAssertNil(try kept(ladder, id).owedPage)
    }

    func testTheFirstJoinAtOrAfterTenMinutesRunsTheShortcutAndCancelsAnyPageOwedAndAnotherAtOnceDoesNotRun() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        at(400)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut)
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(1))
        let timers = clock.pendingCount

        // The Mac slept, too little to convert anything, so the wall clock reads the run 630 s old while its timer,
        // which counts awake time, is 220 s away.
        clock.sleep(for: 250)
        at(500)
        let join = try XCTUnwrap(match(ladder, theRule, 2).join)
        XCTAssertTrue(join.ranShortcut, "the first join at or after 10 minutes runs it")
        XCTAssertEqual(shortcutNotifications.last, notification(2), "with its own fields")
        XCTAssertNil(try kept(ladder, id).owedPage, "and the older match's page is no longer owed")
        XCTAssertEqual(clock.pendingCount, timers - 1, "its timer is cancelled")

        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 3).join).ranShortcut, "another at once does not run")
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(3), "it is owed a page, 10 minutes after this run")
        at(1099)
        XCTAssertEqual(shortcutTimes, [120, 500])
        at(1100)
        XCTAssertEqual(shortcutTimes, [120, 500, 1100], "and only the later match's page goes, and only then")
        XCTAssertEqual(shortcutNotifications, [notification(0), notification(2), notification(3)])
    }

    func testASleepThatConvertsNothingMakesTheRunOlderSoTheOwedPageIsDueSooner() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        match(ladder, theRule, 0)
        at(120)
        at(300)
        clock.sleep(for: 250)
        at(310)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut, "440 s by the wall clock and 190 awake")
        at(469)
        XCTAssertEqual(shortcutTimes, [120])
        at(470)
        XCTAssertEqual(shortcutTimes, [120, 470], "the run is 440 s old by the wall clock, so the page is 160 s away and not 410")
    }

    func testAWallClockSetBackAnHourDoesNotDelayAPageOwedByAnHour() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        clock.stepBack(by: 3600)
        at(420)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut)
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(1))
        at(719)
        XCTAssertEqual(shortcutTimes, [120])
        at(720)
        XCTAssertEqual(shortcutTimes, [120, 720],
                       "the run's time on the wall clock is an hour ahead of it, and the awake clock's 300 s are what count")
    }

    func testALadderWhoseTier4IsAnAlertOwesNothingWhenAMatchJoinsAfterItHasSounded() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: FinalAlert(afterSeconds: 60, action: .alert(glass))))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        XCTAssertEqual(ownAlerts, 1, "tier 4's alert sounded once")
        let timers = clock.pendingCount
        let join = try XCTUnwrap(match(ladder, theRule, 1).join)
        XCTAssertFalse(join.ranShortcut)
        XCTAssertNil(try kept(ladder, id).owedPage, "no page is owed for an alert")
        XCTAssertEqual(clock.pendingCount, timers, "and no timer is armed")
        at(2000)
        XCTAssertEqual(shortcutNotifications, [])
        XCTAssertEqual(ownAlerts, 1)
    }

    func testTheOwedNotificationIsForgottenWhenItIsSentWhenAcknowledgedAndWhenRetired() throws {
        // Sent: nothing is left of it, and the timers and the assertion return to what they were.
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        var ladder = coordinator()
        let gentle = rule(Escalation(tier2: PanelAlert(delaySeconds: 10), tier4: FinalAlert(afterSeconds: 30, action: .shortcut(name: "Page me"))))
        var id = try XCTUnwrap(match(ladder, gentle, 0).beganID)
        at(40)
        XCTAssertEqual(clock.pendingCount, 0, "nothing is armed once tier 4 has run")
        XCTAssertFalse(try XCTUnwrap(match(ladder, gentle, 1).join).ranShortcut)
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(1))
        XCTAssertEqual(clock.pendingCount, 1)
        at(630)
        XCTAssertEqual(shortcutNotifications.last, notification(1))
        XCTAssertNil(try kept(ladder, id).owedPage, "sent, and forgotten")
        XCTAssertEqual(clock.pendingCount, 0)
        XCTAssertFalse(ladder.hasPendingTiers)
        XCTAssertEqual(ladder.trackedCount, 1)

        // Acknowledged while a run is pending: the escalation is still held for that run, and the notification is not.
        freshWorld()
        ladder = coordinator()
        id = try XCTUnwrap(match(ladder, gentle, 0).beganID)
        at(40)
        XCTAssertEqual(shortcutRuns.count, 1)
        XCTAssertFalse(try XCTUnwrap(match(ladder, gentle, 1).join).ranShortcut, "the run is pending")
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(1))
        ladder.acknowledge(id)
        XCTAssertEqual(ladder.trackedCount, 1, "held until the run reports")
        XCTAssertNil(try kept(ladder, id).owedPage, "acknowledged, and forgotten")
        XCTAssertEqual(clock.pendingCount, 0)

        // Retired: the report comes, and the escalation goes with all it held.
        let entry = try XCTUnwrap(begun.first).entry
        report(run: 0, .shortcutLaunched(name: "Page me"))
        XCTAssertNil(ladder.bookkeeping(of: id))
        XCTAssertEqual(ladder.trackedCount, 0, "retired")
        XCTAssertEqual(retirements, [entry])
        XCTAssertEqual(clock.pendingCount, 0)
        at(3000)
        XCTAssertEqual(shortcutRuns.count, 1)
    }

    func testTheRepageTimerHoldsThePowerAssertionUntilItHasFired() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let gentle = rule(Escalation(tier2: PanelAlert(delaySeconds: 10), tier4: FinalAlert(afterSeconds: 30, action: .shortcut(name: "Page me"))))
        match(ladder, gentle, 0)
        XCTAssertEqual(power, ["begin"])
        at(40)
        XCTAssertEqual(power, ["begin", "end"], "tier 4 has run and nothing else is left to fire")
        XCTAssertFalse(ladder.hasPendingTiers)
        XCTAssertFalse(try XCTUnwrap(match(ladder, gentle, 1).join).ranShortcut)
        XCTAssertTrue(ladder.hasPendingTiers, "a page owed is a tier still to fire")
        XCTAssertEqual(power, ["begin", "end", "begin"], "so the Mac is held awake for it")
        at(629)
        XCTAssertEqual(power, ["begin", "end", "begin"])
        at(630)
        XCTAssertEqual(power, ["begin", "end", "begin", "end"], "and let go once it has fired")
        XCTAssertFalse(ladder.hasPendingTiers)
    }

    func testARepageTimerThatIsDeliveredAgainOrIsNoLongerTheOneWaitedForSendsNothing() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 40),
                                      tier4: FinalAlert(afterSeconds: 30, action: .shortcut(name: "Page me"))))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(40)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut, "10 s after the run")
        at(630)
        XCTAssertEqual(shortcutTimes, [30, 630])
        XCTAssertEqual(clock.refireLast(), 1)
        XCTAssertEqual(shortcutTimes, [30, 630], "the same timer delivered a second time finds nothing owed and nothing to wait for")

        // A newer page is owed, with a new timer: the old one, delivered late, is not the one waited for.
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 2).join).ranShortcut)
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(2))
        XCTAssertEqual(clock.refireLast(), 1)
        XCTAssertEqual(shortcutTimes, [30, 630], "it does not send the page early")
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(2), "which is still owed")
        at(1229)
        XCTAssertEqual(shortcutTimes, [30, 630])
        at(1230)
        XCTAssertEqual(shortcutTimes, [30, 630, 1230], "and goes when its own timer says")
        XCTAssertEqual(shortcutNotifications.last, notification(2))
    }

    func testAnAcknowledgementFromInsideTheRecordOfAJoinThatOwesAPageLeavesNothingOwedAndNoTimer() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        at(420)
        onRecord = { _, summary in
            if summary.matchCount == 2, summary.status == .live { ladder.acknowledge(id) }
        }
        let join = try XCTUnwrap(match(ladder, theRule, 1).join)
        XCTAssertEqual(join.matchNumber, 2)
        XCTAssertFalse(join.ranShortcut)
        XCTAssertEqual(ladder.listedSummaries.count, 0, "acknowledged from inside the record, and it stays so")
        XCTAssertNil(ladder.bookkeeping(of: id), "with nothing left owed or held")
        XCTAssertEqual(clock.pendingCount, 0, "and the timer that would have sent the page is not armed")
        XCTAssertEqual(power, ["begin", "end"])
        at(3000)
        XCTAssertEqual(shortcutTimes, [120])
    }

    func testAnOwedPageThatFailsIsTriedAgainByTheNextMatchAtOnceAndLeavesNothingOwed() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        report(run: 0, .shortcutLaunched(name: "Page me"))
        at(420)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut)
        at(720)
        XCTAssertEqual(shortcutRuns.count, 2, "the owed page was sent")
        XCTAssertEqual(shortcutNotifications.last, notification(1))
        report(run: 1, .shortcutFailed(name: "Page me", reason: "x"))
        XCTAssertEqual(shortcutRuns.count, 2, "its failure has nothing owed to run")
        at(730)
        let join = try XCTUnwrap(match(ladder, theRule, 2).join)
        XCTAssertTrue(join.ranShortcut, "the page that was sent failed: the next match tries it again at once")
        XCTAssertEqual(shortcutNotifications.last, notification(2))
        XCTAssertNil(try kept(ladder, id).owedPage)
    }

    func testAFailureReportedAfterASleepBeforeTheWakeStepFindsTheEscalationConvertedAndRunsNoOwedPage() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        XCTAssertEqual(shortcutRuns.count, 1, "10:02: tier 4's run is out and has not reported")
        at(130)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut)
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(1), "owed a page behind the pending run")

        // The Mac sleeps 400 seconds, and the run reports its failure on waking,
        // before the app's wake step has looked for the sleep.
        clock.sleep(for: 400)
        report(run: 0, .shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed"))
        XCTAssertEqual(shortcutRuns.count, 1, "the page owed before the sleep is not run after it")
        XCTAssertTrue(try XCTUnwrap(ladder.listedSummaries.first { $0.0 == id }).1.status.isUnseenMiss,
                      "the report found the escalation converted")
        XCTAssertNil(try kept(ladder, id).owedPage)
        XCTAssertEqual(clock.pendingCount, 0, "and no timer is left, the re-page's included")
        let summary = try XCTUnwrap(latest(try XCTUnwrap(begun.first).entry))
        XCTAssertEqual(summary.final, .shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed"),
                       "the failure is still recorded")
        XCTAssertEqual(summary.finalCount, 1)

        // The wake step after it, and the time the page was due, change nothing.
        ladder.checkForSleep()
        at(1000)
        XCTAssertEqual(shortcutRuns.count, 1)
        XCTAssertEqual(power, ["begin", "end"])
    }

    // MARK: - The quiet gap, whatever the wall clock does

    func testAQuietGapIsReadOnBothClocksSoASleepEndsItAndASetBackWallClockDoesNotStretchIt() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier2: PanelAlert(delaySeconds: 10)))
        match(ladder, theRule, 0)
        at(10)
        clock.sleep(for: 100)
        guard case .began = match(ladder, theRule, 1) else {
            return XCTFail("10 s awake, 110 s by the wall clock: the Mac slept, so it is not within the gap")
        }
        XCTAssertEqual(begun.count, 2)

        let other = rule("Another", Escalation(tier2: PanelAlert(delaySeconds: 10)))
        match(ladder, other, 2)
        clock.stepBack(by: 3600)
        at(clock.awakeTime() + 30)
        XCTAssertNotNil(match(ladder, other, 3).join, "30 s awake: a wall clock an hour back does not make a match too late")
        // Set back again, after the last match: its time on the wall clock is now an hour in the future.
        clock.stepBack(by: 3600)
        at(clock.awakeTime() + 61)
        guard case .began = match(ladder, other, 4) else {
            return XCTFail("61 s awake is past the gap whatever the wall clock reads: it must not hold a match to a gap it has left")
        }
    }

    // MARK: - Coordinator, as before

    func testASecondMatchJoinsWithNoNewTimerACountOfTwoTheRowRecordedAndThePanelRepublished() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier2: PanelAlert(delaySeconds: 10), tier3: repeating(every: 30)))
        match(ladder, theRule, 0)
        let entry = try XCTUnwrap(begun.first).entry
        at(15)
        XCTAssertEqual(panels.last?.map(\.1.matchCount), [1], "tier 2 has shown")
        let timers = clock.pendingCount
        let recordsBefore = records.count
        let panelsBefore = panels.count

        let join = try XCTUnwrap(match(ladder, theRule, 1).join)
        XCTAssertEqual(join, EscalationJoin(matchNumber: 2, alert: nil, ranShortcut: false))
        XCTAssertEqual(clock.pendingCount, timers, "no new timer")
        XCTAssertEqual(records.count, recordsBefore + 1, "the row is recorded")
        XCTAssertEqual(records.last?.0, entry)
        XCTAssertEqual(records.last?.1.matchCount, 2)
        XCTAssertEqual(panels.count, panelsBefore + 1, "and the panel republished")
        XCTAssertEqual(panels.last?.map(\.1.matchCount), [2])
        XCTAssertEqual(ladder.listedSummaries.map(\.1.matchCount), [2])
    }

    func testTier3RepeatsOncePerIntervalAndNotOncePerMatch() {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 30)))
        match(ladder, theRule, 0)
        for index in 1...20 {
            at(Double(index))
            match(ladder, theRule, index)
        }
        at(29)
        XCTAssertEqual(repeats, 0)
        at(30)
        XCTAssertEqual(repeats, 1, "twenty matches in the interval, and one repeat")
        at(60)
        XCTAssertEqual(repeats, 2)
    }

    func testAMatchAfterAcknowledgeOrAcknowledgeAllNeverJoins() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier2: PanelAlert(delaySeconds: 10)))
        let one = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(5)
        XCTAssertNotNil(match(ladder, theRule, 1).join)
        ladder.acknowledge(one)
        at(6)
        guard case .began(let second) = match(ladder, theRule, 2) else { return XCTFail("after Acknowledge it begins a new ladder") }
        XCTAssertNotEqual(second, one)
        XCTAssertEqual(firstAlerts, 2, "and sounds")
        ladder.acknowledgeAll()
        at(7)
        guard case .began = match(ladder, theRule, 3) else { return XCTFail("after Acknowledge All too") }
        XCTAssertEqual(firstAlerts, 3)
        XCTAssertEqual(latest(begun[0].entry)?.matchCount, 2, "and the acknowledged escalation's count stood where it was")
    }

    func testAMatchNeverJoinsACappedEscalationWhichStaysListedAndKeepsItsTier4() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 30, maxRepeats: 2),
                                      tier4: FinalAlert(afterSeconds: 300, action: .shortcut(name: "Page me"))))
        match(ladder, theRule, 0)
        at(100)
        XCTAssertEqual(records.last?.1.status, .capped(at: start + 60))
        guard case .began = match(ladder, theRule, 1) else { return XCTFail("a capped escalation is never joined") }
        XCTAssertEqual(ladder.listedSummaries.count, 2, "the capped one is still listed")
        at(300)
        XCTAssertEqual(shortcutTimes, [300], "and its tier 4 fires")
        XCTAssertEqual(latest(begun[0].entry)?.matchCount, 1)
    }

    func testAnAcknowledgedEscalationStillHeldForItsShortcutIsNeverJoined() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier2: PanelAlert(delaySeconds: 10),
                                      tier4: FinalAlert(afterSeconds: 30, action: .shortcut(name: "Page me"))))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(30)
        XCTAssertEqual(shortcutRuns.count, 1, "its run has not reported")
        ladder.acknowledge(id)
        XCTAssertNotNil(ladder.bookkeeping(of: id), "so it is held, though acknowledged")
        at(40)
        guard case .began = match(ladder, theRule, 1) else {
            return XCTFail("an acknowledged escalation is not joined, held or not, and 40 s is within the gap")
        }
        XCTAssertEqual(latest(begun[0].entry)?.matchCount, 1)
        XCTAssertEqual(begun.count, 2)
    }

    func testAMissedEscalationIsNeverJoinedEvenWithinAQuietGapThatOutlastsTheSleep() throws {
        let ladder = coordinator(policy: BurstPolicy(quietGap: 1000, silentJoinWindow: 60, repageTime: 600))
        let theRule = rule(Escalation(tier2: PanelAlert(delaySeconds: 10)))
        match(ladder, theRule, 0)
        at(5)
        clock.sleep(for: 400)
        guard case .began = match(ladder, theRule, 1) else {
            return XCTFail("converted as missed while asleep, so not live, whatever the gap")
        }
        XCTAssertEqual(latest(begun[0].entry)?.matchCount, 1)
        XCTAssertTrue(try XCTUnwrap(ladder.listedSummaries.first { $0.0 == begun[0].id }).1.status.isUnseenMiss)
    }

    func testAfterASleepAJoinConvertsFirstAndThenTheMatchBeginsANewOne() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 30)))
        match(ladder, theRule, 0)
        at(10)
        clock.sleep(for: 400)
        guard case .began = match(ladder, theRule, 1) else { return XCTFail("the first is no longer live") }
        let missed = try XCTUnwrap(records.firstIndex { $0.0 == begun[0].entry && $0.1.status.isUnseenMiss })
        let fresh = try XCTUnwrap(records.firstIndex { $0.0 == begun[1].entry })
        XCTAssertLessThan(missed, fresh, "converted first, and then the new one recorded")
        XCTAssertEqual(latest(begun[0].entry)?.matchCount, 1, "the match was not counted into it")
        XCTAssertEqual(firstAlerts, 2)
        XCTAssertEqual(ladder.listedSummaries.count, 2, "the missed one is listed until seen, beside the new one")
    }

    func testTwoRulesBurstIndependently() throws {
        let ladder = coordinator()
        let mentions = rule("On-call mentions", Escalation(tier3: repeating(every: 30)))
        let pages = rule("Pager", Escalation(tier2: PanelAlert(delaySeconds: 10)))
        match(ladder, mentions, 0)
        match(ladder, pages, 1)
        at(5)
        XCTAssertEqual(try XCTUnwrap(match(ladder, mentions, 2).join).matchNumber, 2)
        XCTAssertEqual(try XCTUnwrap(match(ladder, pages, 3).join).matchNumber, 2)
        XCTAssertEqual(try XCTUnwrap(match(ladder, mentions, 4).join).matchNumber, 3)
        XCTAssertEqual(latest(begun[0].entry)?.matchCount, 3)
        XCTAssertEqual(latest(begun[1].entry)?.matchCount, 2, "each rule's count is its own")
        XCTAssertEqual(begun.count, 2)
        XCTAssertEqual(firstAlerts, 2)
    }

    func testTwoRulesWithTheSameNameAndDifferentIdsNeverJoin() throws {
        let ladder = coordinator()
        let a = rule("On-call mentions", Escalation(tier3: repeating(every: 30)))
        let b = rule("On-call mentions", Escalation(tier3: repeating(every: 30)))
        XCTAssertNotEqual(a.id, b.id)
        match(ladder, a, 0)
        match(ladder, b, 1)
        XCTAssertEqual(begun.count, 2, "the same name and the same ladder, and two escalations")
        at(5)
        XCTAssertEqual(try XCTUnwrap(match(ladder, a, 2).join).matchNumber, 2)
        XCTAssertEqual(try XCTUnwrap(match(ladder, b, 3).join).matchNumber, 2)
        XCTAssertEqual(latest(begun[0].entry)?.matchCount, 2)
        XCTAssertEqual(latest(begun[1].entry)?.matchCount, 2)
        at(30)
        XCTAssertEqual(repeats, 2, "each escalation repeats once")
        XCTAssertEqual(begun.count, 2)
    }

    func testARuleWithNoLadderJoinsNothingAndAskingChangesNothing() throws {
        let ladder = coordinator()
        let running = rule(Escalation(tier3: repeating(every: 30)))
        match(ladder, running, 0)
        var withoutLadder = running
        withoutLadder.escalation = nil
        let recordsBefore = records.count
        XCTAssertNil(ladder.join(rule: withoutLadder, notification: notification(1)),
                     "the rule has no ladder now, whatever it had: nothing for a match to join")
        XCTAssertNil(ladder.join(rule: rule("Plain", nil), notification: notification(2)))
        XCTAssertEqual(ladder.trackedCount, 1)
        XCTAssertEqual(records.count, recordsBefore)
        XCTAssertEqual(latest(begun[0].entry)?.matchCount, 1)
        XCTAssertEqual(sounds, [], "and it played nothing")
    }

    func testAJoinLeavesTheTrackedCountTheDueTimesAndThePowerAssertionAsTheyWereAndArmsNoTimerUnlessAPageIsOwed() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier2: PanelAlert(delaySeconds: 10), tier3: repeating(every: 300), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(20)
        struct Snapshot: Equatable {
            let tracked: Int
            let timers: Int
            let repeatDue: TimeInterval?
            let power: [String]
            let hasPendingTiers: Bool
        }
        func snapshot() throws -> Snapshot {
            Snapshot(tracked: ladder.trackedCount, timers: clock.pendingCount, repeatDue: try kept(ladder, id).repeatDue,
                     power: power, hasPendingTiers: ladder.hasPendingTiers)
        }
        let before = try snapshot()
        XCTAssertEqual(before, Snapshot(tracked: 1, timers: 2, repeatDue: 300, power: ["begin"], hasPendingTiers: true),
                       "the repeat and tier 4 are armed, and the panel has shown")
        XCTAssertNotNil(match(ladder, theRule, 1).join?.alert, "audible: the repeat is far")
        XCTAssertEqual(try snapshot(), before, "tier 4 has not run, so nothing is owed and nothing is armed")
        at(250)
        let atTier4 = try snapshot()
        XCTAssertEqual(atTier4, Snapshot(tracked: 1, timers: 1, repeatDue: 300, power: ["begin"], hasPendingTiers: true),
                       "tier 4 has fired since, and that is all that changed")
        XCTAssertNil(match(ladder, theRule, 3).join?.alert, "silent: due in 50")
        XCTAssertEqual(try snapshot(), Snapshot(tracked: 1, timers: 2, repeatDue: 300, power: ["begin"], hasPendingTiers: true),
                       "tier 4 ran 130 s ago, so the match is owed a page: the one re-page timer is armed, and nothing else moved")
    }

    func testAJoinThatRunsTheShortcutArmsNoTimerAndHoldsNoMoreOfTheAssertionThanBefore() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        match(ladder, theRule, 0)
        at(720)
        let timers = clock.pendingCount
        let powerBefore = power
        XCTAssertTrue(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut)
        XCTAssertEqual(clock.pendingCount, timers)
        XCTAssertEqual(power, powerBefore)
        XCTAssertEqual(ladder.trackedCount, 1)
    }

    func testAMatchThatArrivesInsideARepeatsOwnSoundDoesNotJoinItAndLaterOnesJoinTheNewest() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 30)))
        match(ladder, theRule, 0)
        var inside: Arrival?
        onSound = { [self] in
            onSound = nil
            inside = match(ladder, theRule, 1)
        }
        at(30)
        XCTAssertEqual(repeats, 1)
        guard case .began = inside else {
            return XCTFail("at that moment the repeat is not armed, and a tier 3 whose repeat is not armed is never joined")
        }
        XCTAssertEqual(latest(begun[0].entry)?.matchCount, 1, "so the match began its own, as it would have")
        XCTAssertEqual(begun.count, 2)
        XCTAssertEqual(clock.pendingCount, 2, "and the first repeat armed the next once its sound was done")

        // Now two live escalations of one rule hold an equal ladder with a repeat armed: the newest is joined.
        at(35)
        XCTAssertEqual(try XCTUnwrap(match(ladder, theRule, 2).join).matchNumber, 2)
        XCTAssertEqual(latest(begun[0].entry)?.matchCount, 1)
        XCTAssertEqual(latest(begun[1].entry)?.matchCount, 2, "it joined the newer one")
    }

    func testAJoinForARuleWhoseFirstAlertIsSilentOrAbsentSaysSoAndIsNotTheSilenceOfARepeat() throws {
        let ladder = coordinator()
        let quiet = rule("Quiet", Escalation(tier3: repeating(every: 300)), alert: .silent)
        let none = rule("None", Escalation(tier3: repeating(every: 300)), alert: nil)
        match(ladder, quiet, 0, tier1: .silentByRule)
        match(ladder, none, 1, tier1: .noAlertSet)
        at(10)
        XCTAssertEqual(try XCTUnwrap(match(ladder, quiet, 2).join).alert, .silentByRule,
                       "an alert the rule chose to make silent is an outcome, and nil is kept for a match a repeat covers")
        XCTAssertEqual(try XCTUnwrap(match(ladder, none, 3).join).alert, .noAlertSet)
        XCTAssertEqual(sounds, [], "and nothing was played for either")
    }

    func testTheQuietGapAndTheRepageTimeAreTheOnesThePolicyGivesAndNotAFixedSixtyAndSixHundred() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator(policy: BurstPolicy(quietGap: 5, silentJoinWindow: 60, repageTime: 100))
        let gentle = rule("Gentle", Escalation(tier2: PanelAlert(delaySeconds: 1)))
        match(ladder, gentle, 0)
        at(5)
        XCTAssertNotNil(match(ladder, gentle, 1).join, "5 s after the last, and the gap is 5")
        at(11)
        guard case .began = match(ladder, gentle, 2) else { return XCTFail("6 s after the last, and the gap is 5") }

        // Two escalations of one ladder: the first is joined 99 s after its run and owed a page, which goes at 100 s
        // and not at 600; the second is joined at 100 s, with nothing owed, and runs the Shortcut.
        let paged = rule("Paged", Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let other = rule("Other", Escalation(tier3: repeating(every: 15), tier4: pageMe))
        match(ladder, paged, 3)
        let begunAt = clock.awakeTime()
        match(ladder, other, 4)
        at(begunAt + 120)
        XCTAssertEqual(shortcutTimes.count, 2, "both ran at tier 4")
        at(begunAt + 219)
        XCTAssertFalse(try XCTUnwrap(match(ladder, paged, 5).join).ranShortcut, "99 s after the run, and the time is 100")
        at(begunAt + 220)
        XCTAssertEqual(shortcutTimes.count, 3, "the page owed to that match went at 100 s and not at 600")
        XCTAssertEqual(shortcutNotifications.last, notification(5))
        XCTAssertTrue(try XCTUnwrap(match(ladder, other, 6).join).ranShortcut, "100 s: the other has nothing owed, and runs it")
        XCTAssertEqual(shortcutNotifications.last, notification(6))
    }

    func testAnEscalationEndedFromInsideTheJoinsAlertIsNotPagedForEvenWhenItIsStillHeld() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 300), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(720)
        XCTAssertEqual(shortcutTimes, [120])
        // The Mac slept while the alert played, long enough to convert it: it is missed, not live, and still held and listed.
        onSound = { [self] in
            onSound = nil
            clock.sleep(for: 400)
            ladder.checkForSleep()
        }
        let join = try XCTUnwrap(match(ladder, theRule, 1).join)
        XCTAssertEqual(join.matchNumber, 2)
        XCTAssertFalse(join.ranShortcut, "an escalation that has ended is not paged for, though the 10 minutes had passed")
        XCTAssertEqual(shortcutTimes, [120])
        XCTAssertTrue(try XCTUnwrap(ladder.listedSummaries.first { $0.0 == id }).1.status.isUnseenMiss)
    }

    // MARK: - What a held menu's Acknowledge ends

    /// The status menu is held open while capture runs (M5 plan, Ruling 22), so a
    /// match can join an escalation it listed in those seconds. Its Acknowledge
    /// item acts on what it listed as it listed it, and an escalation whose count
    /// of matches has grown since is left escalating, so that a click never ends
    /// what the user was not shown: a silent join has sounded nothing of its
    /// own, and the match may be owed a page, which acknowledging would cancel.
    /// This goes beyond the plan, which holds the item to the ids it listed.

    /// What the item carries when the menu is built.
    private func menuListing(_ ladder: EscalationCoordinator) -> [ListedEscalation] {
        ladder.listedSummaries.map(ListedEscalation.init(row:))
    }

    func testAMatchThatJoinedWhileTheMenuWasOpenSurvivesAcknowledgeFromThatMenuAndItsOwedPageStillGoes() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(130)
        XCTAssertEqual(shortcutTimes, [120], "tier 4 has run")
        let menu = menuListing(ladder)
        XCTAssertEqual(menu, [ListedEscalation(id: id, matchCount: 1)], "the menu is built, and held open")

        at(200)
        let join = try XCTUnwrap(match(ladder, theRule, 1).join)
        XCTAssertEqual(join.matchNumber, 2, "a match joins while it is open")
        XCTAssertNil(join.alert, "silently: a repeat is about to sound, so nothing of its own was heard")
        XCTAssertFalse(join.ranShortcut)
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(1), "and it is owed a page")

        ladder.acknowledge(listed: menu)
        XCTAssertEqual(ladder.listedSummaries.map(\.0), [id], "the click leaves it listed")
        XCTAssertEqual(ladder.listedSummaries.first?.1.status, .live, "and escalating")
        XCTAssertEqual(ladder.listedSummaries.first?.1.matchCount, 2)
        XCTAssertEqual(playerStopped, 0, "nothing is stopped")
        XCTAssertEqual(power, ["begin"], "and the Mac is still held for its tiers")
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(1), "the page it owes is still owed")

        let before = repeats
        at(215)
        XCTAssertEqual(repeats, before + 1, "its repeat still sounds")
        at(719)
        XCTAssertEqual(shortcutTimes, [120])
        at(720)
        XCTAssertEqual(shortcutTimes, [120, 720], "and the page it owed goes, when the 10 minutes are up")
        XCTAssertEqual(shortcutNotifications, [notification(0), notification(1)], "with the joined match's fields")
    }

    func testAnEscalationWhoseCountDidNotGrowIsAcknowledgedAsBeforeBesideOneWhoseCountDid() throws {
        let ladder = coordinator()
        let a = rule("A", Escalation(tier2: PanelAlert(delaySeconds: 1), tier3: repeating(every: 30)))
        let b = rule("B", Escalation(tier2: PanelAlert(delaySeconds: 1)))
        let idA = try XCTUnwrap(match(ladder, a, 0).beganID)
        let idB = try XCTUnwrap(match(ladder, b, 1).beganID)
        at(2)
        let menu = menuListing(ladder)
        XCTAssertEqual(menu.map(\.id), [idB, idA], "both are listed, newest first")
        XCTAssertEqual(menu.map(\.matchCount), [1, 1])

        at(5)
        XCTAssertNotNil(match(ladder, a, 2).join, "a match joins A while the menu is open")
        ladder.acknowledge(listed: menu)

        XCTAssertEqual(ladder.listedSummaries.map(\.0), [idA], "B is acknowledged as before, and A is left")
        XCTAssertEqual(latest(begun[1].entry)?.status, .acknowledged(at: start + 5))
        XCTAssertEqual(latest(begun[0].entry)?.status, .live)
        XCTAssertEqual(playerStopped, 0, "A is still escalating, so nothing is stopped")
        XCTAssertEqual(panels.last?.map(\.0), [idA], "the panel is told B has gone, and A stays")
        let before = repeats
        at(35)
        XCTAssertEqual(repeats, before + 1, "A still repeats")
    }

    func testTheNextMenuListsItWithItsNewCountAndAcknowledgingFromThatOneEndsItAndCancelsThePageItOwed() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(130)
        let held = menuListing(ladder)
        at(200)
        XCTAssertNotNil(match(ladder, theRule, 1).join)
        ladder.acknowledge(listed: held)

        let next = menuListing(ladder)
        XCTAssertEqual(next, [ListedEscalation(id: id, matchCount: 2)], "the next menu carries the count it stands for now")
        XCTAssertEqual(AlertMenuText.escalationLines(listed: ladder.listedSummaries.map(\.1), shortcutFailure: nil,
                                                     time: { _ in "10:00" }),
                       ["\(AlertMenuText.singleEscalatingStem) (2 matches)"], "and says it: the user is shown the match")

        ladder.acknowledge(listed: next)
        XCTAssertEqual(ladder.listedSummaries.count, 0, "so a click on that one ends it")
        XCTAssertEqual(playerStopped, 1, "and stops what plays, as it does when nothing is left live")
        XCTAssertEqual(clock.pendingCount, 0, "with the page it owed, as acknowledging cancels")
        at(720)
        at(3000)
        XCTAssertEqual(shortcutTimes, [120], "and nothing is sent")
    }

    func testAMissedEscalationWhoseCountGrewBeforeItWasConvertedIsLeftUnseenByTheOldMenu() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier2: PanelAlert(delaySeconds: 1), tier3: repeating(every: 30)))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(20)
        let menu = menuListing(ladder)
        XCTAssertNotNil(match(ladder, theRule, 1).join)
        clock.sleep(for: 400)
        ladder.checkForSleep()
        XCTAssertTrue(try XCTUnwrap(ladder.listedSummaries.first { $0.0 == id }).1.status.isUnseenMiss, "converted while asleep")

        ladder.acknowledge(listed: menu)
        XCTAssertTrue(try XCTUnwrap(ladder.listedSummaries.first { $0.0 == id }).1.status.isUnseenMiss,
                      "the match that joined is one the user was not shown, so it is still to be seen")

        ladder.acknowledge(listed: menuListing(ladder))
        XCTAssertEqual(ladder.listedSummaries.count, 0, "and the next menu's click marks it seen")
    }

    func testAMatchThatJoinedAndPlayedItsOwnAlertWhileTheMenuWasOpenIsLeftToo() throws {
        // Nothing repeats, so nothing stands in for the match's alert and it is heard. It
        // is still one the user was not shown, and the guard is not about silence alone.
        let ladder = coordinator()
        let theRule = rule(Escalation(tier2: PanelAlert(delaySeconds: 10)))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(5)
        let menu = menuListing(ladder)
        at(20)
        let join = try XCTUnwrap(match(ladder, theRule, 1).join)
        XCTAssertNotNil(join.alert, "it played its own alert")
        XCTAssertEqual(ownAlerts, 1)

        ladder.acknowledge(listed: menu)
        XCTAssertEqual(ladder.listedSummaries.map(\.0), [id])
        XCTAssertEqual(ladder.listedSummaries.first?.1.matchCount, 2)
        XCTAssertEqual(playerStopped, 0)
    }

    func testWhatAMenuCarriesOfAnEscalationIsItsIdAndItsCountAndNothingMore() {
        let id = EscalationID()
        for count in [1, 2, 7] {
            let summary = EscalationSummary(ruleName: "On-call mentions", startedAt: start,
                                            lastRepeat: .spoke(text: "Alex Example mentioned you", voice: "Daniel", gainDB: 0,
                                                               outputSilent: false),
                                            matchCount: count)
            let listed = ListedEscalation(row: (id, summary))
            XCTAssertEqual(listed, ListedEscalation(id: id, matchCount: count), "from the row as it was listed")
            XCTAssertEqual(Mirror(reflecting: listed).children.compactMap(\.label), ["id", "matchCount"],
                           "no name, no outcome and no word a notification said can ride along")
        }
    }

    // MARK: - What the quit prompt asks

    /// The quit prompt is an alert with capture running behind it (M5 plan, Ruling 22), so a
    /// match can join an escalation it listed while it is up. That raises neither the count of
    /// escalations nor of missed ones, and a silent join has sounded nothing for the match, which
    /// may be owed a page. These ask the policy as the app does, with what stands read afresh from
    /// the coordinator's summaries, through `ask` as the alert, and let the match arrive while it
    /// is showing.

    /// What the app reads: `AppDelegate.applicationShouldTerminate`'s closure, which a test of
    /// the app's sources holds to this expression.
    private func standing(_ ladder: EscalationCoordinator) -> QuitPolicy.Standing {
        QuitPolicy.Standing(listed: ladder.listedSummaries.map(\.1), onCall: false)
    }

    func testAMatchThatJoinsSilentlyWhileTheQuitPromptIsUpIsAskedAboutAgainAndNotQuitAwayUnseen() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(130)
        let named = standing(ladder)
        XCTAssertEqual(named, QuitPolicy.Standing(escalating: 1, missed: 0, matches: 1, onCall: false))

        var shown: [QuitPolicy.Prompt] = []
        var joined: EscalationJoin?
        let mayQuit = QuitPolicy.mayQuit(reason: .user, standing: { standing(ladder) }, noticeAge: { nil }, ask: { prompt in
            shown.append(prompt)
            if shown.count == 1 {
                at(200)
                joined = match(ladder, theRule, 1).join
                let after = standing(ladder)
                XCTAssertEqual(after.escalating, named.escalating, "the join began no escalation")
                XCTAssertEqual(after.missed, named.missed)
                XCTAssertEqual(after.matches, 2, "it is the matches that moved")
            }
            return true
        })

        let join = try XCTUnwrap(joined)
        XCTAssertEqual(join.matchNumber, 2)
        XCTAssertNil(join.alert, "it joined silently: nothing sounded for it")
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(1), "and it is owed a page")
        XCTAssertEqual(shown.map(\.message), [
            "1 alert is still waiting to be acknowledged. Quit anyway?",
            "1 alert (2 matches) is still waiting to be acknowledged. Quit anyway?",
        ], "Quit on the first is not taken for Quit on a prompt that never named the match")
        XCTAssertTrue(mayQuit, "and the answer to the second, which named it, is taken")
    }

    func testCancellingThePromptAskedAgainForAJoinedMatchLeavesTheEscalationAndItsOwedPageRunning() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(130)

        var shown = 0
        let mayQuit = QuitPolicy.mayQuit(reason: .user, standing: { standing(ladder) }, noticeAge: { nil }, ask: { _ in
            shown += 1
            if shown == 1 {
                at(200)
                XCTAssertNotNil(match(ladder, theRule, 1).join)
            }
            return shown == 1
        })

        XCTAssertFalse(mayQuit, "Cancel on the second prompt stops the quit")
        XCTAssertEqual(shown, 2)
        XCTAssertEqual(ladder.listedSummaries.first?.1.status, .live, "nothing was ended")
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(1))
        at(720)
        XCTAssertEqual(shortcutTimes, [120, 720], "and the page it owed goes")
    }

    // MARK: - Calling back in

    func testAnAcknowledgementFromInsideTheJoinsRecordSticksAndTheJoinIsStillAnswered() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier2: PanelAlert(delaySeconds: 10), tier3: repeating(every: 300)))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(20)
        onRecord = { _, summary in
            if summary.matchCount == 2, summary.status == .live { ladder.acknowledge(id) }
        }
        let join = try XCTUnwrap(match(ladder, theRule, 1).join)
        XCTAssertEqual(join.matchNumber, 2)
        XCTAssertEqual(ladder.listedSummaries.count, 0, "acknowledged from inside the record, and it stays so")
        XCTAssertEqual(clock.pendingCount, 0)
        XCTAssertEqual(ladder.trackedCount, 0)
        XCTAssertEqual(power, ["begin", "end"])
        at(1000)
        XCTAssertEqual(repeats, 0, "no repeat comes after it")
    }

    func testAnAcknowledgementFromInsideTheJoinsOwnAlertSticksAndNoShortcutIsRunForAnEndedEscalation() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 300), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(720)
        XCTAssertEqual(shortcutTimes, [120])
        onSound = { ladder.acknowledgeAll() }
        let join = try XCTUnwrap(match(ladder, theRule, 1).join)
        XCTAssertEqual(join.matchNumber, 2)
        XCTAssertNotNil(join.alert, "it was the match's own alert that was acknowledged")
        XCTAssertFalse(join.ranShortcut, "an escalation acknowledged during the join is not paged for")
        XCTAssertEqual(shortcutTimes, [120])
        XCTAssertNil(ladder.bookkeeping(of: id), "and it is retired, so nothing is kept")
        XCTAssertEqual(power, ["begin", "end"])
    }

    func testAnAcknowledgementFromInsideTheRecordOfAJoinThatRunsTheShortcutStillSendsThePageAndLeavesNothingPending() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 300), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        shortcutRuns[0].report(.shortcutLaunched(name: "Page me"))
        at(720)
        onRecord = { _, summary in
            if summary.matchCount == 2, summary.status == .live { ladder.acknowledge(id) }
        }
        let join = try XCTUnwrap(match(ladder, theRule, 1).join)
        XCTAssertTrue(join.ranShortcut, "the run was decided before the record, and goes ahead")
        XCTAssertEqual(shortcutRuns.count, 2)
        XCTAssertNotNil(ladder.bookkeeping(of: id), "held until the run reports, as any acknowledged escalation's run is")
        shortcutRuns[1].report(.shortcutLaunched(name: "Page me"))
        XCTAssertNil(ladder.bookkeeping(of: id), "and then forgotten: nothing was left pending")
        XCTAssertEqual(ladder.trackedCount, 0)
        XCTAssertEqual(retirements, [begun[0].entry])
    }

    func testAMatchThatJoinsFromInsideAnotherJoinsAlertIsCountedOnceEach() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 300)))
        match(ladder, theRule, 0)
        at(10)
        var inner: EscalationJoin?
        onSound = { [self] in
            onSound = nil
            inner = ladder.join(rule: theRule, notification: notification(2))
        }
        let outer = try XCTUnwrap(match(ladder, theRule, 1).join)
        XCTAssertEqual(outer.matchNumber, 2, "the outer match was counted before it called out")
        XCTAssertEqual(inner?.matchNumber, 3)
        XCTAssertEqual(latest(begun[0].entry)?.matchCount, 3)
        XCTAssertEqual(ladder.trackedCount, 1)
    }

    func testAMatchThatJoinsFromInsideAnotherJoinsAlertAndIsOwedAPageIsTheOneThatIsSentAndTheOlderOwesNothing() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 300), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(420)
        XCTAssertEqual(shortcutTimes, [120], "tier 4 ran at 10:02, and 10:07 is inside the 10 minutes")
        let timers = clock.pendingCount
        var inner: EscalationJoin?
        onSound = { [self] in
            onSound = nil
            inner = ladder.join(rule: theRule, notification: notification(2))
        }
        let outer = try XCTUnwrap(match(ladder, theRule, 1).join)
        XCTAssertEqual(outer.matchNumber, 2)
        XCTAssertNotNil(outer.alert, "the repeat is 3 minutes away, so the match plays its own alert, and the other joins from inside it")
        XCTAssertEqual(inner?.matchNumber, 3)
        XCTAssertFalse(outer.ranShortcut)
        XCTAssertEqual(inner?.ranShortcut, false)
        XCTAssertEqual(try kept(ladder, id).owedPage, notification(2),
                       "the page owed is the newer match's, and the older one that was counted first does not replace it")
        XCTAssertEqual(clock.pendingCount, timers + 1, "with the one re-page timer")

        at(720)
        XCTAssertEqual(shortcutTimes, [120, 720], "one page, at 10:12")
        XCTAssertEqual(shortcutNotifications, [notification(0), notification(2)], "with the newer match's fields")
        at(2000)
        XCTAssertEqual(shortcutRuns.count, 0)
        XCTAssertEqual(shortcutTimes, [120, 720], "and no page for the older one after it")
        XCTAssertNil(try kept(ladder, id).owedPage)
    }

    func testAMatchThatJoinsFromInsideAnotherJoinsAlertAndRunsTheShortcutLeavesTheOlderOwedNothingAndNoSecondPage() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 300), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        report(run: 0, .shortcutLaunched(name: "Page me"))
        at(720)
        let timers = clock.pendingCount
        var inner: EscalationJoin?
        onSound = { [self] in
            onSound = nil
            inner = ladder.join(rule: theRule, notification: notification(2))
        }
        let outer = try XCTUnwrap(match(ladder, theRule, 1).join)
        XCTAssertEqual(outer.matchNumber, 2)
        XCTAssertEqual(inner?.matchNumber, 3)
        XCTAssertEqual(inner?.ranShortcut, true, "the newer match is 10 minutes after the last run, and runs it")
        XCTAssertFalse(outer.ranShortcut, "the older one is covered by it")
        XCTAssertEqual(shortcutRuns.count, 2)
        XCTAssertEqual(shortcutNotifications, [notification(0), notification(2)])
        XCTAssertNil(try kept(ladder, id).owedPage, "and is not owed a page behind a run that is pending")
        XCTAssertEqual(clock.pendingCount, timers, "no re-page timer is armed")

        report(run: 1, .shortcutLaunched(name: "Page me"))
        at(3000)
        XCTAssertEqual(shortcutRuns.count, 2, "nothing is paged for the older match 10 minutes after")
    }
}
