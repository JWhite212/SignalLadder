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

    /// Every ladder in this file is begun through here, so that what tier 1 is
    /// taken to have done is passed from one line, and a task that gives these
    /// tests more to say about it edits that line and not each call (M5 plan,
    /// Task 5). The default is the coordinator's own "not proof that anything
    /// was heard", which is all that a test that makes no claim about tier 1
    /// should say. The coordinator's `begin` has no default.
    @discardableResult
    private func begin(_ ladder: EscalationCoordinator, rule: Rule, notification: CapturedNotification,
                       entryID: UUID, tier1Outcome: AlertOutcome? = nil) -> EscalationID? {
        ladder.begin(rule: rule, notification: notification, entryID: entryID, tier1Outcome: tier1Outcome)
    }

    private func repeating(every interval: TimeInterval = 30, maxRepeats: Int? = 20,
                           maxDuration: TimeInterval? = 600) -> RepeatAlert {
        RepeatAlert(action: hero, intervalSeconds: interval, maxRepeats: maxRepeats, maxDurationSeconds: maxDuration)
    }

    private var last: EscalationSummary? { records.last?.1 }
    private var start: Date { Date(timeIntervalSince1970: 1_790_000_000) }

    // MARK: - Tier 3: repeating, and its caps

    func testARepeatFiresEveryIntervalAndStopsAtMaxRepeats() {
        let ladder = coordinator()
        begin(ladder, rule: rule(Escalation(tier3: repeating(maxRepeats: 3, maxDuration: nil))),
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
        begin(ladder, rule: rule(Escalation(tier3: repeating(maxRepeats: 20, maxDuration: 100))),
                      notification: notification, entryID: UUID())
        clock.advance(by: 1000)
        XCTAssertEqual(sounds.count, 3, "at 30, 60 and 90; 120 is past the limit")
        XCTAssertEqual(last?.status, .capped(at: start + 90))
    }

    func testTheDefaultCapsAllowTwentyRepeatsInTenMinutes() {
        let ladder = coordinator()
        begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
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
        begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        clock.advance(by: 3600)
        XCTAssertEqual(sounds.count, 20)
        XCTAssertEqual(last?.repeatCount, 20)
    }

    func testALimitEqualToOneIntervalAllowsThatOneRepeat() {
        let ladder = coordinator()
        begin(ladder, rule: rule(Escalation(tier3: repeating(every: 30, maxRepeats: nil, maxDuration: 30))),
                      notification: notification, entryID: UUID())
        clock.advance(by: 300)
        XCTAssertEqual(sounds.count, 1)
        XCTAssertEqual(last?.status, .capped(at: start + 30))
    }

    func testALimitShorterThanOneIntervalIsCappedAtOnce() {
        let ladder = coordinator()
        begin(ladder, rule: rule(Escalation(tier3: repeating(every: 30, maxRepeats: nil, maxDuration: 10))),
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
            begin(ladder, rule: rule(Escalation(tier3: tier3)), notification: notification, entryID: UUID())
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
        begin(ladder, rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 10), tier3: repeating(),
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
        XCTAssertNil(begin(ladder, rule: plain, notification: notification, entryID: UUID()))
        XCTAssertEqual(clock.pendingCount, 0)
        XCTAssertEqual(records.count, 0)
    }

    // MARK: - Sleep

    func testAnHourAwakeConvertsNothing() {
        // The test that would have caught Ruling 14's first version, which
        // ended every escalation at five minutes, asleep or not.
        let ladder = coordinator()
        let uncapped = UUID()
        begin(ladder, rule: rule("Uncapped", Escalation(tier3: repeating(maxRepeats: nil, maxDuration: nil))),
                      notification: notification, entryID: uncapped)
        let capped = UUID()
        begin(ladder, rule: rule("Capped", Escalation(tier3: repeating(maxRepeats: 1, maxDuration: nil))),
                      notification: notification, entryID: capped)
        clock.advance(by: 3600)
        XCTAssertEqual(records.last { $0.0 == uncapped }?.1.repeatCount, 120)
        XCTAssertEqual(records.last { $0.0 == uncapped }?.1.status, .live)
        XCTAssertEqual(records.last { $0.0 == capped }?.1.status, .capped(at: start + 30))
    }

    func testALongSleepEndsEverythingStillGoingWhenTheNextTierFallsDue() {
        let ladder = coordinator()
        let row = UUID()
        begin(ladder, rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 10),
                                            tier3: repeating(maxRepeats: nil, maxDuration: nil))),
                      notification: notification, entryID: row)
        let done = UUID()
        let acknowledged = begin(ladder, rule: rule("Already seen", Escalation(tier3: repeating())),
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
        begin(ladder, rule: rule(Escalation(tier3: repeating(maxRepeats: nil, maxDuration: nil))),
                      notification: notification, entryID: UUID())
        clock.advance(by: 31)
        clock.sleep(for: 299)
        clock.advance(by: 30)
        XCTAssertEqual(sounds.count, 2)
        XCTAssertEqual(last?.status, .live)
    }

    func testTheWakeCheckConvertsAtOnceEvenWithNothingLeftToFire() {
        let ladder = coordinator()
        begin(ladder, rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 10))), notification: notification, entryID: UUID())
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
        begin(ladder, rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification, entryID: UUID())
        clock.advance(by: 900)
        ladder.checkForSleep()
        XCTAssertEqual(last?.status, .live)
    }

    func testAnEscalationStartedAfterASleepIsMeasuredFromItsStart() {
        // The sleep belongs to what was running before it, not to what began
        // afterwards, even when the wake notification never came.
        let ladder = coordinator()
        let before = UUID()
        begin(ladder, rule: rule("Before", Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification, entryID: before)
        clock.advance(by: 1)
        clock.sleep(for: 400)
        let after = UUID()
        begin(ladder, rule: rule("After", Escalation(tier3: repeating())), notification: notification, entryID: after)
        XCTAssertEqual(records.last { $0.0 == before }?.1.status, .missedWhileAsleep(convertedAt: clock.now(), acknowledgedAt: nil))
        clock.advance(by: 30)
        XCTAssertEqual(records.last { $0.0 == after }?.1.status, .live)
        XCTAssertEqual(sounds.count, 1)
    }

    // MARK: - Concurrent escalations

    func testTwoEscalationsRunApartAndAcknowledgeAllEndsBoth() {
        let ladder = coordinator()
        let first = begin(ladder, rule: rule("First", Escalation(tier3: repeating())), notification: notification, entryID: UUID())!
        let second = begin(ladder, rule: rule("Second", Escalation(tier3: repeating())), notification: notification, entryID: UUID())!
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
        begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
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
        begin(ladder, rule: rule("A", Escalation(tier3: repeating(maxRepeats: 2, maxDuration: nil),
                                                 tier4: FinalAlert(afterSeconds: 70, action: .alert(glass)))),
                      notification: notification, entryID: UUID())
        clock.advance(by: 5)
        begin(ladder, rule: rule("B", Escalation(tier2: PanelAlert(delaySeconds: 10))), notification: notification, entryID: UUID())
        XCTAssertEqual(power, ["begin"], "claimed once for both")
        clock.advance(by: 64)
        XCTAssertEqual(power, ["begin"], "A's tier 4 is still to fire")
        clock.advance(by: 1)
        XCTAssertEqual(power, ["begin", "end"])
        XCTAssertEqual(ladder.listedSummaries.first { $0.1.ruleName == "A" }?.1.status, .capped(at: start + 60),
                       "still capped and listed, but holding nothing")
        XCTAssertFalse(ladder.hasPendingTiers)

        begin(ladder, rule: rule("C", Escalation(tier2: PanelAlert())), notification: notification, entryID: UUID())
        XCTAssertEqual(power, ["begin", "end", "begin"])
    }

    func testAcknowledgingReleasesThePowerAssertion() {
        let ladder = coordinator()
        let id = begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())!
        ladder.acknowledge(id)
        XCTAssertEqual(power, ["begin", "end"])
        XCTAssertEqual(clock.pendingCount, 0, "its timers are cancelled, not left to fire into nothing")
    }

    // MARK: - The panel

    func testThePanelListsOnlyEscalationsWhoseTier2HasShown() {
        let ladder = coordinator()
        begin(ladder, rule: rule("Panel", Escalation(tier2: PanelAlert(delaySeconds: 10), tier3: repeating())),
                      notification: notification, entryID: UUID())
        begin(ladder, rule: rule("No panel", Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        clock.advance(by: 9)
        XCTAssertTrue(panels.allSatisfy(\.isEmpty), "nothing before tier 2 has shown")
        clock.advance(by: 1)
        XCTAssertEqual(panels.last?.map(\.1.ruleName), ["Panel"], "and never one with no tier 2")
        XCTAssertEqual(ladder.listedSummaries.map(\.1.ruleName), ["No panel", "Panel"], "the menu lists both, newest first")
    }

    func testAMissedEscalationStaysOnThePanelUntilAcknowledgedAndStaysMissed() {
        let ladder = coordinator()
        let id = begin(ladder, rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 10), tier3: repeating())),
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
            begin(ladder, rule: rule(name, Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification, entryID: UUID())
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
        let id = begin(ladder, rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 10), tier3: repeating(),
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
        begin(ladder, rule: rule(Escalation(tier3: repeating(maxRepeats: nil, maxDuration: nil),
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
        begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        clock.sleep(for: 400)
        ladder.checkForSleep()
        XCTAssertEqual(clock.runCancelled(), 1)
        XCTAssertEqual(sounds, [])
    }

    // MARK: - What is recorded

    func testEveryChangeIsRecordedOnTheRowItBeganFrom() {
        let ladder = coordinator()
        let row = UUID()
        let id = begin(ladder, rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 10),
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
        begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        clock.advance(by: 30)
        XCTAssertEqual(last?.lastRepeat, .failed("sound \"Hero\" was not found"))
    }

    func testAFailedShortcutIsRecorded() {
        shortcutsReportAtOnce = .shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed")
        let ladder = coordinator()
        begin(ladder, rule: rule(Escalation(tier4: FinalAlert(afterSeconds: 60, action: .shortcut(name: "Page me")))),
                      notification: notification, entryID: UUID())
        clock.advance(by: 60)
        XCTAssertEqual(last?.final, .shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed"))
        XCTAssertEqual(last?.tierReached, 4)
    }

    func testAShortcutThatReportsLateHoldsNothingUpAndIsStillRecorded() {
        let ladder = coordinator()
        let id = begin(ladder, rule: rule(Escalation(tier3: repeating(maxRepeats: nil, maxDuration: nil),
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
        let id = begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())!
        ladder.acknowledge(id)
        XCTAssertEqual(silences, 1)
    }

    func testAcknowledgeAllWithOneLiveEscalationSilencesOnce() {
        let ladder = coordinator()
        begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        ladder.acknowledgeAll()
        XCTAssertEqual(silences, 1)
    }

    func testAcknowledgeAllWithTwoLiveEscalationsSilencesOnce() {
        let ladder = coordinator()
        begin(ladder, rule: rule("A", Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        begin(ladder, rule: rule("B", Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        ladder.acknowledgeAll()
        XCTAssertEqual(silences, 1)
    }

    func testAcknowledgingOneOfTwoNeverSilences() {
        // The player cannot tell whose sound is playing (ruling 8).
        let ladder = coordinator()
        let first = begin(ladder, rule: rule("A", Escalation(tier3: repeating())), notification: notification, entryID: UUID())!
        begin(ladder, rule: rule("B", Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        ladder.acknowledge(first)
        XCTAssertEqual(silences, 0)
        XCTAssertTrue(ladder.hasLiveEscalations)
    }

    func testAcknowledgingAMissedEscalationNeverSilences() {
        let ladder = coordinator()
        let id = begin(ladder, rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification, entryID: UUID())!
        clock.sleep(for: 400)
        ladder.checkForSleep()
        ladder.acknowledge(id)
        XCTAssertEqual(silences, 0, "it has no sound of its own to stop")
    }

    func testAcknowledgeAllWithOnlyMissedEscalationsSilencesOnce() {
        let ladder = coordinator()
        begin(ladder, rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification, entryID: UUID())
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
        let id = begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())!
        ladder.acknowledge(id)
        let recorded = records.count
        ladder.acknowledge(id)
        XCTAssertEqual(records.count, recorded)
        XCTAssertEqual(silences, 1)
    }

    // MARK: - Acknowledging what a menu listed (M5 plan, Ruling 22)

    private var laddered: Escalation { Escalation(tier2: PanelAlert(delaySeconds: 1), tier3: repeating()) }

    /// What a menu carries when it lists exactly these escalations as they stand
    /// now, each with the count of matches it stands for at this moment, so that
    /// a test of which escalations are ended is not also a test of the counts
    /// (`EscalationJoinTests` is, for those). One that is not listed now, being
    /// acknowledged already or not known, is given 1, which is what an
    /// escalation that no match has joined stands for.
    private func listing(_ ladder: EscalationCoordinator, _ ids: [EscalationID]) -> [ListedEscalation] {
        ids.map { id in
            ListedEscalation(id: id, matchCount: ladder.listedSummaries.first { $0.0 == id }?.1.matchCount ?? 1)
        }
    }

    func testAcknowledgingWhatWasListedLeavesAnEscalationBegunAfterwardsLive() {
        // Capture runs while the status menu is open, so an escalation can
        // begin in the seconds it is held. Its item still reads Acknowledge All
        // for the set it listed, and a click must not end one never shown.
        let ladder = coordinator()
        begin(ladder, rule: rule("A", laddered), notification: notification, entryID: UUID())
        begin(ladder, rule: rule("B", laddered), notification: notification, entryID: UUID())
        clock.advance(by: 2)
        let listedWhenBuilt = ladder.listedSummaries.map(ListedEscalation.init(row:))
        XCTAssertEqual(listedWhenBuilt.count, 2)

        let later = begin(ladder, rule: rule("C", laddered), notification: notification, entryID: UUID())!
        ladder.acknowledge(listed: listedWhenBuilt)

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

    func testAcknowledgingTheOneThatBeganLaterAsListedThenSilences() {
        let ladder = coordinator()
        let first = begin(ladder, rule: rule("A", laddered), notification: notification, entryID: UUID())!
        let later = begin(ladder, rule: rule("C", laddered), notification: notification, entryID: UUID())!
        ladder.acknowledge(listed: listing(ladder, [first]))
        XCTAssertEqual(silences, 0)
        ladder.acknowledge(listed: listing(ladder, [later]))
        XCTAssertEqual(silences, 1, "once it was the only one live")
        XCTAssertFalse(ladder.hasLiveEscalations)
        XCTAssertEqual(power, ["begin", "end"])
    }

    func testAcknowledgingEveryLiveOneAsListedSilencesOnce() {
        let ladder = coordinator()
        let a = begin(ladder, rule: rule("A", laddered), notification: notification, entryID: UUID())!
        let b = begin(ladder, rule: rule("B", laddered), notification: notification, entryID: UUID())!
        clock.advance(by: 2)
        XCTAssertEqual(panels.last?.count, 2)
        ladder.acknowledge(listed: listing(ladder, [a, b]))
        XCTAssertEqual(silences, 1, "once for both, not once each")
        XCTAssertEqual(ladder.listedSummaries.count, 0)
        XCTAssertEqual(panels.last?.count, 0, "the panel is told they are gone")
    }

    func testWhatWasListedIsEndedNewestFirstAsAcknowledgeAllEndsThem() {
        // Eight, and handed over in an order that is neither oldest nor newest
        // first, so that ending them newest first is the coordinator's own
        // choice and not the order the menu listed them in.
        let ladder = coordinator()
        let entries = (0..<8).map { _ in UUID() }
        let ids = entries.enumerated().map { i, entry in
            begin(ladder, rule: rule("R\(i)", laddered), notification: notification, entryID: entry)!
        }
        let recorded = records.count
        ladder.acknowledge(listed: listing(ladder, [3, 0, 7, 5, 1, 6, 2, 4].map { ids[$0] }))
        XCTAssertEqual(records.dropFirst(recorded).map(\.0), Array(entries.reversed()), "whatever order they were listed in")
    }

    func testAnEscalationAlreadyAcknowledgedDoesNothingTheSecondTimeItIsListed() {
        // Held, not forgotten: acknowledged, and waiting on its Shortcut's report.
        let ladder = coordinator()
        let id = begin(ladder, rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 1), tier3: repeating(),
                                                     tier4: FinalAlert(afterSeconds: 10, action: .shortcut(name: "Page me")))),
                               notification: notification, entryID: UUID())!
        clock.advance(by: 10)
        ladder.acknowledge(id)
        XCTAssertEqual(ladder.trackedCount, 1, "still held, so the id is known and its status is acknowledged")
        let recorded = records.count
        let published = panels.count
        ladder.acknowledge(listed: listing(ladder, [id]))
        XCTAssertEqual(records.count, recorded)
        XCTAssertEqual(panels.count, published, "nothing changed, so nobody is told")
        XCTAssertEqual(silences, 1, "the one the first acknowledgement made, and no second")
    }

    func testAnUnknownEscalationAndAnEmptyListingDoNothing() {
        let ladder = coordinator()
        begin(ladder, rule: rule("A", laddered), notification: notification, entryID: UUID())
        let recorded = records.count
        let published = panels.count
        ladder.acknowledge(listed: listing(ladder, [UUID()]))
        ladder.acknowledge(listed: [])
        XCTAssertEqual(records.count, recorded)
        XCTAssertEqual(panels.count, published)
        XCTAssertEqual(silences, 0)
        XCTAssertTrue(ladder.hasLiveEscalations, "the one that is listed is not touched")
    }

    func testAMissedEscalationAsListedIsOnlyMarkedSeen() {
        let ladder = coordinator()
        let id = begin(ladder, rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification,
                               entryID: UUID())!
        clock.sleep(for: 400)
        ladder.checkForSleep()
        ladder.acknowledge(listed: listing(ladder, [id]))
        XCTAssertEqual(silences, 0, "it has no sound of its own to stop, as for acknowledge(_:)")
        XCTAssertEqual(ladder.listedSummaries.count, 0)
        guard case .missedWhileAsleep(_, let seen)? = last?.status else { return XCTFail("still a missed one") }
        XCTAssertNotNil(seen, "and marked seen")
    }

    func testAMissedEscalationAndALiveOneAsListedSilenceOnceWhenNothingElseIsLive() {
        let ladder = coordinator()
        let missed = begin(ladder, rule: rule("Missed", Escalation(tier2: PanelAlert(delaySeconds: 1))),
                                   notification: notification, entryID: UUID())!
        clock.sleep(for: 400)
        ladder.checkForSleep()
        let live = begin(ladder, rule: rule("Live", laddered), notification: notification, entryID: UUID())!
        ladder.acknowledge(listed: listing(ladder, [missed, live]))
        XCTAssertEqual(silences, 1)
        XCTAssertEqual(ladder.listedSummaries.count, 0)
    }

    func testAMissedEscalationAsListedWhileAnotherIsLiveSilencesNothing() {
        let ladder = coordinator()
        let missed = begin(ladder, rule: rule("Missed", Escalation(tier2: PanelAlert(delaySeconds: 1))),
                                   notification: notification, entryID: UUID())!
        clock.sleep(for: 400)
        ladder.checkForSleep()
        begin(ladder, rule: rule("Live", laddered), notification: notification, entryID: UUID())
        ladder.acknowledge(listed: listing(ladder, [missed]))
        XCTAssertEqual(silences, 0)
        XCTAssertTrue(ladder.hasLiveEscalations)
    }

    func testAcknowledgeAllStillEndsWhatBeganAfterTheListing() {
        // The hotkey and the panel act on what the panel shows, which is not
        // held, so they keep ending everything listed now.
        let ladder = coordinator()
        let first = begin(ladder, rule: rule("A", laddered), notification: notification, entryID: UUID())!
        let listedWhenBuilt = Set(ladder.listedSummaries.map(\.0))
        XCTAssertEqual(listedWhenBuilt, [first])
        begin(ladder, rule: rule("C", laddered), notification: notification, entryID: UUID())
        ladder.acknowledgeAll()
        XCTAssertEqual(ladder.listedSummaries.count, 0)
        XCTAssertEqual(silences, 1)
    }

    // MARK: - Calling back in (review, 2026-09-30)

    func testAcknowledgingFromInsideARepeatsSoundSticks() {
        // A sound, a record or a Shortcut's report may call back in. The
        // change being made is written back first, so it is never undone.
        let ladder = coordinator()
        let id = begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())!
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
        let id = begin(ladder, rule: rule(Escalation(tier3: repeating(),
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
        begin(ladder, rule: rule(Escalation(tier3: repeating(), tier4: FinalAlert(afterSeconds: 10, action: .alert(glass)))),
                      notification: notification, entryID: UUID())
        onSound = { ladder.acknowledgeAll() }
        clock.advance(by: 300)
        XCTAssertEqual(sounds, ["Glass"])
        XCTAssertFalse(ladder.hasLiveEscalations)
        XCTAssertEqual(power, ["begin", "end"])
    }

    func testAcknowledgingFromInsideARecordSticks() {
        let ladder = coordinator()
        let id = begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())!
        onRecord = { summary in if summary.repeatCount == 1, summary.status == .live { ladder.acknowledge(id) } }
        clock.advance(by: 300)
        XCTAssertEqual(sounds, ["Hero"])
        XCTAssertEqual(ladder.listedSummaries.count, 0)
    }

    // MARK: - Sleep, further

    func testTwoSleepsEachUnderTheThresholdDoNotAddUp() {
        let ladder = coordinator()
        begin(ladder, rule: rule(Escalation(tier3: repeating(maxRepeats: nil, maxDuration: nil))),
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
        begin(ladder, rule: rule(Escalation(tier3: repeating(maxRepeats: nil, maxDuration: nil))),
                      notification: notification, entryID: UUID())
        clock.sleep(for: 300)
        clock.advance(by: 30)
        XCTAssertEqual(last?.status, .live)
    }

    func testTheThresholdIsFiveMinutesUnlessGivenAnother() {
        XCTAssertEqual(EscalationCoordinator.defaultStalenessThreshold, 300)
        let ladder = coordinator(threshold: 60)
        begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        clock.sleep(for: 61)
        ladder.checkForSleep()
        XCTAssertEqual(last?.status, .missedWhileAsleep(convertedAt: clock.now(), acknowledgedAt: nil))
    }

    func testASleepEndsACappedEscalationToo() {
        let ladder = coordinator()
        begin(ladder, rule: rule(Escalation(tier3: repeating(maxRepeats: 1, maxDuration: nil),
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
        begin(ladder, rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification, entryID: UUID())
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
        begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        clock.sleep(for: 301)
        ladder.checkForSleep()
        XCTAssertEqual(clock.pendingCount, 0)
        XCTAssertEqual(power, ["begin", "end"])
    }

    func testAMissedEscalationWhoseTier2NeverShowedIsListedButNotOnThePanel() {
        let ladder = coordinator()
        begin(ladder, rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 60), tier3: repeating())),
                      notification: notification, entryID: UUID())
        clock.advance(by: 30)
        clock.sleep(for: 400)
        ladder.checkForSleep()
        XCTAssertEqual(ladder.listedSummaries.count, 1, "the menu still says it was missed")
        XCTAssertEqual(panels.last?.count, 0)
    }

    func testAShortcutReportingAfterASleepIsStillRecorded() {
        let ladder = coordinator()
        begin(ladder, rule: rule(Escalation(tier4: FinalAlert(afterSeconds: 10, action: .shortcut(name: "Page me")))),
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
        begin(ladder, rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 1), tier3: repeating())),
                      notification: notification, entryID: UUID())
        clock.advance(by: 1)
        XCTAssertEqual(panels.last?.count, 1)
        ladder.acknowledgeAll()
        XCTAssertEqual(panels.last?.count, 0)
        XCTAssertEqual(power, ["begin", "end"])
    }

    func testAcknowledgingTheLastLiveEscalationSilencesEvenWithAMissedOneListed() {
        let ladder = coordinator()
        begin(ladder, rule: rule("Missed", Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification, entryID: UUID())
        clock.sleep(for: 400)
        ladder.checkForSleep()
        let live = begin(ladder, rule: rule("Live", Escalation(tier3: repeating())), notification: notification, entryID: UUID())!
        ladder.acknowledge(live)
        XCTAssertEqual(silences, 1)
        XCTAssertEqual(ladder.listedSummaries.map(\.1.ruleName), ["Missed"])
    }

    func testAnAcknowledgedEscalationWaitingOnAShortcutLeavesThePanel() {
        let ladder = coordinator()
        let id = begin(ladder, rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 1),
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
        begin(ladder, rule: rule(Escalation(tier3: RepeatAlert(action: .speak(line), maxRepeats: 1),
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
        begin(ladder, rule: rule(Escalation(tier4: FinalAlert(afterSeconds: 10, action: .shortcut(name: "Page me")))),
                      notification: notification, entryID: UUID())
        clock.advance(by: 10)
        XCTAssertEqual(shortcutNotifications, [notification])
    }

    func testARunningShortcutHasReachedTier4AndHoldsNoPower() {
        let ladder = coordinator()
        begin(ladder, rule: rule(Escalation(tier4: FinalAlert(afterSeconds: 10, action: .shortcut(name: "Page me")))),
                      notification: notification, entryID: UUID())
        clock.advance(by: 10)
        XCTAssertEqual(last?.tierReached, 4)
        XCTAssertNil(last?.final, "not yet reported")
        XCTAssertEqual(power, ["begin", "end"], "nothing is left to fire; the Shortcut is not waited on")
    }

    func testTheSummaryCarriesTheStartAndTheCap() {
        let ladder = coordinator()
        begin(ladder, rule: rule(Escalation(tier3: repeating(maxRepeats: 7))), notification: notification, entryID: UUID())
        XCTAssertEqual(last?.startedAt, start)
        XCTAssertEqual(last?.repeatCap, 7)
        XCTAssertEqual(last?.ruleName, "On-call mentions")
    }

    func testTierReachedNeverGoesBackDown() {
        let ladder = coordinator()
        begin(ladder, rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 45), tier3: repeating())),
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
        begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        clock.advance(by: 30)
        XCTAssertEqual(last?.lastRepeat, .failed("sound \"Hero\" was not found"))
        clock.advance(by: 30)
        XCTAssertEqual(last?.lastRepeat, .played(sound: "Hero", gainDB: 0, outputSilent: false))
    }

    func testThePanelListsNewestFirst() {
        let ladder = coordinator()
        begin(ladder, rule: rule("Older", Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification, entryID: UUID())
        clock.advance(by: 1)
        begin(ladder, rule: rule("Newer", Escalation(tier2: PanelAlert(delaySeconds: 1))), notification: notification, entryID: UUID())
        clock.advance(by: 1)
        XCTAssertEqual(panels.last?.map(\.1.ruleName), ["Newer", "Older"])
    }

    func testEscalationsThatEndedAreForgottenOnceNothingCanReportToThem() {
        // A notification's copy is kept only as long as its escalation needs it.
        let ladder = coordinator()
        let plainRow = UUID(), pagingRow = UUID()
        let plain = begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: plainRow)!
        let paging = begin(ladder, rule: rule(Escalation(tier4: FinalAlert(afterSeconds: 1, action: .shortcut(name: "Page me")))),
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
        let plain = begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: acknowledged)!
        let paging = begin(ladder, rule: rule(Escalation(tier4: FinalAlert(afterSeconds: 1, action: .shortcut(name: "Page me")))),
                                   notification: notification, entryID: late)!
        clock.advance(by: 1)
        ladder.acknowledge(plain)
        ladder.acknowledge(paging)
        shortcutRuns[0].report(.shortcutFailed(name: "Page me", reason: "x"))
        let asleep = begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: missed)!
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
        let id = begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: row)!
        clock.sleep(for: 3600)
        ladder.checkForSleep()
        XCTAssertEqual(retirements, [], "still listed until seen")
        ladder.acknowledge(id)
        XCTAssertEqual(retirements, [row])
    }

    // MARK: - What a ladder keeps for a match that joins it (M5 plan, Task 5)

    private let heard = AlertOutcome.played(sound: "Glass", gainDB: 0, outputSilent: false)

    /// What is kept of an escalation that must still be held. Unwrapped, so that
    /// a field that reads nil because the escalation is gone cannot pass for one
    /// that reads nil because nothing is set.
    private func kept(_ ladder: EscalationCoordinator, _ id: EscalationID?) throws -> EscalationCoordinator.Bookkeeping {
        try XCTUnwrap(ladder.bookkeeping(of: try XCTUnwrap(id)), "the escalation is no longer held")
    }

    func testBeginKeepsWhatTier1DidTheRulesIdAndTheTimeOfTheMatch() throws {
        clock.advance(by: 125)  // so neither clock, nor the test's start, is zero
        let ladder = coordinator()
        let theRule = rule(Escalation(tier3: repeating()))
        let id = begin(ladder, rule: theRule, notification: notification, entryID: UUID(), tier1Outcome: heard)
        let record = try kept(ladder, id)
        XCTAssertEqual(record.tier1Outcome, heard)
        XCTAssertEqual(record.ruleID, theRule.id)
        XCTAssertEqual(record.lastMatchAt, EscalationCoordinator.Stamp(wall: start + 125, awake: 125),
                       "the clocks' at the moment it began, both of them")
        XCTAssertNotEqual(record.lastMatchAt.wall, notification.timestamp, "and not the banner's own time")
        XCTAssertNil(record.lastShortcutRunAt, "no Shortcut has run")
        XCTAssertNil(record.owedPage, "and no page is owed: nothing owes one yet")
    }

    func testBeginKeepsTier1sOutcomeAsGivenWhateverItWas() throws {
        let outcomes: [AlertOutcome?] = [
            nil, heard,
            AlertOutcome.played(sound: "Glass", gainDB: 0, outputSilent: true),
            AlertOutcome.failed("sound \"Glass\" was not found"),
            AlertOutcome.playedButNotSpoken(sound: "Glass", gainDB: 0, reason: "x", outputSilent: false),
            AlertOutcome.silentByRule, AlertOutcome.noAlertSet,
        ]
        let ladder = coordinator()
        for outcome in outcomes {
            let id = begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification,
                           entryID: UUID(), tier1Outcome: outcome)
            XCTAssertEqual(try kept(ladder, id).tier1Outcome, outcome, "\(String(describing: outcome))")
        }
    }

    func testTheHelperSaysNothingOfTier1UnlessAskedTo() throws {
        let ladder = coordinator()
        let id = begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        XCTAssertNil(try kept(ladder, id).tier1Outcome, "nil: not proof that anything was heard")
    }

    func testTwoRulesWithTheSameNameAreToldApartByTheirIds() throws {
        let ladder = coordinator()
        let first = rule("On-call mentions", Escalation(tier3: repeating()))
        let second = rule("On-call mentions", Escalation(tier3: repeating()))
        XCTAssertNotEqual(first.id, second.id)
        let a = begin(ladder, rule: first, notification: notification, entryID: UUID())
        let b = begin(ladder, rule: second, notification: notification, entryID: UUID())
        XCTAssertEqual(try kept(ladder, a).ruleID, first.id)
        XCTAssertEqual(try kept(ladder, b).ruleID, second.id)
        let again = begin(ladder, rule: first, notification: notification, entryID: UUID())
        XCTAssertNotEqual(again, a, "nothing joins yet: the same rule begins another escalation")
        XCTAssertEqual(try kept(ladder, again).ruleID, first.id, "under the same id")
    }

    func testAnEscalationNeverBegunOrRetiredHasNoRecord() throws {
        let ladder = coordinator()
        XCTAssertNil(ladder.bookkeeping(of: EscalationID()))
        let id = try XCTUnwrap(begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification,
                                     entryID: UUID()))
        _ = try kept(ladder, id)
        ladder.acknowledge(id)
        XCTAssertNil(ladder.bookkeeping(of: id), "retired, so forgotten with its notification")
        XCTAssertEqual(ladder.trackedCount, 0)
    }

    func testTheTimeOfTheLastShortcutRunIsWhenTier4StartedItAndNotWhenItReported() throws {
        let ladder = coordinator()
        let tier4 = FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me"))
        let id = begin(ladder, rule: rule(Escalation(tier3: repeating(maxRepeats: nil, maxDuration: nil), tier4: tier4)),
                       notification: notification, entryID: UUID())
        clock.advance(by: 119)
        XCTAssertNil(try kept(ladder, id).lastShortcutRunAt, "not yet")
        clock.advance(by: 1)
        let startedNow = EscalationCoordinator.Stamp(wall: start + 120, awake: 120)
        XCTAssertEqual(try kept(ladder, id).lastShortcutRunAt, startedNow, "it started now, by both clocks")
        clock.advance(by: 80)
        shortcutRuns[0].report(.shortcutLaunched(name: "Page me"))
        XCTAssertEqual(try kept(ladder, id).lastShortcutRunAt, startedNow, "a report is not another run")
        XCTAssertEqual(try kept(ladder, id).lastMatchAt, EscalationCoordinator.Stamp(wall: start, awake: 0),
                       "and the last match did not move")
    }

    func testAFinalAlertIsNotAShortcutRunAndALadderWithoutOneHasNoRun() throws {
        let ladder = coordinator()
        let alerting = begin(ladder, rule: rule(Escalation(tier4: FinalAlert(afterSeconds: 30, action: .alert(glass)))),
                             notification: notification, entryID: UUID())
        let none = begin(ladder, rule: rule(Escalation(tier3: repeating())), notification: notification, entryID: UUID())
        clock.advance(by: 300)
        XCTAssertEqual(sounds.filter { $0 == "Glass" }.count, 1, "the final alert sounded")
        XCTAssertNil(try kept(ladder, alerting).lastShortcutRunAt)
        XCTAssertNil(try kept(ladder, none).lastShortcutRunAt)
        XCTAssertEqual(shortcutRuns.count, 0)
    }

    // MARK: - How long ago a match or a run was, whatever the wall clock does

    func testAMomentLooksAsOldAsTheLongerClockSaysAndNeverNearer() {
        let noted = EscalationCoordinator.Stamp(wall: start, awake: 1000)
        func elapsed(wall: TimeInterval, awake: TimeInterval) -> TimeInterval {
            noted.elapsed(wall: start + wall, awake: 1000 + awake)
        }
        XCTAssertEqual(elapsed(wall: 0, awake: 0), 0)
        XCTAssertEqual(elapsed(wall: 45, awake: 45), 45, "both clocks agree")
        XCTAssertEqual(elapsed(wall: 245, awake: 45), 245, "a sleep: only the wall clock counts it, and it is older")
        XCTAssertEqual(elapsed(wall: 45.0 - 3600.0, awake: 45), 45,
                       "a wall clock set back an hour: the awake clock says how long it was")
        XCTAssertEqual(elapsed(wall: -3600, awake: 0), 0, "and it is never less than nothing")
        XCTAssertEqual(elapsed(wall: -3600, awake: -5), 0, "whatever either clock says")
        XCTAssertEqual(elapsed(wall: 45.0 + 3600.0, awake: 45), 3645, "set forward an hour: older")
    }

    func testASetBackWallClockDoesNotMakeTheLastMatchOrRunLookRecent() throws {
        // What a quiet gap and the 10 minutes before a Shortcut may run again
        // are measured from, and what an owed page waits on. A moment kept in
        // the future by a clock set back an hour would hold each of them off
        // for an hour, which is a page that does not go.
        clock.advance(by: 100)
        let ladder = coordinator()
        let tier4 = FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me"))
        let id = begin(ladder, rule: rule(Escalation(tier3: repeating(maxRepeats: nil, maxDuration: nil), tier4: tier4)),
                       notification: notification, entryID: UUID())
        clock.advance(by: 120)
        XCTAssertEqual(shortcutRuns.count, 1)
        func ago() throws -> [TimeInterval] {
            let record = try kept(ladder, id)
            let run = try XCTUnwrap(record.lastShortcutRunAt)
            return [record.lastMatchAt.elapsed(wall: clock.now(), awake: clock.awakeTime()),
                    run.elapsed(wall: clock.now(), awake: clock.awakeTime())]
        }
        XCTAssertEqual(try ago(), [120.0, 0.0])
        clock.advance(by: 30)
        XCTAssertEqual(try ago(), [150.0, 30.0])
        clock.sleep(for: 100)
        XCTAssertEqual(try ago(), [250.0, 130.0], "a sleep too short to convert: the wall clock counts it, so they are older")

        let due = try kept(ladder, id).repeatDue
        clock.stepBack(by: 3600)
        XCTAssertLessThan(clock.now().timeIntervalSince(try kept(ladder, id).lastMatchAt.wall), 0,
                          "the wall clock now reads before the match: it was set back")
        XCTAssertEqual(try ago(), [150.0, 30.0], "and the awake clock says how long ago they were")
        ladder.checkForSleep()
        XCTAssertTrue(ladder.hasLiveEscalations, "a clock set back is not a sleep, and converts nothing")
        XCTAssertEqual(try kept(ladder, id).repeatDue, due, "the repeat is still due by the awake clock")
        clock.advance(by: 10)
        XCTAssertEqual(try ago(), [160.0, 40.0], "and they go on growing from there")
    }

    // MARK: - When the repeat is due

    func testTheRepeatsDueTimeFollowsItsTimerThroughArmFireAndCap() throws {
        clock.advance(by: 100)  // the awake clock is not at zero when the ladder begins
        let ladder = coordinator()
        let id = begin(ladder, rule: rule(Escalation(tier3: repeating(every: 30, maxRepeats: 3, maxDuration: nil))),
                       notification: notification, entryID: UUID())
        XCTAssertEqual(try kept(ladder, id).repeatDue, 130, "armed: now and one interval")
        clock.advance(by: 29)
        XCTAssertEqual(try kept(ladder, id).repeatDue, 130, "still the same timer")
        clock.advance(by: 1)
        XCTAssertEqual(sounds.count, 1)
        XCTAssertEqual(try kept(ladder, id).repeatDue, 160, "fired and re-armed: the next one is due")
        clock.advance(by: 30)
        XCTAssertEqual(try kept(ladder, id).repeatDue, 190)
        clock.advance(by: 30)
        XCTAssertEqual(sounds.count, 3)
        XCTAssertEqual(last?.status, .capped(at: start + 190))
        XCTAssertNil(try kept(ladder, id).repeatDue, "capped: the escalation is held and listed, and none is armed")
        XCTAssertEqual(clock.pendingCount, 0)
    }

    func testTheRepeatsDueTimeGoesWithTheTimerWhenItIsCancelled() throws {
        let ladder = coordinator()
        // Waiting on its Shortcut's report, so that it is still held once acknowledged.
        let acknowledged = begin(ladder, rule: rule("A", Escalation(tier3: repeating(),
                                                                    tier4: FinalAlert(afterSeconds: 5,
                                                                                      action: .shortcut(name: "Page me")))),
                                 notification: notification, entryID: UUID())
        let asleep = begin(ladder, rule: rule("B", Escalation(tier3: repeating())), notification: notification,
                           entryID: UUID())
        let other = begin(ladder, rule: rule("C", Escalation(tier3: repeating(every: 45))), notification: notification,
                          entryID: UUID())
        clock.advance(by: 5)
        XCTAssertEqual(shortcutRuns.count, 1)
        XCTAssertEqual(try kept(ladder, acknowledged).repeatDue, 30)
        XCTAssertEqual(try kept(ladder, asleep).repeatDue, 30)
        XCTAssertEqual(try kept(ladder, other).repeatDue, 45)

        ladder.acknowledge(try XCTUnwrap(acknowledged))
        XCTAssertNil(try kept(ladder, acknowledged).repeatDue, "acknowledging cancels it, with every other timer")
        XCTAssertEqual(try kept(ladder, other).repeatDue, 45, "and only that escalation's")

        clock.sleep(for: 400)
        ladder.checkForSleep()
        XCTAssertFalse(ladder.hasLiveEscalations, "both converted")
        XCTAssertNil(try kept(ladder, asleep).repeatDue, "converted after a sleep: cancelled")
        XCTAssertNil(try kept(ladder, other).repeatDue)
        XCTAssertEqual(clock.pendingCount, 0, "and no timer is left that one could belong to")
    }

    func testALadderWithNoRepeatHasNoRepeatDue() throws {
        let ladder = coordinator()
        let panelOnly = begin(ladder, rule: rule("A", Escalation(tier2: PanelAlert(delaySeconds: 10))),
                              notification: notification, entryID: UUID())
        let finalOnly = begin(ladder, rule: rule("B", Escalation(tier4: FinalAlert(afterSeconds: 60, action: .alert(glass)))),
                              notification: notification, entryID: UUID())
        let tooShort = begin(ladder, rule: rule("C", Escalation(tier3: repeating(every: 30, maxRepeats: nil, maxDuration: 10))),
                             notification: notification, entryID: UUID())
        for id in [panelOnly, finalOnly, tooShort] { XCTAssertNil(try kept(ladder, id).repeatDue) }
        XCTAssertEqual(records.last { $0.1.ruleName == "C" }?.1.status, .capped(at: start),
                       "a limit shorter than one interval allows no repeat")
        clock.advance(by: 100)
        for id in [panelOnly, finalOnly, tooShort] { XCTAssertNil(try kept(ladder, id).repeatDue) }
    }

    func testTheRepeatsDueTimeIsOnTheClockTheTimersFallDueBy() throws {
        // The awake clock stops while the Mac sleeps, as the timers' time does,
        // and a sleep too short to convert is counted by the wall clock alone. A
        // due time taken from the wall clock would look nearer than the timer
        // is, which is how a match could be called covered by a repeat that is
        // not about to sound.
        let ladder = coordinator()
        let id = begin(ladder, rule: rule(Escalation(tier3: repeating(maxRepeats: nil, maxDuration: nil))),
                       notification: notification, entryID: UUID())
        clock.advance(by: 10)
        clock.sleep(for: 200)
        XCTAssertEqual(try kept(ladder, id).repeatDue, 30, "a sleep moves the wall clock and not the timers'")
        XCTAssertEqual(clock.awakeTime(), 10)
        clock.advance(by: 20)
        XCTAssertEqual(sounds.count, 1, "it fires by awake time, which is when it was said to be due")
        XCTAssertEqual(try kept(ladder, id).repeatDue, 60)
        XCTAssertEqual(last?.status, .live, "and a sleep of 200 seconds resumes")
    }

    func testALateTimersNextDueTimeIsFromWhenItFired() throws {
        // A real timer is a few milliseconds late. What is recorded when one is
        // armed is when it is scheduled to fall due, and the next is scheduled
        // from when this one fired, as the timer is.
        clock.lateness = 0.0035
        let ladder = coordinator()
        let id = begin(ladder, rule: rule(Escalation(tier3: repeating(maxRepeats: nil, maxDuration: nil))),
                       notification: notification, entryID: UUID())
        XCTAssertEqual(try kept(ladder, id).repeatDue, 30)
        clock.advance(by: 31)
        XCTAssertEqual(sounds.count, 1)
        XCTAssertEqual(try XCTUnwrap(try kept(ladder, id).repeatDue), 60.0035, accuracy: 1e-9)
    }

    // MARK: - What a summary counts

    func testASummaryBeginsAsOneMatchWithNoFinalOutcomeSet() throws {
        let summary = EscalationSummary(ruleName: "On-call mentions", startedAt: start)
        XCTAssertEqual(summary.matchCount, 1)
        XCTAssertEqual(summary.finalCount, 0)

        let ladder = coordinator()
        begin(ladder, rule: rule(Escalation(tier2: PanelAlert(delaySeconds: 10), tier3: repeating(),
                                            tier4: FinalAlert(afterSeconds: 120, action: .alert(glass)))),
              notification: notification, entryID: UUID())
        XCTAssertEqual(last?.matchCount, 1)
        XCTAssertEqual(last?.finalCount, 0)
        clock.advance(by: 600)
        XCTAssertFalse(records.isEmpty)
        XCTAssertTrue(records.allSatisfy { $0.1.matchCount == 1 }, "every record of it says one match: nothing joins")
        XCTAssertFalse(panels.flatMap { $0 }.isEmpty)
        XCTAssertTrue(panels.flatMap { $0 }.allSatisfy { $0.1.matchCount == 1 })
    }

    func testTheFinalOutcomeIsCountedEachTimeItIsSet() throws {
        let ladder = coordinator()
        begin(ladder, rule: rule("Alert", Escalation(tier4: FinalAlert(afterSeconds: 30, action: .alert(glass)))),
              notification: notification, entryID: UUID())
        begin(ladder, rule: rule("Page", Escalation(tier4: FinalAlert(afterSeconds: 60, action: .shortcut(name: "Page me")))),
              notification: notification, entryID: UUID())
        func latest(_ name: String) -> EscalationSummary? { records.last { $0.1.ruleName == name }?.1 }
        XCTAssertEqual(latest("Alert")?.finalCount, 0)
        XCTAssertEqual(latest("Page")?.finalCount, 0)

        clock.advance(by: 30)
        XCTAssertEqual(latest("Alert")?.finalCount, 1, "a final alert sets it once")
        XCTAssertEqual(latest("Alert")?.final, .alerted(.played(sound: "Glass", gainDB: 0, outputSilent: false)))
        clock.advance(by: 30)
        XCTAssertEqual(latest("Page")?.finalCount, 0, "a Shortcut that has started has not set it: nothing has reported")

        shortcutRuns[0].report(.shortcutFailed(name: "Page me", reason: "the Shortcut \"Page me\" is not installed"))
        XCTAssertEqual(latest("Page")?.finalCount, 1)
        shortcutRuns[0].report(.shortcutLaunched(name: "Page me"))
        XCTAssertEqual(latest("Page")?.finalCount, 2, "a later report replaces the outcome and is counted again")
        XCTAssertEqual(latest("Page")?.final, .shortcutLaunched(name: "Page me"))
        XCTAssertEqual(latest("Alert")?.finalCount, 1, "and the other escalation's count is its own")
    }

    func testTheFinalCountRisesWithTheOutcomeAndNothingElse() {
        var summary = EscalationSummary(ruleName: "On-call mentions", startedAt: start)
        summary.final = .shortcutFailed(name: "Page me", reason: "x")
        XCTAssertEqual(summary.finalCount, 1)
        summary.final = .shortcutFailed(name: "Page me", reason: "x")
        XCTAssertEqual(summary.finalCount, 2, "the same outcome again is another report")
        summary.status = .acknowledged(at: start)
        summary.repeatCount = 5
        summary.lastRepeat = .failed("x")
        summary.matchCount = 9
        XCTAssertEqual(summary.finalCount, 2, "nothing else counts")
        summary.final = nil
        XCTAssertEqual(summary.finalCount, 2, "taking it away is not an outcome set")
    }

    func testASummaryBuiltWithAFinalOutcomeHasHadItSetAtLeastOnce() {
        let outcome = FinalOutcome.shortcutLaunched(name: "Page me")
        XCTAssertEqual(EscalationSummary(ruleName: "R", startedAt: start, final: outcome).finalCount, 1,
                       "so a summary built as a test builds one is not one that was never set")
        XCTAssertEqual(EscalationSummary(ruleName: "R", startedAt: start, final: outcome, finalCount: 3).finalCount, 3)
        XCTAssertEqual(EscalationSummary(ruleName: "R", startedAt: start, final: outcome, finalCount: 0).finalCount, 1)
        XCTAssertEqual(EscalationSummary(ruleName: "R", startedAt: start).finalCount, 0)
        XCTAssertEqual(EscalationSummary(ruleName: "R", startedAt: start, matchCount: 7).matchCount, 7)
    }
}
