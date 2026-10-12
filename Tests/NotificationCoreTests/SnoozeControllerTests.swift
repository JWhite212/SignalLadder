import XCTest
@testable import NotificationCore

/// The snooze: when it is on, what it holds, what it keeps and when it speaks
/// (M5 plan, Task 4, Rulings 12 and 13, O8 and O9). Every clock is
/// `ManualScheduler`'s, and persistence is a dictionary the closures write to
/// and a second controller reads back: no real timer, no sound, no preferences.
/// Fixtures are invented text (§10.1).
@MainActor
final class SnoozeControllerTests: XCTestCase {
    private var clock: ManualScheduler!
    /// What the preferences hold, as the app's store would keep it.
    private var preferences: [String: Any] = [:]
    /// Every save, in the order they came.
    private var saves: [(key: String, value: Any?)] = []
    private var announcements = 0
    private var redraws = 0
    /// Runs inside the announcement, as a caller that reads the snooze again would.
    private var onAnnounce: (() -> Void)?

    /// 10:00, for the stories that are told in clock times.
    private var start: Date { Date(timeIntervalSince1970: 1_790_000_000) }

    private let pager = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let chatter = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    override func setUp() {
        clock = ManualScheduler()
        preferences = [:]
        saves = []
        announcements = 0
        redraws = 0
        onAnnounce = nil
    }

    /// A controller as the app makes one at launch: from what the preferences
    /// hold, which is what a second one is built from after a relaunch.
    private func make(on scheduler: EscalationScheduler? = nil) -> SnoozeController {
        SnoozeController(
            scheduler: scheduler ?? clock,
            storedUntil: preferences[SnoozeController.untilKey],
            storedHeld: preferences[SnoozeController.heldKey],
            save: { [unowned self] key, value in
                saves.append((key, value))
                preferences[key] = value
            },
            changed: { [unowned self] in redraws += 1 },
            announce: { [unowned self] in
                announcements += 1
                onAnnounce?()
            })
    }

    private func rule(_ escalation: Escalation? = nil, name: String = "On-call mentions", id: UUID? = nil,
                      alert: AlertAction? = .sound(name: "Glass", gainDB: 0),
                      quiet: Bool = true, enabled: Bool = true) -> Rule {
        Rule(id: id ?? pager, name: name, condition: .field(.app, .equals, "Microsoft Teams"), isEnabled: enabled,
             alert: alert, escalation: escalation, quietWhenSnoozed: quiet)
    }

    private let page = FinalAlert(afterSeconds: 120, action: .shortcut(name: "Page me"))

    private var savedUntil: Double? { (preferences[SnoozeController.untilKey] as? NSNumber)?.doubleValue }
    private var savedHeld: [String: Any]? { preferences[SnoozeController.heldKey] as? [String: Any] }
    private var savedCounts: [String: Int]? { savedHeld?["counts"] as? [String: Int] }
    private var savedUnannounced: Int? { savedHeld?["unannounced"] as? Int }

    // MARK: - The durations

    func testTheKeysTheAppSavesUnderAreFixedBecauseTheyAreWhatIsOnDisk() {
        XCTAssertEqual(SnoozeController.untilKey, "snoozeUntil")
        XCTAssertEqual(SnoozeController.heldKey, "snoozeHeld")
    }

    func testTheDurationsAreFifteenMinutesThirtyOneHourAndTwoHoursAndTwoHoursIsTheLongest() {
        XCTAssertEqual(SnoozeDuration.allCases.map(\.seconds), [900.0, 1800.0, 3600.0, 7200.0])
        XCTAssertEqual(SnoozeDuration.longest, 7200.0)
        XCTAssertEqual(SnoozeDuration.allCases.map(\.seconds).max(), SnoozeDuration.longest,
                       "no duration is longer than the longest")
    }

    // MARK: - What it holds

    func testARuleThatMayBeHeldIsHeldDuringASnoozeAndCounted() {
        let snooze = make()
        snooze.start(.thirtyMinutes)
        XCTAssertTrue(snooze.holds(rule()))
        XCTAssertEqual(savedCounts, [pager.uuidString: 1], "saved at once, not at the end")
        XCTAssertTrue(snooze.holds(rule()))
        XCTAssertEqual(snooze.summary.counts, [pager: 2])
        XCTAssertEqual(savedCounts, [pager.uuidString: 2])
    }

    func testNothingIsHeldOrCountedWhileNoSnoozeIsRunning() {
        let snooze = make()
        XCTAssertFalse(snooze.holds(rule()))
        XCTAssertTrue(snooze.summary.isEmpty)
        XCTAssertNil(preferences[SnoozeController.heldKey])
        XCTAssertEqual(saves.count, 0)
    }

    func testARuleWithoutTheFlagIsNotHeldAndNotCounted() {
        let snooze = make()
        snooze.start(.thirtyMinutes)
        XCTAssertFalse(snooze.holds(rule(quiet: false)))
        XCTAssertTrue(snooze.summary.isEmpty)
        XCTAssertNil(preferences[SnoozeController.heldKey])
    }

    func testARuleThatMakesNoSoundIsNotHeldAndNotCountedWhateverItsBoxSays() {
        let snooze = make()
        snooze.start(.thirtyMinutes)
        XCTAssertFalse(snooze.holds(rule(alert: nil)), "no alert")
        XCTAssertFalse(snooze.holds(rule(alert: .silent)), "a silent one")
        XCTAssertFalse(snooze.holds(rule(Escalation(tier2: PanelAlert()), alert: .silent)), "a silent one with a panel")
        XCTAssertFalse(snooze.holds(rule(enabled: false)), "a rule that is off")
        XCTAssertTrue(snooze.summary.isEmpty)
        XCTAssertNil(preferences[SnoozeController.heldKey])
    }

