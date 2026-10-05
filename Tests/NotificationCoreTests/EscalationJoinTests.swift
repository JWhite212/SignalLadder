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
/// The pipeline does not ask the coordinator yet, so `match` below does what
/// the pipeline will do with a match: ask first, and when nothing joins, play
/// tier 1, which is the pipeline's own alert and is counted in `firstAlerts`
/// and not in `sounds`, and begin. What the coordinator's closures played, a
/// repeat, a final alert or the alert of a match that joined and was not
/// silent, is `sounds`.
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

    func testAShortcutAfter120SecondsOverTheHourRunsAt120AndThenNoMoreOftenThanEvery600WithTheJoiningMatchsFields() throws {
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
                       "tier 4 at 120 s, and then a joined match at 600 s or more after the last run started")
        XCTAssertEqual(shortcutNotifications, [0, 24, 44, 64, 84, 104].map(notification),
                       "tier 4's with the first match's fields, and each later run with the fields of the match that caused it")
        XCTAssertEqual(ran, [25, 45, 65, 85, 105], "the joins that say they ran it: every one but tier 4's")
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
        XCTAssertEqual(shortcutTimes, [120, 750, 1350, 1950, 2550, 3150],
                       "tier 4, and then the first match 600 seconds or more after each run started")
        XCTAssertEqual(shortcutNotifications, [0, 15, 27, 39, 51, 63].map(notification))
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

    // MARK: - Tier 4 and re-paging, where nothing is owed

    func testAMatchThatJoinsBeforeTier4RunsRaisesTheCountAndRunsNothing() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        match(ladder, theRule, 0)
        at(60)
        let join = try XCTUnwrap(match(ladder, theRule, 1).join)
        XCTAssertEqual(join.matchNumber, 2)
        XCTAssertFalse(join.ranShortcut)
        XCTAssertEqual(shortcutNotifications, [], "tier 4 has not run, and will")
        XCTAssertEqual(latest(try XCTUnwrap(begun.first).entry)?.matchCount, 2)
        at(120)
        XCTAssertEqual(shortcutNotifications, [notification(0)], "and when it does it is given the first match's fields")
    }

    func testTheFirstJoinAtOrAfterTenMinutesRunsTheShortcutOnceMoreWithItsOwnFourFieldsAndAnotherAtOnceDoesNot() throws {
        shortcutsReportAtOnce = .shortcutLaunched(name: "Page me")
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        let id = try XCTUnwrap(match(ladder, theRule, 0).beganID)
        at(120)
        XCTAssertEqual(shortcutTimes, [120])
        at(600)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut, "480 s after the run began")
        at(719)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 2).join).ranShortcut, "599 s")
        at(720)
        let join = try XCTUnwrap(match(ladder, theRule, 3).join)
        XCTAssertTrue(join.ranShortcut, "600 s: at least the re-page time")
        XCTAssertEqual(shortcutTimes, [120, 720])
        let given = try XCTUnwrap(shortcutNotifications.last)
        XCTAssertEqual([given.appNameGuess, given.title, given.subtitle, given.body],
                       ["Microsoft Teams", "Incident 3", "Channel 3", "Body 3"], "the four fields of the joining match")
        XCTAssertEqual(try kept(ladder, id).lastShortcutRunAt, EscalationCoordinator.Stamp(wall: start + 720, awake: 720),
                       "and the run's time is recorded, on both clocks")
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 4).join).ranShortcut, "another at once does not")
        at(725)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 5).join).ranShortcut)
        at(1320)
        XCTAssertTrue(try XCTUnwrap(match(ladder, theRule, 6).join).ranShortcut, "and 600 s after that one it does again")
        XCTAssertEqual(shortcutTimes, [120, 720, 1320])
    }

    func testAMatchThatJoinsAfterAFailedRunRunsItAgainAtOnceAndNeverWhileARunIsPending() throws {
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating(every: 15), tier4: pageMe))
        match(ladder, theRule, 0)
        at(120)
        XCTAssertEqual(shortcutRuns.count, 1)
        at(125)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 1).join).ranShortcut, "the first run has not reported")

        shortcutRuns[0].report(.shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed"))
        at(130)
        let again = try XCTUnwrap(match(ladder, theRule, 2).join)
        XCTAssertTrue(again.ranShortcut, "the last run failed: tried again at once, inside the 10 minutes")
        XCTAssertEqual(shortcutNotifications.last, notification(2))
        XCTAssertEqual(shortcutRuns.count, 2)

        at(131)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 3).join).ranShortcut,
                       "a run is pending, though the report that is held is still a failure")
        XCTAssertEqual(shortcutRuns.count, 2)

        shortcutRuns[1].report(.shortcutFailed(name: "Page me", reason: "x"))
        at(140)
        XCTAssertTrue(try XCTUnwrap(match(ladder, theRule, 4).join).ranShortcut, "and a failure is tried again once it has reported")
        shortcutRuns[2].report(.shortcutLaunched(name: "Page me"))
        at(150)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 5).join).ranShortcut,
                       "a run that started is not retried: it needs the re-page time")
        XCTAssertEqual(shortcutRuns.count, 3)
        XCTAssertEqual(latest(try XCTUnwrap(begun.first).entry)?.finalCount, 3, "each report that came was counted once")
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

        // A Shortcut that always fails and reports at once is tried by each match that arrives after the last reported.
        shortcutsReportAtOnce = .shortcutFailed(name: "Page me", reason: "x")
        shortcutRuns[0].report(.shortcutFailed(name: "Page me", reason: "x"))
        let before = shortcutTimes.count
        for index in 21...40 {
            at(120 + Double(index))
            XCTAssertTrue(try XCTUnwrap(match(ladder, theRule, index).join).ranShortcut, "the last run failed and none is pending")
        }
        XCTAssertEqual(shortcutTimes.count - before, 20)
        XCTAssertEqual(latest(try XCTUnwrap(begun.first).entry)?.finalCount, 21, "the first report and one for each retry")
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
        XCTAssertTrue(try XCTUnwrap(match(ladder, theRule, 2).join).ranShortcut,
                      "600 s by the awake clock, whatever the wall clock was set to: an hour back would hold a page off for an hour")

        // A sleep too short to convert, which only the wall clock counts, is time too.
        at(1000)
        XCTAssertFalse(try XCTUnwrap(match(ladder, theRule, 3).join).ranShortcut, "280 s after the last run")
        clock.sleep(for: 250)
        at(1100)
        XCTAssertTrue(try XCTUnwrap(match(ladder, theRule, 4).join).ranShortcut,
                      "380 s awake and 630 s by the wall clock: a sleep that converts nothing still makes the run older")
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

    func testAJoinLeavesTheTrackedCountThePendingTimersTheDueTimesAndThePowerAssertionAsTheyWere() throws {
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
        XCTAssertEqual(try snapshot(), before)
        at(250)
        let atTier4 = try snapshot()
        XCTAssertEqual(atTier4, Snapshot(tracked: 1, timers: 1, repeatDue: 300, power: ["begin"], hasPendingTiers: true),
                       "tier 4 has fired since, and that is all that changed")
        XCTAssertNil(match(ladder, theRule, 3).join?.alert, "silent: due in 50")
        XCTAssertEqual(try snapshot(), atTier4)
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

        let paged = rule("Paged", Escalation(tier3: repeating(every: 15), tier4: pageMe))
        match(ladder, paged, 3)
        at(clock.awakeTime() + 120)
        XCTAssertEqual(shortcutTimes.count, 1)
        at(clock.awakeTime() + 99)
        XCTAssertFalse(try XCTUnwrap(match(ladder, paged, 4).join).ranShortcut, "99 s after the run, and the time is 100")
        at(clock.awakeTime() + 1)
        XCTAssertTrue(try XCTUnwrap(match(ladder, paged, 5).join).ranShortcut, "100 s")
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
}
