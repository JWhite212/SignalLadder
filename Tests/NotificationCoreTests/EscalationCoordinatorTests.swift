import XCTest
@testable import NotificationCore

/// The escalation coordinator (M4 Task 3). Every clock is `ManualScheduler`'s,
/// and every closure a fake that only records what it was called with: no
/// real player, panel, process or timer. Fixtures are invented text (§10.1).
@MainActor
final class EscalationCoordinatorTests: XCTestCase {
    private var clock: ManualScheduler!
    private var sounds: [String] = []
    private var soundOutcome: (String) -> AlertOutcome = { .played(sound: $0, gainDB: 0, outputSilent: false) }
    private var panels: [[(EscalationID, EscalationSummary)]] = []
    private var records: [(UUID, EscalationSummary)] = []
    private var retirements: [UUID] = []
    /// Records and retirements in the order they came, per row.
    private var events: [(kind: String, row: UUID)] = []
    private var power: [String] = []
    private var silences = 0
    private var shortcutRuns: [(name: String, report: (FinalOutcome) -> Void)] = []
    private var shortcutsReportAtOnce: FinalOutcome?
    private var spoken: [String] = []
    private var shortcutNotifications: [CapturedNotification] = []
    /// Runs inside a sound, or a record, as a re-entrant caller would.
    private var onSound: (() -> Void)?
    private var onRecord: ((EscalationSummary) -> Void)?

    private let notification = CapturedNotification(
        timestamp: Date(timeIntervalSince1970: 1_790_000_000), appNameGuess: "Microsoft Teams",
        title: "Alex Example mentioned you", subtitle: "General", body: "Placeholder body text",
        rawText: "Microsoft Teams, Alex Example mentioned you, Placeholder body text",
        subrole: "AXNotificationCenterAlert")

    private let hero = AlertAction.sound(name: "Hero", gainDB: 0)
    private let glass = AlertAction.sound(name: "Glass", gainDB: 0)

    override func setUp() {
        clock = ManualScheduler()
        sounds = []
        panels = []
        records = []
        retirements = []
        events = []
        power = []
        silences = 0
        shortcutRuns = []
        shortcutsReportAtOnce = nil
        spoken = []
        shortcutNotifications = []
        onSound = nil
        onRecord = nil
    }

    private func coordinator(threshold: TimeInterval = 300) -> EscalationCoordinator {
        EscalationCoordinator(
            scheduler: clock,
            playSound: { [unowned self] name, _ in sounds.append(name); onSound?(); return soundOutcome(name) },
            speak: { [unowned self] text, speech in sounds.append("speech:\(speech.voiceIdentifier)"); spoken.append(text)
                onSound?(); return .spoke(text: text, voice: speech.voiceIdentifier, gainDB: 0, outputSilent: false) },
            playAndSpeak: { [unowned self] name, _, text, _ in sounds.append("\(name)+speech"); spoken.append(text)
                onSound?(); return .played(sound: name, gainDB: 0, outputSilent: false) },
            runShortcut: { [unowned self] name, notification, report in
                shortcutNotifications.append(notification)
                if let outcome = shortcutsReportAtOnce { report(outcome) } else { shortcutRuns.append((name, report)) }
            },
            updatePanel: { [unowned self] rows in panels.append(rows) },
            recordSummary: { [unowned self] entry, summary in
                records.append((entry, summary)); events.append(("record", entry)); onRecord?(summary)
            },
            retired: { [unowned self] entry in retirements.append(entry); events.append(("retired", entry)) },
            beginPowerAssertion: { [unowned self] in power.append("begin") },
            endPowerAssertion: { [unowned self] in power.append("end") },
            silenceIfIdle: { [unowned self] in silences += 1 },
            stalenessThreshold: threshold)
    }

    private func rule(_ name: String, _ ladder: Escalation) -> Rule {
        Rule(name: name, condition: .field(.app, .equals, "Microsoft Teams"), alert: .silent, escalation: ladder)
    }

    private func rule(_ ladder: Escalation) -> Rule { rule("On-call mentions", ladder) }

    private func repeating(every interval: TimeInterval = 30, maxRepeats: Int? = 20,
                           maxDuration: TimeInterval? = 600) -> RepeatAlert {
        RepeatAlert(action: hero, intervalSeconds: interval, maxRepeats: maxRepeats, maxDurationSeconds: maxDuration)
    }

    private var last: EscalationSummary? { records.last?.1 }
    private var start: Date { Date(timeIntervalSince1970: 1_790_000_000) }

    // MARK: - Tier 3: repeating, and its caps