    func testARuleWhoseLastStepIsAShortcutIsNotHeldAndNotCountedAndIsHeldAgainOnceItIsTakenAway() {
        let snooze = make()
        snooze.start(.thirtyMinutes)
        let paging = rule(Escalation(tier2: PanelAlert(), tier4: page))
        XCTAssertFalse(snooze.holds(paging), "the phone page is the alert a snooze must not swallow")
        XCTAssertTrue(snooze.summary.isEmpty, "and it is not counted")
        XCTAssertNil(preferences[SnoozeController.heldKey])

        var withoutIt = paging
        withoutIt.escalation = Escalation(tier2: PanelAlert())
        XCTAssertTrue(snooze.holds(withoutIt), "the tick was kept, and counts again when the Shortcut is gone")
        XCTAssertEqual(snooze.summary.counts, [pager: 1])
    }

    // MARK: - When a snooze ends

    func testTheSnoozeEndsWhenItsTimePassesThoughItsTimerNeverFired() {
        let snooze = make()
        snooze.start(.fifteenMinutes)
        XCTAssertEqual(clock.pendingCount, 1)
        clock.sleep(for: 899)
        XCTAssertTrue(snooze.isActive)
        XCTAssertEqual(snooze.endsAt, start + 900)
        clock.sleep(for: 1)
        XCTAssertFalse(snooze.isActive, "the wall clock says it is over, whether or not anything was woken")
        XCTAssertNil(snooze.endsAt)
        XCTAssertFalse(snooze.holds(rule()), "so a match alerts")
        XCTAssertNil(preferences[SnoozeController.untilKey], "the saved end goes with it")
        XCTAssertEqual(clock.pendingCount, 0, "and so does the timer")
    }

    func testEndingEarlyRestoresAlertsAndKeepsWhatWasHeld() {
        let snooze = make()
        snooze.start(.thirtyMinutes)
        XCTAssertTrue(snooze.holds(rule()))
        snooze.end()
        XCTAssertFalse(snooze.isActive)
        XCTAssertFalse(snooze.holds(rule()), "alerts are back")
        XCTAssertEqual(snooze.summary.counts, [pager: 1], "what it held stays")
        XCTAssertNil(preferences[SnoozeController.untilKey])
        XCTAssertEqual(clock.pendingCount, 0)
        clock.advance(by: 7200)
        XCTAssertEqual(announcements, 0)
    }

    func testStartingAgainReplacesTheEndAndDoesNotAddToIt() {
        let snooze = make()
        snooze.start(.twoHours)
        clock.advance(by: 600)
        snooze.start(.fifteenMinutes)
        XCTAssertEqual(snooze.endsAt, start + 600 + 900, "shorter, and from now")
        XCTAssertEqual(savedUntil, 1_790_001_500.0)
        XCTAssertEqual(clock.pendingCount, 1, "one timer, the new one")
        clock.advance(by: 900)
        XCTAssertFalse(snooze.isActive)

        snooze.start(.fifteenMinutes)
        snooze.start(.twoHours)
        XCTAssertEqual(snooze.endsAt, clock.now() + 7200, "and a longer one replaces it as well")
    }

    func testStartingSavesTheEndAsSecondsSince1970AndAsksForARedraw() {
        let snooze = make()
        snooze.start(.fifteenMinutes)
        let stored = preferences[SnoozeController.untilKey]
        XCTAssertEqual(stored as? Double, 1_790_000_900.0, "a real number of seconds since 1970")
        XCTAssertTrue(stored is Double, "and of no other type: \(type(of: stored))")
        XCTAssertEqual(redraws, 1)
    }

    // MARK: - The longest

    func testASnoozeStartedForTwoHoursThenTheWallClockMovedBackAnHourEndsNoLaterThanTwoHoursFromNow() throws {
        let snooze = make()
        snooze.start(.twoHours)
        clock.sleep(for: -3600)
        let end = try XCTUnwrap(snooze.endsAt)
        XCTAssertLessThanOrEqual(end, clock.now() + 7200)
        XCTAssertTrue(snooze.isActive)
    }

    func testTheLongestIsEnforcedAtEveryReadAndNotOnlyWhenARestoredEndIsRead() throws {
        // A controller built from a saved end has no awake deadline, so only the
        // cap can pull this one in when the clock goes back.
        preferences[SnoozeController.untilKey] = start.timeIntervalSince1970 + 6600
        let snooze = make()
        XCTAssertEqual(snooze.endsAt, start + 6600, "restored as saved: within 2 hours")
        clock.sleep(for: -3600)
        XCTAssertEqual(snooze.endsAt, clock.now() + 7200, "now it is 2 hours and 50 minutes off, and is cut to 2 hours")
        clock.sleep(for: -3600)
        XCTAssertEqual(snooze.endsAt, clock.now() + 7200, "and again at the next read")
    }

    func testTheLongestIsEnforcedOnRestoreAndWhatIsSavedIsTheCutEnd() throws {
        preferences[SnoozeController.untilKey] = start.timeIntervalSince1970 + 5 * 3600
        let snooze = make()
        XCTAssertEqual(snooze.endsAt, start + 7200)
        XCTAssertEqual(savedUntil, 1_790_007_200.0, "saved in its place, so a relaunch cannot take 2 hours from a later now")
        XCTAssertEqual(saves.count, 1)
        clock.advance(by: 3600)
        XCTAssertEqual(snooze.endsAt, start + 7200, "it is not 2 hours from each read")
        clock.advance(by: 3600)
        XCTAssertFalse(snooze.isActive)
    }

