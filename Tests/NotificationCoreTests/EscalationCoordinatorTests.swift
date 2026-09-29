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
    private var power: [String] = []
    private var silences = 0
    private var shortcutRuns: [(name: String, report: (FinalOutcome) -> Void)] = []
    private var shortcutsReportAtOnce: FinalOutcome?

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
        power = []
        silences = 0
        shortcutRuns = []
        shortcutsReportAtOnce = nil
    }

    private func coordinator(threshold: TimeInterval = 300) -> EscalationCoordinator {
        EscalationCoordinator(
            scheduler: clock,
            playSound: { [unowned self] name, _ in sounds.append(name); return soundOutcome(name) },
            speak: { [unowned self] _, speech in sounds.append("speech:\(speech.voiceIdentifier)")
                return .spoke(text: "said", voice: speech.voiceIdentifier, gainDB: 0, outputSilent: false) },
            playAndSpeak: { [unowned self] name, _, _, _ in sounds.append("\(name)+speech")
                return .played(sound: name, gainDB: 0, outputSilent: false) },
            runShortcut: { [unowned self] name, _, report in
                if let outcome = shortcutsReportAtOnce { report(outcome) } else { shortcutRuns.append((name, report)) }
            },
            updatePanel: { [unowned self] rows in panels.append(rows) },
            recordSummary: { [unowned self] entry, summary in records.append((entry, summary)) },
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
    }

    func testALimitShorterThanOneIntervalIsCappedAtOnce() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating(every: 30, maxRepeats: nil, maxDuration: 10))),
                     notification: notification, entryID: UUID())
        XCTAssertEqual(last?.status, .capped(at: start))
        clock.advance(by: 100)
        XCTAssertEqual(sounds, [])
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

    func testAFreshTier1MatchIsNeverSuppressedByALiveRepeat() {
        // Interrupting is the player's job, not the coordinator's (ruling 7).
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
        clock.runCancelled()
        XCTAssertEqual(sounds, [])
        XCTAssertEqual(records.count, recorded)
    }

    func testATimerDeliveredTwiceActsOnce() {
        let ladder = coordinator()
        ladder.begin(rule: rule(Escalation(tier3: repeating(maxRepeats: nil, maxDuration: nil),
                                           tier4: FinalAlert(afterSeconds: 45, action: .alert(glass)))),
                     notification: notification, entryID: UUID())
        clock.advance(by: 30)
        clock.refireLast()
        XCTAssertEqual(sounds, ["Hero"], "one repeat, and one next repeat armed")
        clock.advance(by: 15)
        clock.refireLast()
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
        clock.runCancelled()
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
}