    func testARepeatFiresEveryIntervalAndStopsAtMaxRepeats() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating(maxRepeats: 3, maxDuration: nil))),
                     notification: notification, entryID: UUID())
        clock.advance(by: 29)
        XCTAssertEqual(sounds, [])
        clock.advance(by: 1)
        XCTAssertEqual(sounds, ["Hero"])
        clock.advance(by: 600)
        XCTAssertEqual(sounds, ["Hero", "Hero", "Hero"])
        XCTAssertEqual(last?.repeatCount, 3)
        XCTAssertEqual(last?.status, .capped(at: start + 90))
        XCTAssertTrue(ladder.hasLiveEscalations, "capped is not the end (ruling 10)")
    }

    func testARepeatStopsAtMaxDurationWhenThatComesFirst() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating(maxRepeats: 20, maxDuration: 100))),
                     notification: notification, entryID: UUID())
        clock.advance(by: 1000)
        XCTAssertEqual(sounds.count, 3, "at 30, 60 and 90; 120 is past the limit")
        XCTAssertEqual(last?.status, .capped(at: start + 90))
    }

    func testTheDefaultCapsAllowTwentyRepeatsInTenMinutes() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        clock.advance(by: 3600)
        XCTAssertEqual(sounds.count, 20)
        XCTAssertEqual(last?.status, .capped(at: start + 600))
        XCTAssertEqual(last?.repeatCap, 20)
    }

    func testTimersALittleLateStillGiveEveryRepeat() {
        // Real timers are never early and often a few milliseconds late.
        // Measured against the clock, the twentieth repeat fell past ten
        // minutes and was lost (review, 2026-09-30).
        clock.lateness = 0.0035
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        clock.advance(by: 3600)
        XCTAssertEqual(sounds.count, 20)
        XCTAssertEqual(last?.repeatCount, 20)
    }

    func testALimitEqualToOneIntervalAllowsThatOneRepeat() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating(every: 30, maxRepeats: nil, maxDuration: 30))),
                     notification: notification, entryID: UUID())
        clock.advance(by: 300)
        XCTAssertEqual(sounds.count, 1)
        XCTAssertEqual(last?.status, .capped(at: start + 30))
    }

    func testALimitShorterThanOneIntervalIsCappedAtOnce() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating(every: 30, maxRepeats: nil, maxDuration: 10))),
                     notification: notification, entryID: UUID())
        XCTAssertEqual(last?.status, .capped(at: start))
        clock.advance(by: 100)
        XCTAssertEqual(sounds, [])
    }

    func testWhetherARepeatIsInTimeIsOneRuleForTheCoordinatorAndTheEditor() {
        func fits(_ number: Int, every interval: Double, within limit: Double?) -> Bool {
            let instance = RepeatAlert(action: hero, intervalSeconds: interval, maxRepeats: nil, maxDurationSeconds: limit)
                .timeLimitAllowsRepeat(number: number)
            let sameRule = RepeatAlert.timeLimitAllowsRepeat(number: number, intervalSeconds: interval, maxDurationSeconds: limit)
            XCTAssertEqual(instance, sameRule, "the instance asks the static rule")
            return instance
        }
        XCTAssertTrue(fits(1, every: 900, within: nil), "no limit allows every repeat")
        XCTAssertTrue(fits(10_000, every: 900, within: nil))
        XCTAssertFalse(fits(1, every: 900, within: 600), "a limit shorter than one interval allows none")
        XCTAssertTrue(fits(1, every: 600, within: 600), "a limit equal to one interval allows that one")
        XCTAssertFalse(fits(2, every: 600, within: 600), "and no second")
        XCTAssertTrue(fits(20, every: 30, within: 600))
        XCTAssertFalse(fits(21, every: 30, within: 600))
        XCTAssertTrue(fits(3, every: 0.1, within: 0.3), "by the schedule: 3 x 0.1 is a hair over 0.3 in floating point")
        XCTAssertFalse(fits(1, every: 30, within: 29.99), "but a real shortfall is a shortfall")
    }

    func testTheEditorsSentenceSaysItNeverRepeatsExactlyWhenTheCoordinatorPlaysNoRepeat() {
        let cases: [(interval: Double, maxRepeats: Int?, maxDuration: Double?)] = [
            (30, 20, 600), (900, 20, 600), (900, nil, 600), (600, 20, 600), (601, 20, 600), (900, 20, nil),
            (30, nil, 29), (30, nil, 30), (30, 1, 30), (0.1, nil, 0.3),
        ]
        for c in cases {
            clock = ManualScheduler()
            sounds = []
            records = []
            let tier3 = repeating(every: c.interval, maxRepeats: c.maxRepeats, maxDuration: c.maxDuration)
            let ladder = coordinator()
            ladder.begin(rule: rule(Escalation(tier3: tier3)), notification: notification, entryID: UUID())
            clock.advance(by: 3600)
            let said = EditorText.ladderSentence(Escalation(tier3: tier3)).hasPrefix("It never repeats")
            XCTAssertEqual(said, sounds.isEmpty,
                           "every \(c.interval) s, at most \(String(describing: c.maxRepeats)), limit \(String(describing: c.maxDuration)): played \(sounds.count)")
        }
    }

    // MARK: - The tiers run apart

    func testEachTierRunsOnItsOwnTimerFromTheStart() {
        // Tier 4 does not wait for tier 3's repeats to end (ruling 9).
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 10), tier3: repeating(),
                                           tier4: FinalAlert(afterSeconds: 125, action: .alert(glass)))),
                     notification: notification, entryID: UUID())
        clock.advance(by: 10)
        XCTAssertEqual(last?.tierReached, 2)
        XCTAssertEqual(sounds, [])
        clock.advance(by: 120)
        XCTAssertEqual(sounds, ["Hero", "Hero", "Hero", "Hero", "Glass"])
        XCTAssertEqual(last?.tierReached, 4)
        XCTAssertEqual(last?.final, .alerted(.played(sound: "Glass", gainDB: 0, outputSilent: false)))
        XCTAssertEqual(last?.status, .live, "tier 3 has not reached its cap")
    }

    func testARuleWithNoLadderStartsNothing() {
        let ladder = coordinator()
        let plain = Rule(name: "a", condition: .field(.app, .equals, "x"), alert: hero)
        XCTAssertNil(ladder.begin(rule: plain, notification: notification, entryID: UUID()))
        XCTAssertEqual(clock.pendingCount, 0)
        XCTAssertEqual(records.count, 0)
    }

    // MARK: - Sleep

    func testAnHourAwakeConvertsNothing() {
        // The test that would have caught Ruling 14's first version, which
        // ended every escalation at five minutes, asleep or not.
        let ladder = coordinator()
        let uncapped = UUID()
        ladder.begin(rule: rule("Uncapped", Escalation(tier3: repeating(maxRepeats: nil, maxDuration: nil))),
                     notification: notification, entryID: uncapped)
        let capped = UUID()
        ladder.begin(rule: rule("Capped", Escalation(tier3: repeating(maxRepeats: 1, maxDuration: nil))),
                     notification: notification, entryID: capped)
        clock.advance(by: 3600)
        XCTAssertEqual(records.last { $0.0 == uncapped }?.1.repeatCount, 120)
        XCTAssertEqual(records.last { $0.0 == uncapped }?.1.status, .live)
        XCTAssertEqual(records.last { $0.0 == capped }?.1.status, .capped(at: start + 30))
    }

    func testALongSleepEndsEverythingStillGoingWhenTheNextTierFallsDue() {
        let ladder = coordinator()
        let row = UUID()
        ladder.begin(rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 10),
                                           tier3: repeating(maxRepeats: nil, maxDuration: nil))),
                     notification: notification, entryID: row)
        let done = UUID()
        let acknowledged = ladder.begin(rule: rule("Already seen", Escalation(tier3: repeating())),
                                        notification: notification, entryID: done)!
        ladder.acknowledge(acknowledged)
        let recordsOfDone = records.filter { $0.0 == done }.count
        clock.advance(by: 31)
        XCTAssertEqual(sounds.count, 1)

        clock.sleep(for: 301)
        let woke = clock.now()
        clock.advance(by: 30)
        XCTAssertEqual(sounds.count, 1, "nothing stale fires on waking")
        XCTAssertEqual(records.last { $0.0 == row }?.1.status, .missedWhileAsleep(convertedAt: woke + 29, acknowledgedAt: nil))
        XCTAssertEqual(clock.pendingCount, 0, "its timers are cancelled")
        XCTAssertEqual(panels.last?.map(\.1.status), [.missedWhileAsleep(convertedAt: woke + 29, acknowledgedAt: nil)],
                       "it stays on the panel, so waking shows what was missed")
        XCTAssertEqual(records.filter { $0.0 == done }.count, recordsOfDone, "one already acknowledged is untouched")
    }

    func testAShortSleepResumes() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating(maxRepeats: nil, maxDuration: nil))),
                     notification: notification, entryID: UUID())
        clock.advance(by: 31)
        clock.sleep(for: 299)
        clock.advance(by: 30)
        XCTAssertEqual(sounds.count, 2)
        XCTAssertEqual(last?.status, .live)
    }

    func testTheWakeCheckConvertsAtOnceEvenWithNothingLeftToFire() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 10))), notification: notification, entryID: UUID())
        clock.advance(by: 11)
        XCTAssertEqual(clock.pendingCount, 0)
        clock.sleep(for: 301)
        ladder.checkForSleep()
        XCTAssertEqual(last?.status, .missedWhileAsleep(convertedAt: clock.now(), acknowledgedAt: nil))
        XCTAssertFalse(ladder.hasLiveEscalations)
        XCTAssertEqual(ladder.listedSummaries.count, 1)
    }

    func testAMainThreadStallIsNotASleep() {
        // Both clocks move together, so fifteen minutes with nothing firing is
        // fifteen minutes awake, not a sleep: what is measured is the sleep,
        // never the time elapsed.
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification, entryID: UUID())
        clock.advance(by: 900)
        ladder.checkForSleep()
        XCTAssertEqual(last?.status, .live)
    }

    func testAnEscalationStartedAfterASleepIsMeasuredFromItsStart() {
        // The sleep belongs to what was running before it, not to what began
        // afterwards, even when the wake notification never came.
        let ladder = coordinator()
        let before = UUID()
        ladder.begin(rule: rule("Before", Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification, entryID: before)
        clock.advance(by: 1)
        clock.sleep(for: 400)
        let after = UUID()
        ladder.begin(rule: rule("After", Escalation(tier3: repeating())), notification: notification, entryID: after)
        XCTAssertEqual(records.last { $0.0 == before }?.1.status, .missedWhileAsleep(convertedAt: clock.now(), acknowledgedAt: nil))
        clock.advance(by: 30)
        XCTAssertEqual(records.last { $0.0 == after }?.1.status, .live)
        XCTAssertEqual(sounds.count, 1)
    }

    // MARK: - Concurrent escalations

    func testTwoEscalationsRunApartAndAcknowledgeAllEndsBoth() {
        let ladder = coordinator()
        let first = ladder.begin(rule: rule("First", Escalation(tier3: repeating())), notification: notification, entryID: UUID())!
        let second = ladder.begin(rule: rule("Second", Escalation(tier3: repeating())), notification: notification, entryID: UUID())!
        XCTAssertNotEqual(first, second)
        clock.advance(by: 30)
        XCTAssertEqual(sounds.count, 2)

        ladder.acknowledge(first)
        clock.advance(by: 30)
        XCTAssertEqual(sounds.count, 3, "the other goes on")
        XCTAssertEqual(ladder.listedSummaries.map(\.1.ruleName), ["Second"])

        ladder.acknowledgeAll()
        clock.advance(by: 300)
        XCTAssertEqual(sounds.count, 3)
        XCTAssertFalse(ladder.hasLiveEscalations)
        XCTAssertEqual(clock.pendingCount, 0)
    }

    func testTheAlertRunnerKnowsNothingOfALiveRepeat() {
        // Pins AlertActionRunner, not the coordinator: a fresh tier 1 goes
        // through the same closures as a live repeat, and nothing in between
        // suppresses it; interrupting is the player's job (ruling 7). With a
        // real pipeline: EscalationWiringTests' end-to-end tests; with a real
        // player: AlertPlayerTests' interruption tests, and Task 7's check
        // that two escalations' sounds never overlap.
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        clock.advance(by: 30)
        let outcome = AlertActionRunner.run(glass, for: notification,
                                            playSound: { [unowned self] name, _ in sounds.append(name); return .silentByRule },
                                            speak: { _, _ in .silentByRule }, playAndSpeak: { _, _, _, _ in .silentByRule })
        XCTAssertEqual(outcome, .silentByRule)
        XCTAssertEqual(sounds, ["Hero", "Glass"])
    }

    // MARK: - The power assertion

    func testThePowerAssertionIsHeldExactlyWhileATierIsPending() {
        let ladder = coordinator()
        ladder.begin(rule: rule("A", Escalation(tier3: repeating(maxRepeats: 2, maxDuration: nil),
                                                tier4: FinalAlert(afterSeconds: 70, action: .alert(glass)))),
                     notification: notification, entryID: UUID())
        clock.advance(by: 5)
        ladder.begin(rule: rule("B", Escalation(tier2: PanelAlert(delaySeconds: 10))), notification: notification, entryID: UUID())
        XCTAssertEqual(power, ["begin"], "claimed once for both")
        clock.advance(by: 64)
        XCTAssertEqual(power, ["begin"], "A's tier 4 is still to fire")
        clock.advance(by: 1)
        XCTAssertEqual(power, ["begin", "end"])
        XCTAssertEqual(ladder.listedSummaries.first { $0.1.ruleName == "A" }?.1.status, .capped(at: start + 60),
                       "still capped and listed, but holding nothing")
        XCTAssertFalse(ladder.hasPendingTiers)

        ladder.begin(rule: rule("C", Escalation(tier2: PanelAlert())), notification: notification, entryID: UUID())
        XCTAssertEqual(power, ["begin", "end", "begin"])
    }

    func testAcknowledgingReleasesThePowerAssertion() {
        let ladder = coordinator()
        let id = ladder.begin(rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())!
        ladder.acknowledge(id)
        XCTAssertEqual(power, ["begin", "end"])
        XCTAssertEqual(clock.pendingCount, 0, "its timers are cancelled, not left to fire into nothing")
    }

    // MARK: - The panel

    func testThePanelListsOnlyEscalationsWhoseTier2HasShown() {
        let ladder = coordinator()
        ladder.begin(rule: rule("Panel", Escalation(tier2: PanelAlert(delaySeconds: 10), tier3: repeating())),
                     notification: notification, entryID: UUID())
        ladder.begin(rule: rule("No panel", Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        clock.advance(by: 9)
        XCTAssertTrue(panels.allSatisfy(\.isEmpty), "nothing before tier 2 has shown")
        clock.advance(by: 1)
        XCTAssertEqual(panels.last?.map(\.1.ruleName), ["Panel"], "and never one with no tier 2")
        XCTAssertEqual(ladder.listedSummaries.map(\.1.ruleName), ["No panel", "Panel"], "the menu lists both, newest first")
    }

    func testAMissedEscalationStaysOnThePanelUntilAcknowledgedAndStaysMissed() {
        let ladder = coordinator()
        let id = ladder.begin(rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 10), tier3: repeating())),
                              notification: notification, entryID: UUID())!
        clock.advance(by: 10)
        clock.sleep(for: 400)
        ladder.checkForSleep()
        let converted = clock.now()
        XCTAssertEqual(panels.last?.count, 1)

        clock.advance(by: 5)
        ladder.acknowledge(id)
        XCTAssertEqual(last?.status, .missedWhileAsleep(convertedAt: converted, acknowledgedAt: clock.now()))
        XCTAssertEqual(panels.last?.count, 0)
        XCTAssertEqual(ladder.listedSummaries.count, 0)
    }

    func testAcknowledgeAllMarksEveryMissedEscalationSeen() {
        let ladder = coordinator()
        for name in ["A", "B"] {
            ladder.begin(rule: rule(name, Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification, entryID: UUID())
        }
        clock.advance(by: 1)
        clock.sleep(for: 400)
        ladder.checkForSleep()
        ladder.acknowledgeAll()
        XCTAssertEqual(ladder.listedSummaries.count, 0)
        XCTAssertEqual(records.suffix(2).map { $0.1.status },
                       Array(repeating: .missedWhileAsleep(convertedAt: clock.now(), acknowledgedAt: clock.now()), count: 2))
    }

    // MARK: - A timer that arrives late

    func testATierRunAfterItsEscalationEndedDoesNothing() {
        let ladder = coordinator()
        let id = ladder.begin(rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 10), tier3: repeating(),
                                                    tier4: FinalAlert(afterSeconds: 60, action: .alert(glass)))),
                              notification: notification, entryID: UUID())!
        ladder.acknowledge(id)
        let recorded = records.count
        XCTAssertEqual(clock.runCancelled(), 3)
        XCTAssertEqual(sounds, [])
        XCTAssertEqual(records.count, recorded)
    }

    func testATimerDeliveredTwiceActsOnce() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating(maxRepeats: nil, maxDuration: nil),
                                           tier4: FinalAlert(afterSeconds: 45, action: .alert(glass)))),
                     notification: notification, entryID: UUID())
        clock.advance(by: 30)
        XCTAssertEqual(clock.refireLast(), 1)
        XCTAssertEqual(sounds, ["Hero"], "one repeat, and one next repeat armed")
        clock.advance(by: 15)
        XCTAssertEqual(clock.refireLast(), 1)
        XCTAssertEqual(sounds, ["Hero", "Glass"])
        clock.advance(by: 15)
        XCTAssertEqual(sounds, ["Hero", "Glass", "Hero"])
        XCTAssertEqual(clock.pendingCount, 1)
    }

    func testATierRunAfterASleepConvertedItDoesNothing() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        clock.sleep(for: 400)
        ladder.checkForSleep()
        XCTAssertEqual(clock.runCancelled(), 1)
        XCTAssertEqual(sounds, [])
    }

    // MARK: - What is recorded

    func testEveryChangeIsRecordedOnTheRowItBeganFrom() {
        let ladder = coordinator()
        let row = UUID()
        let id = ladder.begin(rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 10),
                                                    tier3: repeating(maxRepeats: 1, maxDuration: nil))),
                              notification: notification, entryID: row)!
        clock.advance(by: 30)
        ladder.acknowledge(id)
        XCTAssertEqual(Set(records.map(\.0)), [row])
        XCTAssertEqual(records.map { $0.1.status }, [.live, .live, .capped(at: start + 30), .acknowledged(at: start + 30)])
    }

    func testAFailedRepeatIsRecorded() {
        soundOutcome = { _ in .failed("sound \"Hero\" was not found") }
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        clock.advance(by: 30)
        XCTAssertEqual(last?.lastRepeat, .failed("sound \"Hero\" was not found"))
    }

    func testAFailedShortcutIsRecorded() {
        shortcutsReportAtOnce = .shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed")
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier4: FinalAlert(afterSeconds: 60, action: .shortcut(name: "Page me")))),
                     notification: notification, entryID: UUID())
        clock.advance(by: 60)
        XCTAssertEqual(last?.final, .shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed"))
        XCTAssertEqual(last?.tierReached, 4)
    }

    func testAShortcutThatReportsLateHoldsNothingUpAndIsStillRecorded() {
        let ladder = coordinator()
        let id = ladder.begin(rule: rule(Escalation(tier3: repeating(maxRepeats: nil, maxDuration: nil),
                                                    tier4: FinalAlert(afterSeconds: 10, action: .shortcut(name: "Page me")))),
                              notification: notification, entryID: UUID())!
        clock.advance(by: 10)
        XCTAssertEqual(shortcutRuns.map(\.name), ["Page me"])
        clock.advance(by: 50)
        XCTAssertEqual(sounds.count, 2, "the repeats went on while it ran")
        ladder.acknowledge(id)
        XCTAssertEqual(last?.status, .acknowledged(at: start + 60))

        shortcutRuns[0].report(.shortcutLaunched(name: "Page me"))
        XCTAssertEqual(last?.final, .shortcutLaunched(name: "Page me"))
        XCTAssertEqual(last?.status, .acknowledged(at: start + 60), "and changes nothing else")
        XCTAssertEqual(ladder.listedSummaries.count, 0)
    }

    // MARK: - Silencing

    func testAcknowledgingTheOnlyLiveEscalationSilences() {
        let ladder = coordinator()
        let id = ladder.begin(rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())!
        ladder.acknowledge(id)
        XCTAssertEqual(silences, 1)
    }

    func testAcknowledgeAllWithOneLiveEscalationSilencesOnce() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        ladder.acknowledgeAll()
        XCTAssertEqual(silences, 1)
    }

    func testAcknowledgeAllWithTwoLiveEscalationsSilencesOnce() {
        let ladder = coordinator()
        ladder.begin(rule: rule("A", Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        ladder.begin(rule: rule("B", Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        ladder.acknowledgeAll()
        XCTAssertEqual(silences, 1)
    }

    func testAcknowledgingOneOfTwoNeverSilences() {
        // The player cannot tell whose sound is playing (ruling 8).
        let ladder = coordinator()
        let first = ladder.begin(rule: rule("A", Escalation(tier3: repeating())), notification: notification, entryID: UUID())!
        ladder.begin(rule: rule("B", Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        ladder.acknowledge(first)
        XCTAssertEqual(silences, 0)
        XCTAssertTrue(ladder.hasLiveEscalations)
    }

    func testAcknowledgingAMissedEscalationNeverSilences() {
        let ladder = coordinator()
        let id = ladder.begin(rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification, entryID: UUID())!
        clock.sleep(for: 400)
        ladder.checkForSleep()
        ladder.acknowledge(id)
        XCTAssertEqual(silences, 0, "it has no sound of its own to stop")
    }

    func testAcknowledgeAllWithOnlyMissedEscalationsSilencesOnce() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification, entryID: UUID())
        clock.sleep(for: 400)
        ladder.checkForSleep()
        ladder.acknowledgeAll()
        XCTAssertEqual(silences, 1, "the one gesture that stops everything")
    }

    func testAcknowledgeAllWithNothingListedDoesNothing() {
        coordinator().acknowledgeAll()
        XCTAssertEqual(silences, 0)
        XCTAssertEqual(panels.count, 0)
    }

    func testAcknowledgingTwiceDoesNothingTheSecondTime() {
        let ladder = coordinator()
        let id = ladder.begin(rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())!
        ladder.acknowledge(id)
        let recorded = records.count
        ladder.acknowledge(id)
        XCTAssertEqual(records.count, recorded)
        XCTAssertEqual(silences, 1)
    }

    // MARK: - Acknowledging the ids a menu listed (M5 plan, Ruling 22)

    private var laddered: Escalation { Escalation(tier2: PanelAlert(delaySeconds: 1), tier3: repeating()) }

    func testAcknowledgingTheIdsListedLeavesAnEscalationBegunAfterwardsLive() {
        // Capture runs while the status menu is open, so an escalation can
        // begin in the seconds it is held. Its item still reads Acknowledge All
        // for the set it listed, and a click must not end one never shown.
        let ladder = coordinator()
        ladder.begin(rule: rule("A", laddered), notification: notification, entryID: UUID())
        ladder.begin(rule: rule("B", laddered), notification: notification, entryID: UUID())
        clock.advance(by: 2)
        let listedWhenBuilt = Set(ladder.listedSummaries.map(\.0))
        XCTAssertEqual(listedWhenBuilt.count, 2)

        let later = ladder.begin(rule: rule("C", laddered), notification: notification, entryID: UUID())!
        ladder.acknowledge(ids: listedWhenBuilt)

        XCTAssertEqual(ladder.listedSummaries.map(\.0), [later], "still listed, and the only one")
        XCTAssertTrue(ladder.hasLiveEscalations)
        XCTAssertEqual(silences, 0, "something is still escalating, so nothing is stopped")
        XCTAssertEqual(power, ["begin"], "and the Mac is still held for its tiers")
        XCTAssertEqual(clock.pendingCount, 2, "its panel timer and its repeat are still armed")

        clock.advance(by: 31)
        XCTAssertEqual(sounds, ["Hero"], "its repeat still sounds, and the two that ended no longer do")
        XCTAssertEqual(panels.last?.map(\.0), [later], "and it takes its place on the panel when its tier 2 shows")
        XCTAssertEqual(last?.status, .live)
    }

    func testAcknowledgingTheOneThatBeganLaterByItsOwnIdThenSilences() {
        let ladder = coordinator()
        let first = ladder.begin(rule: rule("A", laddered), notification: notification, entryID: UUID())!
        let later = ladder.begin(rule: rule("C", laddered), notification: notification, entryID: UUID())!
        ladder.acknowledge(ids: [first])
        XCTAssertEqual(silences, 0)
        ladder.acknowledge(ids: [later])
        XCTAssertEqual(silences, 1, "once it was the only one live")
        XCTAssertFalse(ladder.hasLiveEscalations)
        XCTAssertEqual(power, ["begin", "end"])
    }

    func testAcknowledgingEveryLiveOneByIdSilencesOnce() {
        let ladder = coordinator()
        let a = ladder.begin(rule: rule("A", laddered), notification: notification, entryID: UUID())!
        let b = ladder.begin(rule: rule("B", laddered), notification: notification, entryID: UUID())!
        clock.advance(by: 2)
        XCTAssertEqual(panels.last?.count, 2)
        ladder.acknowledge(ids: [a, b])
        XCTAssertEqual(silences, 1, "once for both, not once each")
        XCTAssertEqual(ladder.listedSummaries.count, 0)
        XCTAssertEqual(panels.last?.count, 0, "the panel is told they are gone")
    }

    func testTheIdsAreEndedNewestFirstAsAcknowledgeAllEndsThem() {
        // Eight, so that an order the set happens to hold could match newest
        // first by chance only once in some forty thousand runs.
        let ladder = coordinator()
        let entries = (0..<8).map { _ in UUID() }
        let ids = entries.enumerated().map { i, entry in
            ladder.begin(rule: rule("R\(i)", laddered), notification: notification, entryID: entry)!
        }
        let recorded = records.count
        ladder.acknowledge(ids: Set(ids))
        XCTAssertEqual(records.dropFirst(recorded).map(\.0), Array(entries.reversed()), "whatever order the set holds them in")
    }

    func testAnIdAlreadyAcknowledgedDoesNothingTheSecondTime() {
        // Held, not forgotten: acknowledged, and waiting on its Shortcut's report.
        let ladder = coordinator()
        let id = ladder.begin(rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 1), tier3: repeating(),
                                                    tier4: FinalAlert(afterSeconds: 10, action: .shortcut(name: "Page me")))),
                              notification: notification, entryID: UUID())!
        clock.advance(by: 10)
        ladder.acknowledge(id)
        XCTAssertEqual(ladder.trackedCount, 1, "still held, so the id is known and its status is acknowledged")
        let recorded = records.count
        let published = panels.count
        ladder.acknowledge(ids: [id])
        XCTAssertEqual(records.count, recorded)
        XCTAssertEqual(panels.count, published, "nothing changed, so nobody is told")
        XCTAssertEqual(silences, 1, "the one the first acknowledgement made, and no second")
    }

    func testAnUnknownIdAndAnEmptySetDoNothing() {
        let ladder = coordinator()
        ladder.begin(rule: rule("A", laddered), notification: notification, entryID: UUID())
        let recorded = records.count
        let published = panels.count
        ladder.acknowledge(ids: [UUID()])
        ladder.acknowledge(ids: [])
        XCTAssertEqual(records.count, recorded)
        XCTAssertEqual(panels.count, published)
        XCTAssertEqual(silences, 0)
        XCTAssertTrue(ladder.hasLiveEscalations, "the one that is listed is not touched")
    }

    func testAMissedEscalationByIdIsOnlyMarkedSeen() {
        let ladder = coordinator()
        let id = ladder.begin(rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification,
                              entryID: UUID())!
        clock.sleep(for: 400)
        ladder.checkForSleep()
        ladder.acknowledge(ids: [id])
        XCTAssertEqual(silences, 0, "it has no sound of its own to stop, as for acknowledge(_:)")
        XCTAssertEqual(ladder.listedSummaries.count, 0)
        guard case .missedWhileAsleep(_, let seen)? = last?.status else { return XCTFail("still a missed one") }
        XCTAssertNotNil(seen, "and marked seen")
    }

    func testAMissedEscalationAndALiveOneByIdSilenceOnceWhenNothingElseIsLive() {
        let ladder = coordinator()
        let missed = ladder.begin(rule: rule("Missed", Escalation(tier2: PanelAlert(delaySeconds: 1))),
                                  notification: notification, entryID: UUID())!
        clock.sleep(for: 400)
        ladder.checkForSleep()
        let live = ladder.begin(rule: rule("Live", laddered), notification: notification, entryID: UUID())!
        ladder.acknowledge(ids: [missed, live])
        XCTAssertEqual(silences, 1)
        XCTAssertEqual(ladder.listedSummaries.count, 0)
    }

    func testAMissedIdWhileAnotherIsLiveSilencesNothing() {
        let ladder = coordinator()
        let missed = ladder.begin(rule: rule("Missed", Escalation(tier2: PanelAlert(delaySeconds: 1))),
                                  notification: notification, entryID: UUID())!
        clock.sleep(for: 400)
        ladder.checkForSleep()
        ladder.begin(rule: rule("Live", laddered), notification: notification, entryID: UUID())
        ladder.acknowledge(ids: [missed])
        XCTAssertEqual(silences, 0)
        XCTAssertTrue(ladder.hasLiveEscalations)
    }

    func testAcknowledgeAllStillEndsWhatBeganAfterTheListing() {
        // The hotkey and the panel act on what the panel shows, which is not
        // held, so they keep ending everything listed now.
        let ladder = coordinator()
        let first = ladder.begin(rule: rule("A", laddered), notification: notification, entryID: UUID())!
        let listedWhenBuilt = Set(ladder.listedSummaries.map(\.0))
        XCTAssertEqual(listedWhenBuilt, [first])
        ladder.begin(rule: rule("C", laddered), notification: notification, entryID: UUID())
        ladder.acknowledgeAll()
        XCTAssertEqual(ladder.listedSummaries.count, 0)
        XCTAssertEqual(silences, 1)
    }

    // MARK: - Calling back in (review, 2026-09-30)

    func testAcknowledgingFromInsideARepeatsSoundSticks() {
        // A sound, a record or a Shortcut's report may call back in. The
        // change being made is written back first, so it is never undone.
        let ladder = coordinator()
        let id = ladder.begin(rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())!
        onSound = { ladder.acknowledge(id) }
        clock.advance(by: 300)
        XCTAssertEqual(sounds, ["Hero"])
        XCTAssertEqual(ladder.listedSummaries.count, 0)
        XCTAssertEqual(power, ["begin", "end"])
        XCTAssertEqual(clock.pendingCount, 0)
    }

    func testAcknowledgingFromInsideARepeatWhileAShortcutRunsSticks() {
        // Acknowledged but still held, waiting on its Shortcut's report: the
        // repeat must not arm another.
        let ladder = coordinator()
        let id = ladder.begin(rule: rule(Escalation(tier3: repeating(),
                                                    tier4: FinalAlert(afterSeconds: 10, action: .shortcut(name: "Page me")))),
                              notification: notification, entryID: UUID())!
        clock.advance(by: 10)
        onSound = { ladder.acknowledge(id) }
        clock.advance(by: 20)
        XCTAssertEqual(clock.pendingCount, 0, "no further repeat is armed, not even one that would fire into nothing")
        clock.advance(by: 300)
        XCTAssertEqual(sounds, ["Hero"])
        XCTAssertEqual(last?.status, .acknowledged(at: start + 30))
    }

    func testAcknowledgeAllFromInsideAFinalAlertSticks() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating(), tier4: FinalAlert(afterSeconds: 10, action: .alert(glass)))),
                     notification: notification, entryID: UUID())
        onSound = { ladder.acknowledgeAll() }
        clock.advance(by: 300)
        XCTAssertEqual(sounds, ["Glass"])
        XCTAssertFalse(ladder.hasLiveEscalations)
        XCTAssertEqual(power, ["begin", "end"])
    }

    func testAcknowledgingFromInsideARecordSticks() {
        let ladder = coordinator()
        let id = ladder.begin(rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())!
        onRecord = { summary in if summary.repeatCount == 1, summary.status == .live { ladder.acknowledge(id) } }
        clock.advance(by: 300)
        XCTAssertEqual(sounds, ["Hero"])
        XCTAssertEqual(ladder.listedSummaries.count, 0)
    }

    // MARK: - Sleep, further

    func testTwoSleepsEachUnderTheThresholdDoNotAddUp() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating(maxRepeats: nil, maxDuration: nil))),
                     notification: notification, entryID: UUID())
        clock.advance(by: 31)
        clock.sleep(for: 200)
        clock.advance(by: 30)
        clock.sleep(for: 200)
        clock.advance(by: 30)
        XCTAssertEqual(last?.status, .live)
        XCTAssertEqual(sounds.count, 3)
    }

    func testASleepOfExactlyTheThresholdResumes() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating(maxRepeats: nil, maxDuration: nil))),
                     notification: notification, entryID: UUID())
        clock.sleep(for: 300)
        clock.advance(by: 30)
        XCTAssertEqual(last?.status, .live)
    }

    func testTheThresholdIsFiveMinutesUnlessGivenAnother() {
        XCTAssertEqual(EscalationCoordinator.defaultStalenessThreshold, 300)
        let ladder = coordinator(threshold: 60)
        ladder.begin(rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        clock.sleep(for: 61)
        ladder.checkForSleep()
        XCTAssertEqual(last?.status, .missedWhileAsleep(convertedAt: clock.now(), acknowledgedAt: nil))
    }

    func testASleepEndsACappedEscalationToo() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating(maxRepeats: 1, maxDuration: nil),
                                           tier4: FinalAlert(afterSeconds: 100, action: .alert(glass)))),
                     notification: notification, entryID: UUID())
        clock.advance(by: 31)
        clock.sleep(for: 301)
        clock.advance(by: 70)
        XCTAssertEqual(sounds, ["Hero"], "no stale tier 4 on waking")
        // Converted when tier 4 fell due, 100 s awake plus the 301 s asleep.
        XCTAssertEqual(last?.status, .missedWhileAsleep(convertedAt: start + 401, acknowledgedAt: nil))
    }

    func testAnEscalationAlreadyMissedIsNotConvertedAgain() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification, entryID: UUID())
        clock.sleep(for: 400)
        ladder.checkForSleep()
        let first = clock.now()
        let recorded = records.count
        clock.sleep(for: 400)
        ladder.checkForSleep()
        XCTAssertEqual(records.count, recorded)
        XCTAssertEqual(ladder.listedSummaries.first?.1.status, .missedWhileAsleep(convertedAt: first, acknowledgedAt: nil))
    }

    func testAWakeCheckCancelsTheTimersAtOnceAndReleasesPower() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        clock.sleep(for: 301)
        ladder.checkForSleep()
        XCTAssertEqual(clock.pendingCount, 0)
        XCTAssertEqual(power, ["begin", "end"])
    }

    func testAMissedEscalationWhoseTier2NeverShowedIsListedButNotOnThePanel() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 60), tier3: repeating())),
                     notification: notification, entryID: UUID())
        clock.advance(by: 30)
        clock.sleep(for: 400)
        ladder.checkForSleep()
        XCTAssertEqual(ladder.listedSummaries.count, 1, "the menu still says it was missed")
        XCTAssertEqual(panels.last?.count, 0)
    }

    func testAShortcutReportingAfterASleepIsStillRecorded() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier4: FinalAlert(afterSeconds: 10, action: .shortcut(name: "Page me")))),
                     notification: notification, entryID: UUID())
        clock.advance(by: 10)
        clock.sleep(for: 400)
        ladder.checkForSleep()
        shortcutRuns[0].report(.shortcutLaunched(name: "Page me"))
        XCTAssertEqual(last?.final, .shortcutLaunched(name: "Page me"))
        XCTAssertEqual(last?.status, .missedWhileAsleep(convertedAt: clock.now(), acknowledgedAt: nil))
    }

    // MARK: - Acknowledging, further

    func testAcknowledgeAllHidesThePanelAndReleasesPower() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 1), tier3: repeating())),
                     notification: notification, entryID: UUID())
        clock.advance(by: 1)
        XCTAssertEqual(panels.last?.count, 1)
        ladder.acknowledgeAll()
        XCTAssertEqual(panels.last?.count, 0)
        XCTAssertEqual(power, ["begin", "end"])
    }

    func testAcknowledgingTheLastLiveEscalationSilencesEvenWithAMissedOneListed() {
        let ladder = coordinator()
        ladder.begin(rule: rule("Missed", Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification, entryID: UUID())
        clock.sleep(for: 400)
        ladder.checkForSleep()
        let live = ladder.begin(rule: rule("Live", Escalation(tier3: repeating())), notification: notification, entryID: UUID())!
        ladder.acknowledge(live)
        XCTAssertEqual(silences, 1)
        XCTAssertEqual(ladder.listedSummaries.map(\.1.ruleName), ["Missed"])
    }

    func testAnAcknowledgedEscalationWaitingOnAShortcutLeavesThePanel() {
        let ladder = coordinator()
        let id = ladder.begin(rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 1),
                                                    tier4: FinalAlert(afterSeconds: 2, action: .shortcut(name: "Page me")))),
                              notification: notification, entryID: UUID())!
        clock.advance(by: 2)
        ladder.acknowledge(id)
        XCTAssertEqual(panels.last?.count, 0)
        clock.sleep(for: 400)
        ladder.checkForSleep()
        XCTAssertEqual(last?.status, .acknowledged(at: start + 2), "a sleep does not bring it back")
    }

    // MARK: - What each tier is given, and what the summary says

    func testLaterTiersSpeakTheNotificationThatStartedThem() {
        let ladder = coordinator()
        let line = SpeechAction(voiceIdentifier: "com.example.voice", template: "{title}")
        ladder.begin(rule: rule(Escalation(tier3: RepeatAlert(action: .speak(line), maxRepeats: 1),
                                           tier4: FinalAlert(afterSeconds: 60, action: .alert(.soundAndSpeak(soundName: "Glass", soundGainDB: 0, speech: line))))),
                     notification: notification, entryID: UUID())
        clock.advance(by: 60)
        XCTAssertEqual(spoken, ["Alex Example mentioned you", "Alex Example mentioned you"])
        XCTAssertEqual(sounds, ["speech:com.example.voice", "Glass+speech"])
        XCTAssertEqual(last?.lastRepeat, .spoke(text: "Alex Example mentioned you", voice: "com.example.voice", gainDB: 0, outputSilent: false))
        XCTAssertEqual(last?.final, .alerted(.played(sound: "Glass", gainDB: 0, outputSilent: false)))
    }

    func testTheShortcutIsGivenTheNotificationThatStartedIt() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier4: FinalAlert(afterSeconds: 10, action: .shortcut(name: "Page me")))),
                     notification: notification, entryID: UUID())
        clock.advance(by: 10)
        XCTAssertEqual(shortcutNotifications, [notification])
    }

    func testARunningShortcutHasReachedTier4AndHoldsNoPower() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier4: FinalAlert(afterSeconds: 10, action: .shortcut(name: "Page me")))),
                     notification: notification, entryID: UUID())
        clock.advance(by: 10)
        XCTAssertEqual(last?.tierReached, 4)
        XCTAssertNil(last?.final, "not yet reported")
        XCTAssertEqual(power, ["begin", "end"], "nothing is left to fire; the Shortcut is not waited on")
    }

    func testTheSummaryCarriesTheStartAndTheCap() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating(maxRepeats: 7))), notification: notification, entryID: UUID())
        XCTAssertEqual(last?.startedAt, start)
        XCTAssertEqual(last?.repeatCap, 7)
        XCTAssertEqual(last?.ruleName, "On-call mentions")
    }

    func testTierReachedNeverGoesBackDown() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 45), tier3: repeating())),
                     notification: notification, entryID: UUID())
        clock.advance(by: 30)
        XCTAssertEqual(last?.tierReached, 3)
        clock.advance(by: 15)
        XCTAssertEqual(last?.tierReached, 3, "the panel showing after a repeat is not a step back")
    }

    func testTheSummaryHoldsTheLatestRepeatsOutcome() {
        var calls = 0
        soundOutcome = { name in calls += 1
            return calls == 1 ? .failed("sound \"\(name)\" was not found") : .played(sound: name, gainDB: 0, outputSilent: false) }
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        clock.advance(by: 30)
        XCTAssertEqual(last?.lastRepeat, .failed("sound \"Hero\" was not found"))
        clock.advance(by: 30)
        XCTAssertEqual(last?.lastRepeat, .played(sound: "Hero", gainDB: 0, outputSilent: false))
    }

    func testThePanelListsNewestFirst() {
        let ladder = coordinator()
        ladder.begin(rule: rule("Older", Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification, entryID: UUID())
        clock.advance(by: 1)
        ladder.begin(rule: rule("Newer", Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification, entryID: UUID())
        clock.advance(by: 1)
        XCTAssertEqual(panels.last?.map(\.1.ruleName), ["Newer", "Older"])
    }

    func testEscalationsThatEndedAreForgottenOnceNothingCanReportToThem() {
        // A notification's copy is kept only as long as its escalation needs it.
        let ladder = coordinator()
        let plainRow = UUID(), pagingRow = UUID()
        let plain = ladder.begin(rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: plainRow)!
        let paging = ladder.begin(rule: rule(Escalation(tier4: FinalAlert(afterSeconds: 1, action: .shortcut(name: "Page me")))),
                                  notification: notification, entryID: pagingRow)!
        clock.advance(by: 1)
        ladder.acknowledge(plain)
        ladder.acknowledge(paging)
        XCTAssertEqual(ladder.trackedCount, 1, "the one still waiting on its Shortcut")
        XCTAssertEqual(retirements, [plainRow])
        shortcutRuns[0].report(.shortcutLaunched(name: "Page me"))
        XCTAssertEqual(ladder.trackedCount, 0)
        XCTAssertEqual(retirements, [plainRow, pagingRow], "each row once, after its last record")
        XCTAssertEqual(records.last?.0, pagingRow)
    }

    func testNothingIsRecordedForARowAfterItIsRetired() {
        // The pipeline forgets what it folded from a row when told it is
        // retired; a record after that would fold an old failure again.
        let ladder = coordinator()
        let acknowledged = UUID(), late = UUID(), missed = UUID()
        let plain = ladder.begin(rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: acknowledged)!
        let paging = ladder.begin(rule: rule(Escalation(tier4: FinalAlert(afterSeconds: 1, action: .shortcut(name: "Page me")))),
                                  notification: notification, entryID: late)!
        clock.advance(by: 1)
        ladder.acknowledge(plain)
        ladder.acknowledge(paging)
        shortcutRuns[0].report(.shortcutFailed(name: "Page me", reason: "x"))
        let asleep = ladder.begin(rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: missed)!
        clock.sleep(for: 3600)
        ladder.checkForSleep()
        ladder.acknowledge(asleep)

        for row in [acknowledged, late, missed] {
            let mine = events.filter { $0.row == row }.map(\.kind)
            XCTAssertEqual(mine.last, "retired", "\(mine)")
            XCTAssertEqual(mine.filter { $0 == "retired" }.count, 1)
            XCTAssertEqual(mine.dropLast().last, "record", "its last record comes just before")
        }
    }

    func testAMissedEscalationIsRetiredOnlyOnceSeen() {
        let ladder = coordinator()
        let row = UUID()
        let id = ladder.begin(rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: row)!
        clock.sleep(for: 3600)
        ladder.checkForSleep()
        XCTAssertEqual(retirements, [], "still listed until seen")
        ladder.acknowledge(id)
        XCTAssertEqual(retirements, [row])
    }
}