    func testAShortSnoozeIsNotStretchedByAClockSteppedBack() {
        let snooze = make()
        snooze.start(.fifteenMinutes)
        clock.sleep(for: -3600)
        XCTAssertEqual(snooze.endsAt, clock.now() + 900,
                       "15 minutes from now in awake time, and not the 75 the wall end would give")
        clock.advance(by: 899)
        XCTAssertTrue(snooze.isActive)
        clock.advance(by: 1)
        XCTAssertFalse(snooze.isActive, "ended after 15 minutes awake, with the wall end still ahead")
        XCTAssertNil(preferences[SnoozeController.untilKey])
    }

    func testAThirtyMinuteSnoozeAcrossAFortyMinuteSleepEndsByTheWall() {
        let snooze = make()
        snooze.start(.thirtyMinutes)
        clock.sleep(for: 1799)
        XCTAssertTrue(snooze.isActive)
        clock.sleep(for: 601)
        XCTAssertEqual(clock.awake, 0, "the Mac was asleep: awake time did not move")
        XCTAssertFalse(snooze.isActive, "so it is the wall that ends it")
    }

    func testAControllerBuiltFromWhatAnotherSavedKeepsOnlyTheWallEndAndTheCap() {
        do {
            let first = make()
            first.start(.fifteenMinutes)
            clock.sleep(for: -3600)
            XCTAssertEqual(first.endsAt, clock.now() + 900)
        }
        let second = make()
        XCTAssertEqual(second.endsAt, start + 900, "the saved wall end, which is 75 minutes from now")
        XCTAssertEqual(second.endsAt?.timeIntervalSince(clock.now()), 4500)

        // And the cap, once the saved end is more than 2 hours from the new now.
        clock.sleep(for: -3600)
        XCTAssertEqual(second.endsAt, clock.now() + 7200, "135 minutes off is cut to 2 hours")
    }

    // MARK: - What is stored

    func testAStoredEndThatIsPastNotFiniteOrOfTheWrongTypeGivesNoSnoozeAndIsTakenOut() {
        let now = start.timeIntervalSince1970
        let garbage: [(label: String, value: Any)] = [
            ("a time in the past", now - 1),
            ("exactly now", now),
            ("the epoch", 0.0),
            ("negative", -5.0),
            ("infinite", Double.infinity),
            ("negative infinity", -Double.infinity),
            ("not a number", Double.nan),
            ("true", true),
            ("false", false),
            ("a string of the right number", "1790000900"),
            ("a date", start + 900),
            ("a list", [now + 900]),
            ("a dictionary", ["until": now + 900]),
            ("a null", NSNull()),
        ]
        for entry in garbage {
            clock = ManualScheduler()
            preferences = [SnoozeController.untilKey: entry.value]
            saves = []
            redraws = 0
            let snooze = make()
            XCTAssertEqual(clock.pendingCount, 0, "no timer for \(entry.label)")
            XCTAssertNil(preferences[SnoozeController.untilKey], "\(entry.label) is taken out, so a clock set back cannot revive it")
            XCTAssertEqual(saves.count, 1, entry.label)
            XCTAssertFalse(snooze.isActive, entry.label)
            XCTAssertNil(snooze.endsAt, entry.label)
            XCTAssertEqual(redraws, 0, "\(entry.label) was never a snooze, so none ended")
            XCTAssertEqual(saves.count, 1, "and reading it saves nothing more: \(entry.label)")
        }
    }

    func testAStoredEndWithinTwoHoursIsKeptAsItWasAndAWholeNumberIsATimeToo() {
        preferences = [SnoozeController.untilKey: start.timeIntervalSince1970 + 900]
        let snooze = make()
        XCTAssertEqual(snooze.endsAt, start + 900)
        XCTAssertEqual(saves.count, 0, "nothing is written for a value that is read as it is")
        XCTAssertEqual(clock.pendingCount, 1, "the timer that redraws at the end")

        clock = ManualScheduler()
        preferences = [SnoozeController.untilKey: 1_790_000_900 as Int]
        XCTAssertEqual(make().endsAt, start + 900, "an integer, as a property list may hand one back")
    }

    func testAStoredEndFurtherOffThanTwoHoursGivesTwoHours() {
        let now = start.timeIntervalSince1970
        for far in [now + 7201, now + 5 * 3600, now + 1e12, Double.greatestFiniteMagnitude] {
            clock = ManualScheduler()
            preferences = [SnoozeController.untilKey: far]
            let snooze = make()
            XCTAssertEqual(snooze.endsAt, start + 7200, "\(far)")
            XCTAssertEqual(savedUntil, 1_790_007_200.0, "\(far)")
        }
        clock = ManualScheduler()
        preferences = [SnoozeController.untilKey: now + 7200]
        saves = []
        XCTAssertEqual(make().endsAt, start + 7200, "exactly 2 hours is not cut")
        XCTAssertEqual(saves.count, 0)
    }

    func testARestoredSnoozeEndsAtItsTimeAndRedrawsThen() {
        preferences[SnoozeController.untilKey] = start.timeIntervalSince1970 + 900
        let snooze = make()
        clock.advance(by: 899)
        XCTAssertTrue(snooze.isActive)
        let before = redraws
        clock.advance(by: 1)
        XCTAssertEqual(redraws, before + 1, "the timer asked for it, before anything had read the snooze")
        XCTAssertFalse(snooze.isActive)
        XCTAssertNil(preferences[SnoozeController.untilKey])
    }

    func testARestoredSnoozeWhoseWallClockWasSetBackKeepsItsTimerForWhatIsLeft() {
        preferences[SnoozeController.untilKey] = start.timeIntervalSince1970 + 900
        let snooze = make()
        clock.sleep(for: -600)
        clock.advance(by: 900)
        XCTAssertTrue(snooze.isActive, "the timer fired, and the wall end is still 10 minutes off")
        XCTAssertEqual(clock.pendingCount, 1, "so it is set again for what is left")
        clock.advance(by: 599)
        XCTAssertTrue(snooze.isActive)
        clock.advance(by: 1)
        XCTAssertFalse(snooze.isActive)
    }

    func testATimerThatFindsTheEndAHairAheadIsSetAgainWhenTheEndPassesBeforeTheNextRead() {
        let drifting = DriftingScheduler(clock)
        preferences[SnoozeController.untilKey] = start.timeIntervalSince1970 + 900
        preferences[SnoozeController.heldKey] = HeldSummary(counts: [pager: 2], unannounced: 2).propertyList
        let snooze = make(on: drifting)
        clock.sleep(for: -1)
        drifting.secondsPerRead = 1
        // The timer fires with the wall end a second ahead; the first read finds
        // it so, and by the second it has passed.
        clock.advance(by: 900)
        XCTAssertEqual(announcements, 1, "settled by the timer, and not left to whatever reads the snooze next")
        XCTAssertEqual(clock.pendingCount, 0, "nothing is left running")
        XCTAssertNil(preferences[SnoozeController.untilKey], "the saved end went with it")
        XCTAssertEqual(savedUnannounced, 0)
        drifting.secondsPerRead = 0
        XCTAssertFalse(snooze.isActive)
        XCTAssertEqual(announcements, 1, "and once")
    }

    // MARK: - The timer

    func testTheTimerOnlyAsksForARedrawAndSettlesWhatIsOwed() {
        let snooze = make()
        snooze.start(.fifteenMinutes)
        XCTAssertTrue(snooze.holds(rule()))
        let before = redraws
        clock.advance(by: 899)
        XCTAssertEqual(redraws, before, "nothing yet")
        XCTAssertEqual(announcements, 0)
        clock.advance(by: 1)
        XCTAssertEqual(redraws, before + 1, "one redraw, at the end")
        XCTAssertEqual(announcements, 1)
        XCTAssertFalse(snooze.isActive)
    }

    func testATimerCancelledAndStillOnItsWayAndOneDeliveredTwiceChangeNothing() {
        let snooze = make()
        snooze.start(.fifteenMinutes)
        XCTAssertTrue(snooze.holds(rule()))
        snooze.end()
        XCTAssertEqual(clock.runCancelled(), 1)
        XCTAssertEqual(announcements, 0, "a snooze the user ended is not announced by its late timer")

        // Replaced: the old timer, delivered late, must not take the new one's place.
        snooze.start(.fifteenMinutes)
        snooze.start(.twoHours)
        XCTAssertTrue(snooze.holds(rule()))
        XCTAssertEqual(clock.runCancelled(), 1, "the 15-minute timer, on its way after the 2-hour one replaced it")
        XCTAssertTrue(snooze.isActive)
        XCTAssertEqual(snooze.endsAt, clock.now() + 7200)
        XCTAssertEqual(clock.pendingCount, 1)

        // Delivered twice.
        clock.advance(by: 7200)
        XCTAssertEqual(announcements, 1)
        let redrawn = redraws
        clock.refireLast()
        XCTAssertEqual(announcements, 1)
        XCTAssertEqual(redraws, redrawn)
    }

    func testReadingAnActiveSnoozeChangesNothing() {
        let snooze = make()
        snooze.start(.thirtyMinutes)
        XCTAssertTrue(snooze.holds(rule()))
        let (saved, drawn) = (saves.count, redraws)
        for _ in 0..<3 {
            clock.advance(by: 300)
            _ = (snooze.isActive, snooze.endsAt, snooze.summary)
            snooze.settle()
        }
        XCTAssertEqual(saves.count, saved)
        XCTAssertEqual(redraws, drawn)
        XCTAssertEqual(announcements, 0)
    }

    func testEveryChangeAsksForARedrawAndNothingElseDoes() {
        let snooze = make()
        snooze.start(.thirtyMinutes)
        XCTAssertEqual(redraws, 1, "start")
        XCTAssertTrue(snooze.holds(rule()))
        XCTAssertEqual(redraws, 2, "a hold, since the icon says how many")
        XCTAssertFalse(snooze.holds(rule(quiet: false)))
        XCTAssertEqual(redraws, 2, "a match that is not held changes nothing")
        snooze.end()
        XCTAssertEqual(redraws, 3, "end")
        snooze.end()
        XCTAssertEqual(redraws, 3, "ending what is not running changes nothing")
        snooze.dismissSummary(shown: snooze.summary)
        XCTAssertEqual(redraws, 4, "dismiss")
        snooze.dismissSummary(shown: snooze.summary)
        XCTAssertEqual(redraws, 4, "dismissing nothing changes nothing")
    }

    // MARK: - What was held

    func testHeldMatchesAreCountedPerRuleIdWithTheTimeOfTheFirst() {
        let snooze = make()
        snooze.start(.oneHour)
        clock.advance(by: 60)
        XCTAssertTrue(snooze.holds(rule(id: pager)))
        clock.advance(by: 60)
        XCTAssertTrue(snooze.holds(rule(name: "Team chatter", id: chatter)))
        XCTAssertTrue(snooze.holds(rule(id: pager)))
        let summary = snooze.summary
        XCTAssertEqual(summary.counts, [pager: 2, chatter: 1])
        XCTAssertEqual(summary.total, 3)
        XCTAssertEqual(summary.firstHeldAt, start + 60, "the time of the first, and not of the last")
        XCTAssertEqual(summary.unannounced, 3)
    }

    func testTheSummarySurvivesTheEndOfASnoozeWhetherItRanOutOrWasEnded() {
        let ran = make()
        ran.start(.fifteenMinutes)
        XCTAssertTrue(ran.holds(rule()))
        clock.advance(by: 900)
        XCTAssertEqual(ran.summary.counts, [pager: 1], "it ran out")
        XCTAssertEqual(savedCounts, [pager.uuidString: 1])

        ran.start(.fifteenMinutes)
        XCTAssertTrue(ran.holds(rule(id: chatter)))
        ran.end()
        XCTAssertEqual(ran.summary.counts, [pager: 1, chatter: 1], "it was ended")
        XCTAssertEqual(savedCounts, [pager.uuidString: 1, chatter.uuidString: 1])
    }

    func testTheSummarySurvivesARelaunchAndSoDoesTheSnoozeThatWasRunning() {
        do {
            let first = make()
            first.start(.oneHour)
            clock.advance(by: 120)
            XCTAssertTrue(first.holds(rule()))
            XCTAssertTrue(first.holds(rule()))
        }
        let second = make()
        XCTAssertEqual(second.summary.counts, [pager: 2])
        XCTAssertEqual(second.summary.firstHeldAt, start + 120)
        XCTAssertEqual(second.summary.unannounced, 2, "a snooze is still running, so these are still to be announced")
        XCTAssertTrue(second.isActive)
        XCTAssertTrue(second.holds(rule()), "and it goes on holding")
        XCTAssertEqual(second.summary.counts, [pager: 3])
        clock.advance(by: 3600)
        XCTAssertEqual(announcements, 1, "and it ends by its own timer, announcing what it held")
        XCTAssertEqual(second.summary.counts, [pager: 3])
    }

    func testAMatchHeldAtTenPastTenOfATenToHalfPastSnoozeIsStillCountedAfterASecondStartsAtQuarterToEleven() {
        let snooze = make()
        snooze.start(.thirtyMinutes)                   // 10:00
        clock.advance(by: 600)                         // 10:10
        XCTAssertTrue(snooze.holds(rule()))
        clock.advance(by: 1200)                        // 10:30: it ran out, and nobody opened the menu
        clock.advance(by: 900)                         // 10:45
        snooze.start(.thirtyMinutes)
        XCTAssertEqual(snooze.summary.counts, [pager: 1], "it was not wiped by the second")
        XCTAssertEqual(snooze.summary.firstHeldAt, start + 600)
        XCTAssertTrue(snooze.holds(rule()))
        XCTAssertEqual(snooze.summary.counts, [pager: 2], "the second adds to it")
        XCTAssertEqual(savedCounts, [pager.uuidString: 2])
    }

    func testOnlyDismissingTheSummaryClearsItAndItStartsFreshAfterwards() {
        let snooze = make()
        snooze.start(.oneHour)
        XCTAssertTrue(snooze.holds(rule()))
        snooze.dismissSummary(shown: snooze.summary)
        XCTAssertTrue(snooze.summary.isEmpty)
        XCTAssertNil(preferences[SnoozeController.heldKey], "the key goes, so nothing of it is left")
        XCTAssertTrue(snooze.isActive, "dismissing a summary does not end a snooze")
        clock.advance(by: 30)
        XCTAssertTrue(snooze.holds(rule()))
        XCTAssertEqual(snooze.summary.counts, [pager: 1])
        XCTAssertEqual(snooze.summary.firstHeldAt, start + 30)
    }

    func testDismissingTakesOutWhatTheMenuShowedAndAMatchHeldWhileItWasOpenSurvives() {
        let snooze = make()
        snooze.start(.fifteenMinutes)
        XCTAssertTrue(snooze.holds(rule()))
        let shown = snooze.summary                      // the menu is built, and held open
        XCTAssertTrue(snooze.holds(rule()))             // a match of the same rule, while it is open
        XCTAssertTrue(snooze.holds(rule(name: "Team chatter", id: chatter)))   // and one of another rule
        let (saved, drawn) = (saves.count, redraws)
        snooze.dismissSummary(shown: shown)             // Dismiss, beside the line that was shown
        XCTAssertEqual(snooze.summary.counts, [pager: 1, chatter: 1], "what was not shown is still counted")
        XCTAssertEqual(savedCounts, [pager.uuidString: 1, chatter.uuidString: 1], "and is saved")
        XCTAssertEqual(snooze.summary.unannounced, 2)
        XCTAssertEqual(savedUnannounced, 2)
        XCTAssertEqual(saves.count, saved + 1, "one save")
        XCTAssertEqual(redraws, drawn + 1, "and a redraw, so that the line that was not shown is")
        XCTAssertTrue(snooze.isActive, "dismissing a summary does not end a snooze")
        clock.advance(by: 900)
        XCTAssertEqual(announcements, 1, "the announcement for what was not shown is still owed")
        XCTAssertEqual(snooze.summary.counts, [pager: 1, chatter: 1])
    }

    func testWhatADismissalLeftIsKeptByARelaunchAndAnnouncedWhenTheSnoozeRunsOut() {
        do {
            let first = make()
            first.start(.fifteenMinutes)
            XCTAssertTrue(first.holds(rule()))
            let shown = first.summary
            XCTAssertTrue(first.holds(rule()))
            first.dismissSummary(shown: shown)
        }
        let second = make()
        XCTAssertEqual(second.summary.counts, [pager: 1])
        XCTAssertEqual(second.summary.unannounced, 1)
        XCTAssertNil(second.summary.firstHeldAt, "when the first of what is left was held is not kept, and is not made up")
        XCTAssertTrue(second.isActive)
        clock.advance(by: 900)
        XCTAssertEqual(announcements, 1)
    }

    func testDismissingWhatIsNoLongerThereChangesNothingAndNeverTakesOutWhatIsThere() {
        let snooze = make()
        snooze.start(.fifteenMinutes)
        XCTAssertTrue(snooze.holds(rule()))
        let shown = snooze.summary
        snooze.dismissSummary(shown: shown)
        XCTAssertTrue(snooze.summary.isEmpty)
        let (saved, drawn) = (saves.count, redraws)
        snooze.dismissSummary(shown: shown)             // a second click on the same line
        XCTAssertEqual(saves.count, saved)
        XCTAssertEqual(redraws, drawn)

        XCTAssertTrue(snooze.holds(rule(name: "Team chatter", id: chatter)))
        let (savedAgain, drawnAgain) = (saves.count, redraws)
        snooze.dismissSummary(shown: shown)             // the old line, and a rule it did not count
        XCTAssertEqual(snooze.summary.counts, [chatter: 1])
        XCTAssertEqual(snooze.summary.unannounced, 1, "and what is owed for it is not reduced")
        XCTAssertEqual(saves.count, savedAgain)
        XCTAssertEqual(redraws, drawnAgain)
    }

    func testARecordThatCannotBeReadIsClearedOnlyByADismissalOfALineThatSaidSo() {
        preferences[SnoozeController.heldKey] = "garbled"
        let snooze = make()
        snooze.start(.oneHour)
        XCTAssertTrue(snooze.holds(rule()))
        snooze.dismissSummary(shown: HeldSummary(counts: [pager: 1], unannounced: 1))
        XCTAssertTrue(snooze.summary.counts.isEmpty)
        XCTAssertTrue(snooze.summary.recordUnreadable, "a line that did not say so did not show it")
        XCTAssertEqual(savedHeld?["unreadable"] as? Int, 1)
        snooze.dismissSummary(shown: snooze.summary)
        XCTAssertTrue(snooze.summary.isEmpty)
        XCTAssertNil(preferences[SnoozeController.heldKey])
    }

    func testARecordThatCannotBeReadIsReportedAndSurvivesEverythingButADismissal() {
        preferences[SnoozeController.heldKey] = "garbled"
        do {
            let first = make()
            XCTAssertTrue(first.summary.recordUnreadable, "said to have existed, and not dropped")
            XCTAssertFalse(first.summary.isEmpty)
            first.start(.oneHour)
            XCTAssertTrue(first.holds(rule()))
            XCTAssertEqual(first.summary.counts, [pager: 1])
            XCTAssertTrue(first.summary.recordUnreadable, "a new hold does not wipe the fact")
            XCTAssertEqual(savedHeld?["unreadable"] as? Int, 1, "and it is saved with the count, so a relaunch still says it")
            first.end()
        }
        let second = make()
        XCTAssertTrue(second.summary.recordUnreadable)
        XCTAssertEqual(second.summary.counts, [pager: 1])
        second.dismissSummary(shown: second.summary)
        XCTAssertTrue(second.summary.isEmpty)
        XCTAssertNil(preferences[SnoozeController.heldKey])
    }

    func testARuleWithNoIdIsHeldThenReloadedAndItsCountIsKeptUnderTheNotFoundPhrase() throws {
        let json = Data("""
            {"version": 5, "rules": [{"name": "Hand-written pager",
              "condition": {"field": "app", "op": "equals", "value": "Microsoft Teams"},
              "alert": {"sound": "Glass"}, "quietWhenSnoozed": true}]}
            """.utf8)
        let (loaded, problems) = try RuleSetCodec.decode(json)
        XCTAssertEqual(problems, [])
        let before = try XCTUnwrap(loaded.first)

        let snooze = make()
        snooze.start(.oneHour)
        XCTAssertTrue(snooze.holds(before))

        // Reload Rules, or a save: the rule has no id in the file, so it gets a new one.
        let after = try XCTUnwrap(try RuleSetCodec.decode(json).rules.first)
        XCTAssertNotEqual(before.id, after.id)

        XCTAssertEqual(snooze.summary.counts, [before.id: 1], "the count is kept, and not dropped")
        XCTAssertEqual(SnoozeText.summaryLine(snooze.summary, names: SnoozeText.names(of: [after])),
                       SnoozeText.heldOneMatchStem + ": " + SnoozeText.ruleNotFound + " ×1",
                       "and it is neither named nor made up")
    }

    // MARK: - What is saved holds no name

    func testWhatIsSavedHoldsNoNameOnlyNumbersAndIdentifiers() {
        let canary = "CANARY-6d2f-rule-name"
        let named = rule(name: canary, id: pager)
        let snooze = make()
        snooze.start(.thirtyMinutes)
        XCTAssertTrue(snooze.holds(named))
        XCTAssertTrue(snooze.holds(rule(name: canary + " two", id: chatter)))
        XCTAssertTrue(snooze.holds(named))
        clock.advance(by: 1800)
        snooze.start(.fifteenMinutes)
        XCTAssertTrue(snooze.holds(named))
        snooze.end()

        XCTAssertFalse(saves.isEmpty)
        let allowedKeys: Set<String> = [SnoozeController.untilKey, SnoozeController.heldKey]
        for save in saves {
            XCTAssertTrue(allowedKeys.contains(save.key), "a save under \(save.key)")
            guard let value = save.value else { continue }
            assertOnlyNumbersAndIdentifiers(value, in: save.key)
            XCTAssertFalse(String(describing: value).contains("CANARY"), "\(save.key): \(value)")
        }
        XCTAssertFalse(String(describing: preferences).contains("CANARY"))
    }

    /// The only strings in a saved record are the names of its fields and the
    /// identifiers of rules, and every value is a number or a dictionary of them.
    private func assertOnlyNumbersAndIdentifiers(_ value: Any, in path: String,
                                                 file: StaticString = #filePath, line: UInt = #line) {
        let fields: Set<String> = ["counts", "since", "unannounced", "unreadable"]
        if let dictionary = value as? [String: Any] {
            for (key, inner) in dictionary {
                XCTAssertTrue(fields.contains(key) || UUID(uuidString: key) != nil,
                              "\(path) has a key that is neither a field nor an identifier: \(key)", file: file, line: line)
                assertOnlyNumbersAndIdentifiers(inner, in: path + "." + key, file: file, line: line)
            }
        } else {
            XCTAssertTrue(value is NSNumber, "\(path) holds a \(type(of: value)), not a number", file: file, line: line)
        }
    }

    // MARK: - What is announced

    func testASnoozeThatRanOutHavingHeldTwoMatchesAnnouncesOnceAtTheTimerAndNotAgainAtTheNextRead() {
        let snooze = make()
        snooze.start(.fifteenMinutes)
        XCTAssertTrue(snooze.holds(rule()))
        XCTAssertTrue(snooze.holds(rule()))
        clock.advance(by: 899)
        XCTAssertEqual(announcements, 0)
        clock.advance(by: 1)
        XCTAssertEqual(announcements, 1, "at the timer")
        XCTAssertEqual(savedUnannounced, 0, "settled, and saved so")
        XCTAssertEqual(savedCounts, [pager.uuidString: 2], "what was held stays")

        _ = (snooze.isActive, snooze.endsAt, snooze.summary)
        snooze.settle()
        XCTAssertFalse(snooze.holds(rule()))
        clock.advance(by: 7200)
        XCTAssertEqual(announcements, 1, "and not again")
    }

    func testASnoozeThatHeldNothingAnnouncesNothing() {
        let snooze = make()
        snooze.start(.fifteenMinutes)
        XCTAssertFalse(snooze.holds(rule(quiet: false)))
        let before = redraws
        clock.advance(by: 900)
        XCTAssertFalse(snooze.isActive)
        XCTAssertEqual(redraws, before + 1, "it is drawn again all the same")
        XCTAssertEqual(announcements, 0)
        snooze.settle()
        XCTAssertEqual(announcements, 0)
    }

    func testASnoozeEndedFromTheMenuAnnouncesNothingThoughItHeldMatchesAndTheSummaryStays() {
        let snooze = make()
        snooze.start(.thirtyMinutes)
        XCTAssertTrue(snooze.holds(rule()))
        XCTAssertTrue(snooze.holds(rule()))
        snooze.end()
        XCTAssertEqual(announcements, 0, "the user is looking at it")
        XCTAssertEqual(snooze.summary.counts, [pager: 2], "but what it held is still on the summary")
        XCTAssertEqual(snooze.summary.unannounced, 0)
        XCTAssertEqual(savedUnannounced, 0, "and nothing is left owing, even after a relaunch")
        clock.advance(by: 7200)
        snooze.settle()
        XCTAssertEqual(announcements, 0)
        let relaunched = make()
        relaunched.settle()
        XCTAssertEqual(announcements, 0)
    }

    func testAMacThatSleptThroughTheEndAnnouncesAtTheFirstReadOnWakingAndOnlyOnce() {
        let snooze = make()
        snooze.start(.thirtyMinutes)
        XCTAssertTrue(snooze.holds(rule()))
        clock.sleep(for: 2400)
        XCTAssertEqual(announcements, 0, "the timer did not fire, and nothing has looked")
        XCTAssertFalse(snooze.isActive)
        XCTAssertEqual(announcements, 1, "the first read after waking")
        XCTAssertFalse(snooze.isActive)
        _ = snooze.summary
        clock.advance(by: 3600)
        XCTAssertEqual(announcements, 1)
    }

    /// What the app's step on waking does, on a Mac that slept through the end and with no
    /// read before it (`SelfTestPlan.WakeStep.settleSnooze`): what was held is announced,
    /// and the redraw that takes the moon off the icon is asked for, whether or not
    /// anything was held, once. A wake in the middle of the snooze leaves it alone.
    func testSettlingOnWakingAfterASleepThroughTheEndAnnouncesWhatWasHeldAndDrawsTheIconAgainOnce() {
        for held in [true, false] {
            clock = ManualScheduler()
            preferences = [:]
            announcements = 0
            redraws = 0
            let snooze = make()
            snooze.start(.thirtyMinutes)
            if held { XCTAssertTrue(snooze.holds(rule()), "held \(held)") }
            clock.sleep(for: 2400)
            let before = redraws
            XCTAssertEqual(announcements, 0, "held \(held): the timer did not fire, and nothing has looked")

            snooze.settle()
            XCTAssertEqual(announcements, held ? 1 : 0, "held \(held)")
            XCTAssertEqual(redraws, before + 1, "held \(held): the icon is drawn again")
            snooze.settle()
            XCTAssertEqual(announcements, held ? 1 : 0, "held \(held): not again")
            XCTAssertEqual(redraws, before + 1, "held \(held): and not drawn again")
            XCTAssertFalse(snooze.isActive, "held \(held)")
        }

        clock = ManualScheduler()
        preferences = [:]
        announcements = 0
        redraws = 0
        let running = make()
        running.start(.thirtyMinutes)
        XCTAssertTrue(running.holds(rule()))
        clock.sleep(for: 600)
        let before = redraws
        running.settle()
        XCTAssertTrue(running.isActive, "a wake in the middle of it leaves it running")
        XCTAssertEqual(announcements, 0)
        XCTAssertEqual(redraws, before, "and draws nothing")
    }

    func testEveryReadThatFindsTheSnoozeOverAnnouncesIt() {
        let reads: [(label: String, read: (SnoozeController) -> Void)] = [
            ("isActive", { _ = $0.isActive }),
            ("endsAt", { _ = $0.endsAt }),
            ("summary", { _ = $0.summary }),
            ("holds", { _ = $0.holds(Rule(id: UUID(), name: "Other", condition: .field(.app, .equals, "x"))) }),
            ("settle", { $0.settle() }),
        ]
        for entry in reads {
            clock = ManualScheduler()
            preferences = [:]
            announcements = 0
            let snooze = make()
            snooze.start(.fifteenMinutes)
            XCTAssertTrue(snooze.holds(rule()), entry.label)
            clock.sleep(for: 901)
            entry.read(snooze)
            XCTAssertEqual(announcements, 1, entry.label)
            entry.read(snooze)
            XCTAssertEqual(announcements, 1, "\(entry.label) again")
        }
    }

    func testALaunchAfterAnEndNobodyHeardAnnouncesOnceAndNotASecondTime() {
        do {
            let first = make()
            first.start(.thirtyMinutes)
            XCTAssertTrue(first.holds(rule()))
            XCTAssertTrue(first.holds(rule()))
        }                                               // the app quits mid-snooze
        clock.sleep(for: 3600)                          // and is not running when it ends
        let second = make()
        XCTAssertFalse(second.isActive)
        XCTAssertEqual(second.summary.counts, [pager: 2])
        XCTAssertEqual(announcements, 1, "the first read, or the app's settle() at launch, whichever comes first")
        second.settle()
        XCTAssertEqual(announcements, 1)

        let third = make()
        third.settle()
        XCTAssertEqual(announcements, 1, "and not on the launch after that")
        XCTAssertEqual(third.summary.counts, [pager: 2])
    }

    func testTheAppsSettleAtLaunchIsTheOneThatAnnouncesWhenNothingElseHasRead() {
        do {
            let first = make()
            first.start(.thirtyMinutes)
            XCTAssertTrue(first.holds(rule()))
        }
        clock.sleep(for: 3600)
        redraws = 0
        let second = make()
        XCTAssertEqual(announcements, 0, "building it announces nothing")
        second.settle()
        XCTAssertEqual(announcements, 1)
        XCTAssertEqual(redraws, 0, "nothing about the snooze changed, and the app draws its menu and icon itself at launch")
        second.settle()
        XCTAssertEqual(announcements, 1)
    }

    func testANewSnoozeThatHoldsMoreAfterAnAnnouncedSummaryAnnouncesAgainForWhatItHeld() {
        let snooze = make()
        snooze.start(.fifteenMinutes)
        XCTAssertTrue(snooze.holds(rule()))
        XCTAssertTrue(snooze.holds(rule()))
        clock.advance(by: 900)
        XCTAssertEqual(announcements, 1)
        XCTAssertEqual(savedUnannounced, 0)

        snooze.start(.fifteenMinutes)
        XCTAssertTrue(snooze.holds(rule()))
        XCTAssertEqual(savedUnannounced, 1, "owed for the one it held, and not for the two already announced")
        XCTAssertEqual(snooze.summary.counts, [pager: 3], "though the summary holds all three")
        clock.advance(by: 900)
        XCTAssertEqual(announcements, 2)
        XCTAssertEqual(savedUnannounced, 0)
        snooze.settle()
        XCTAssertEqual(announcements, 2)
    }

    func testAnEndNobodyNoticedIsAnnouncedWhenANewSnoozeStartsAndNotFoldedIntoIt() {
        let snooze = make()
        snooze.start(.thirtyMinutes)
        XCTAssertTrue(snooze.holds(rule()))
        clock.sleep(for: 2400)
        XCTAssertEqual(announcements, 0)
        snooze.start(.fifteenMinutes)
        XCTAssertEqual(announcements, 1, "what the first held is announced, before the second begins")
        XCTAssertTrue(snooze.isActive)
        XCTAssertEqual(snooze.summary.unannounced, 0)
        clock.advance(by: 900)
        XCTAssertEqual(announcements, 1, "the second held nothing")
    }

    func testDismissingTheSummaryOwesNothingMore() {
        let snooze = make()
        snooze.start(.fifteenMinutes)
        XCTAssertTrue(snooze.holds(rule()))
        snooze.dismissSummary(shown: snooze.summary)
        clock.advance(by: 900)
        XCTAssertEqual(announcements, 0, "the user has seen it")
        XCTAssertTrue(snooze.summary.isEmpty)
    }

    func testTheAnnouncementMayReadTheSnoozeAgainWithoutBeingMadeTwice() {
        let snooze = make()
        onAnnounce = { [unowned snooze] in
            _ = (snooze.isActive, snooze.endsAt, snooze.summary)
            snooze.settle()
        }
        snooze.start(.fifteenMinutes)
        XCTAssertTrue(snooze.holds(rule()))
        clock.advance(by: 900)
        XCTAssertEqual(announcements, 1, "it is zeroed before it is made")
    }
}

/// A scheduler whose wall clock moves on with every read of it, as a real one
/// does between two reads, here by seconds so that it can be seen. Its timers
/// and its awake time are `ManualScheduler`'s.
@MainActor
private final class DriftingScheduler: EscalationScheduler {
    private let base: ManualScheduler
    var secondsPerRead: TimeInterval = 0

    init(_ base: ManualScheduler) {
        self.base = base
    }

    func now() -> Date {
        let read = base.now()
        base.sleep(for: secondsPerRead)
        return read
    }

    func awakeTime() -> TimeInterval { base.awakeTime() }

    func schedule(after seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> EscalationTimerToken {
        base.schedule(after: seconds, work)
    }

    func cancel(_ token: EscalationTimerToken) { base.cancel(token) }
}
