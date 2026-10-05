import XCTest
@testable import NotificationCore

/// What switching on-call mode does, as the list the app carries out (M5 plan,
/// Ruling 10): the state, the timers, the health alarm and the watch, the hold
/// against sleep, the menu and the icon, the self-test, and the check window.
final class OnCallSwitchTests: XCTestCase {
    func testTurningOnSavesArmsTheTimerDropsAPendingRetryResetsTheAlarmAndTheWatchHoldsTheMacAwakeDrawsTheMenuRunsASelfTestAndThenOpensTheWindowAndWatchesInThatOrder() {
        XCTAssertEqual(OnCallSwitch.effects(turningOn: true, snoozeActive: false),
                       [.save, .rearmSelfTestTimer, .cancelPendingRetry, .resetHealthAlarm, .resetWatch, .holdAwake,
                        .rebuildMenuAndIcon, .runSelfTestNow, .openCheckWindowIfUrgent, .evaluateWatch])
    }

    func testTurningOffSavesArmsTheTimerLetsGoOfTheHoldClearsTheWatchAndDrawsTheMenuAndNothingElse() {
        XCTAssertEqual(OnCallSwitch.effects(turningOn: false, snoozeActive: false),
                       [.save, .rearmSelfTestTimer, .releaseAwake, .resetWatch, .rebuildMenuAndIcon])
    }

    /// A failed self-test promises "It will retry in a minute." Turning off runs
    /// no self-test in the retry's place, so cancelling it would leave a degraded
    /// state waiting up to half an hour under words that say otherwise (Ruling 8).
    func testTurningOffKeepsAPendingRetryAndRunsNoSelfTest() {
        let off = OnCallSwitch.effects(turningOn: false, snoozeActive: false)
        XCTAssertFalse(off.contains(.cancelPendingRetry))
        XCTAssertFalse(off.contains(.runSelfTestNow))
    }

    /// Turning on says that the user is on call, so a fault already standing is
    /// told afresh: the alarm begins again, and it does so before the self-test
    /// whose report is the first it is asked about.
    func testTurningOnResetsTheHealthAlarmBeforeTheSelfTestThatReportsToIt() throws {
        let on = OnCallSwitch.effects(turningOn: true, snoozeActive: false)
        let reset = try XCTUnwrap(on.firstIndex(of: .resetHealthAlarm))
        let run = try XCTUnwrap(on.firstIndex(of: .runSelfTestNow))
        XCTAssertLessThan(reset, run)
    }

    /// Turning off leaves the alarm's state alone (Ruling 8): what stood on call
    /// is not told again, and one reset would begin the once-per-change rule over.
    func testTurningOffLeavesTheHealthAlarmsStateAlone() {
        XCTAssertFalse(OnCallSwitch.effects(turningOn: false, snoozeActive: false).contains(.resetHealthAlarm))
    }

    /// A self-test run at once takes a retry's place, so turning on drops it. And
    /// it drops it first: the run is awaited, and one that fails arms a retry of
    /// its own, which a cancel after it would take away.
    func testTurningOnDropsAPendingRetryBeforeTheSelfTestThatReplacesItRuns() throws {
        let on = OnCallSwitch.effects(turningOn: true, snoozeActive: false)
        let cancel = try XCTUnwrap(on.firstIndex(of: .cancelPendingRetry))
        let run = try XCTUnwrap(on.firstIndex(of: .runSelfTestNow))
        XCTAssertLessThan(cancel, run)
    }

    /// The hold is taken before the self-test is run, because the run is awaited:
    /// a step after it would wait for the banner to come back, and the Mac would
    /// be free to sleep until it did.
    func testTurningOnHoldsTheMacAwakeBeforeTheSelfTestWhoseRunIsAwaited() throws {
        let on = OnCallSwitch.effects(turningOn: true, snoozeActive: false)
        let hold = try XCTUnwrap(on.firstIndex(of: .holdAwake))
        let run = try XCTUnwrap(on.firstIndex(of: .runSelfTestNow))
        XCTAssertLessThan(hold, run)
    }

    /// Only turning on takes the hold and only turning off lets go of it. A list
    /// that did both would end the hold the moment it began, and one that did
    /// neither would leave a Mac held after the user said they were off call.
    func testOnlyTurningOnHoldsAndOnlyTurningOffReleases() {
        let on = OnCallSwitch.effects(turningOn: true, snoozeActive: false)
        let off = OnCallSwitch.effects(turningOn: false, snoozeActive: false)
        XCTAssertTrue(on.contains(.holdAwake))
        XCTAssertFalse(on.contains(.releaseAwake), "turning on lets go of the hold it has just taken")
        XCTAssertTrue(off.contains(.releaseAwake))
        XCTAssertFalse(off.contains(.holdAwake), "turning off takes a hold")
    }

    /// The timer is armed at the interval of the state, and the state is the one
    /// just saved.
    func testEitherSwitchSavesBeforeItArmsTheTimer() throws {
        for turningOn in [true, false] {
            for snoozeActive in [true, false] {
                let effects = OnCallSwitch.effects(turningOn: turningOn, snoozeActive: snoozeActive)
                let save = try XCTUnwrap(effects.firstIndex(of: .save))
                let arm = try XCTUnwrap(effects.firstIndex(of: .rearmSelfTestTimer))
                XCTAssertLessThan(save, arm, "turning \(turningOn ? "on" : "off"), snooze running \(snoozeActive)")
            }
        }
    }

    /// The window is asked about once, when the self-test that turning on started
    /// has returned: a check made before it would say that nothing had been
    /// verified, which is true of every switch-on.
    func testTurningOnAsksAboutTheWindowAndWatchesOnlyAfterTheSelfTestHasReturned() throws {
        let on = OnCallSwitch.effects(turningOn: true, snoozeActive: false)
        let run = try XCTUnwrap(on.firstIndex(of: .runSelfTestNow))
        let open = try XCTUnwrap(on.firstIndex(of: .openCheckWindowIfUrgent))
        let watch = try XCTUnwrap(on.firstIndex(of: .evaluateWatch))
        XCTAssertLessThan(run, open)
        XCTAssertLessThan(open, watch)
        XCTAssertEqual(on.last, .evaluateWatch)
    }

    /// The watch begins afresh before the self-test, whose report is the first it
    /// is asked about, so that a finding already standing sounds for someone who
    /// has just said they are on call.
    func testTurningOnResetsTheWatchBeforeTheSelfTestWhoseReportIsTheFirstItWatches() throws {
        let on = OnCallSwitch.effects(turningOn: true, snoozeActive: false)
        let reset = try XCTUnwrap(on.firstIndex(of: .resetWatch))
        let run = try XCTUnwrap(on.firstIndex(of: .runSelfTestNow))
        XCTAssertLessThan(reset, run)
    }

    /// Turning off asks nothing of the window and does not watch: it clears what
    /// the watch remembers, so that switching on afterwards sounds for a finding
    /// that is still standing, and opens nothing.
    func testTurningOffClearsTheWatchAndOpensNoWindowAndWatchesNothing() {
        let off = OnCallSwitch.effects(turningOn: false, snoozeActive: false)
        XCTAssertTrue(off.contains(.resetWatch))
        XCTAssertFalse(off.contains(.openCheckWindowIfUrgent))
        XCTAssertFalse(off.contains(.evaluateWatch))
    }

    // MARK: - The menu and the icon say it at once

    /// The self-test is awaited and takes seconds, in which a menu and an icon
    /// drawn from the state before the switch would say that nothing had happened.
    /// So turning on draws them from the state just saved before the self-test, and
    /// after the hold, so that the menu says what is held.
    func testTurningOnDrawsTheMenuAndTheIconAfterTheStateIsSavedAndTheHoldIsTakenAndBeforeTheSelfTest() throws {
        let on = OnCallSwitch.effects(turningOn: true, snoozeActive: false)
        let draw = try XCTUnwrap(on.firstIndex(of: .rebuildMenuAndIcon))
        XCTAssertLessThan(try XCTUnwrap(on.firstIndex(of: .save)), draw, "from the state just saved")
        XCTAssertLessThan(try XCTUnwrap(on.firstIndex(of: .holdAwake)), draw, "the menu says what is held")
        XCTAssertLessThan(draw, try XCTUnwrap(on.firstIndex(of: .runSelfTestNow)), "not after the wait")
        XCTAssertEqual(on.filter { $0 == .rebuildMenuAndIcon }.count, 1)
    }

    /// Turning off runs no self-test to end in a rebuild, so it draws them itself,
    /// last: after the hold is let go of, or the menu would go on saying it is held.
    func testTurningOffDrawsTheMenuAndTheIconLastAfterTheHoldIsLetGoOf() throws {
        let off = OnCallSwitch.effects(turningOn: false, snoozeActive: false)
        XCTAssertEqual(off.last, .rebuildMenuAndIcon)
        XCTAssertLessThan(try XCTUnwrap(off.firstIndex(of: .releaseAwake)), try XCTUnwrap(off.firstIndex(of: .rebuildMenuAndIcon)))
    }

    // MARK: - What waits for the self-test, and the mode switched off again meanwhile

    /// The self-test waits on a banner. It is the one effect that does, so it is
    /// where a list is split, and a second awaited effect would have to be named.
    func testTheSelfTestIsTheOnlyEffectThatIsAwaited() {
        XCTAssertEqual(OnCallSwitch.Effect.allCases.filter(\.isAwaited), [.runSelfTestNow])
        for turningOn in [true, false] {
            for snoozeActive in [true, false] {
                XCTAssertLessThanOrEqual(
                    OnCallSwitch.effects(turningOn: turningOn, snoozeActive: snoozeActive).filter(\.isAwaited).count, 1)
            }
        }
    }

    /// The list is carried out in two parts, up to and including the wait and then
    /// what waited, and the two parts make the whole list in its order.
    func testTurningOnIsSplitAtTheSelfTestSoThatTheWindowAndTheWatchWaitForIt() {
        XCTAssertEqual(OnCallSwitch.effectsUntilSelfTestReturns(turningOn: true, snoozeActive: false),
                       [.save, .rearmSelfTestTimer, .cancelPendingRetry, .resetHealthAlarm, .resetWatch, .holdAwake,
                        .rebuildMenuAndIcon, .runSelfTestNow])
        XCTAssertEqual(OnCallSwitch.effectsAfterSelfTestReturns(turningOn: true, snoozeActive: false, stillOn: true),
                       [.openCheckWindowIfUrgent, .evaluateWatch])
    }

    /// With a snooze running the first part gains the step that ends it and the
    /// second part is what it was: the snooze ends before the wait, and nothing
    /// that waits depends on it.
    func testTurningOnWithASnoozeRunningEndsItInTheFirstPartAndLeavesTheSecondAsItWas() {
        XCTAssertEqual(OnCallSwitch.effectsUntilSelfTestReturns(turningOn: true, snoozeActive: true),
                       [.save, .endSnooze, .rearmSelfTestTimer, .cancelPendingRetry, .resetHealthAlarm, .resetWatch,
                        .holdAwake, .rebuildMenuAndIcon, .runSelfTestNow])
        XCTAssertEqual(OnCallSwitch.effectsAfterSelfTestReturns(turningOn: true, snoozeActive: true, stillOn: true),
                       OnCallSwitch.effectsAfterSelfTestReturns(turningOn: true, snoozeActive: false, stillOn: true))
    }

    func testTheTwoPartsMakeTheWholeListInItsOrderForEitherSwitchWithAndWithoutASnooze() {
        for turningOn in [true, false] {
            for snoozeActive in [true, false] {
                XCTAssertEqual(
                    OnCallSwitch.effectsUntilSelfTestReturns(turningOn: turningOn, snoozeActive: snoozeActive)
                        + OnCallSwitch.effectsAfterSelfTestReturns(turningOn: turningOn, snoozeActive: snoozeActive,
                                                                   stillOn: true),
                    OnCallSwitch.effects(turningOn: turningOn, snoozeActive: snoozeActive),
                    "turning \(turningOn ? "on" : "off"), snooze running \(snoozeActive)")
            }
        }
    }

    /// Turning off awaits nothing, so all of it is carried out at once and nothing
    /// waits, whether or not the mode is on when it is asked.
    func testTurningOffHasNothingThatWaits() {
        for snoozeActive in [true, false] {
            XCTAssertEqual(OnCallSwitch.effectsUntilSelfTestReturns(turningOn: false, snoozeActive: snoozeActive),
                           OnCallSwitch.effects(turningOn: false, snoozeActive: snoozeActive))
            for stillOn in [true, false] {
                XCTAssertEqual(
                    OnCallSwitch.effectsAfterSelfTestReturns(turningOn: false, snoozeActive: snoozeActive, stillOn: stillOn),
                    [])
            }
        }
    }

    /// The user can switch the mode off in the seconds the self-test takes. A check
    /// window opened for a mode that is off again is a window nobody asked for, and
    /// a watch begun for it begins nothing, so nothing that waited runs.
    func testNothingThatWaitedForTheSelfTestRunsIfTheModeWasSwitchedOffMeanwhile() {
        for snoozeActive in [true, false] {
            XCTAssertEqual(OnCallSwitch.effectsAfterSelfTestReturns(turningOn: true, snoozeActive: snoozeActive, stillOn: false), [])
            XCTAssertFalse(
                OnCallSwitch.effectsAfterSelfTestReturns(turningOn: true, snoozeActive: snoozeActive, stillOn: true).isEmpty)
        }
    }

    /// What is carried out before the wait does not depend on it, and includes the
    /// self-test whose return is waited for.
    func testTheFirstPartEndsInTheSelfTestAndHoldsNeitherTheWindowNorTheWatch() throws {
        for snoozeActive in [true, false] {
            let first = OnCallSwitch.effectsUntilSelfTestReturns(turningOn: true, snoozeActive: snoozeActive)
            XCTAssertEqual(first.last, .runSelfTestNow)
            XCTAssertFalse(first.contains(.openCheckWindowIfUrgent))
            XCTAssertFalse(first.contains(.evaluateWatch))
        }
    }

    func testEachListNamesEachStepOnce() {
        for turningOn in [true, false] {
            for snoozeActive in [true, false] {
                let effects = OnCallSwitch.effects(turningOn: turningOn, snoozeActive: snoozeActive)
                XCTAssertEqual(effects.count, Set(effects).count,
                               "turning \(turningOn ? "on" : "off"), snooze running \(snoozeActive)")
            }
        }
    }

    // MARK: - A snooze that is running (O10)

    /// Switching on says the user is on call, which a snooze contradicts, so it
    /// ends. It comes straight after the state is saved and changes nothing else:
    /// the list without it is the list there was.
    func testTurningOnWithASnoozeRunningEndsItRightAfterTheStateIsSavedAndChangesNothingElse() {
        let without = OnCallSwitch.effects(turningOn: true, snoozeActive: false)
        let with = OnCallSwitch.effects(turningOn: true, snoozeActive: true)
        XCTAssertEqual(with,
                       [.save, .endSnooze, .rearmSelfTestTimer, .cancelPendingRetry, .resetHealthAlarm, .resetWatch,
                        .holdAwake, .rebuildMenuAndIcon, .runSelfTestNow, .openCheckWindowIfUrgent, .evaluateWatch])
        XCTAssertEqual(with.filter { $0 != .endSnooze }, without)
        XCTAssertEqual(with.filter { $0 == .endSnooze }.count, 1)
    }

    func testTurningOnWithNoSnoozeRunningHasNoStepThatEndsOne() {
        XCTAssertFalse(OnCallSwitch.effects(turningOn: true, snoozeActive: false).contains(.endSnooze))
    }

    /// Someone who starts a snooze while on call and then switches the mode off
    /// keeps the snooze: turning off is the same list whether or not one runs.
    func testTurningOffNeverTouchesASnoozeWhetherOneIsRunningOrNot() {
        XCTAssertEqual(OnCallSwitch.effects(turningOn: false, snoozeActive: true),
                       OnCallSwitch.effects(turningOn: false, snoozeActive: false))
        XCTAssertFalse(OnCallSwitch.effects(turningOn: false, snoozeActive: true).contains(.endSnooze))
        XCTAssertEqual(OnCallSwitch.effectsUntilSelfTestReturns(turningOn: false, snoozeActive: true),
                       OnCallSwitch.effects(turningOn: false, snoozeActive: false))
    }

    /// The menu and the icon are drawn from the state once the snooze is gone, or
    /// they would show a moon over a mode that says the user is on call. And it
    /// ends before the self-test, which waits on a banner: a snooze that outlived
    /// a wait of seconds would be a snooze the user had already ended.
    func testTheSnoozeEndsBeforeTheMenuAndTheIconAreDrawnAndBeforeTheSelfTestWhoseRunIsAwaited() throws {
        let on = OnCallSwitch.effects(turningOn: true, snoozeActive: true)
        let end = try XCTUnwrap(on.firstIndex(of: .endSnooze))
        XCTAssertLessThan(try XCTUnwrap(on.firstIndex(of: .save)), end, "after the mode is saved as on")
        XCTAssertLessThan(end, try XCTUnwrap(on.firstIndex(of: .rebuildMenuAndIcon)))
        XCTAssertLessThan(end, try XCTUnwrap(on.firstIndex(of: .runSelfTestNow)))
        XCTAssertFalse(OnCallSwitch.effectsAfterSelfTestReturns(turningOn: true, snoozeActive: true, stillOn: true)
            .contains(.endSnooze), "it is not one of what waits")
    }

    /// The one step that touches a snooze ends it. Nothing in the list dismisses
    /// what a snooze held or announces it, so what it held stays and the user is
    /// told nothing aloud: they have just clicked, and the menu says what happened.
    /// This holds the whole set of steps, so a step added to the switch has to be
    /// named here, where its name is read.
    func testNoStepOfTheSwitchDismissesASummaryOrAnnouncesOne() {
        XCTAssertEqual(Set(OnCallSwitch.Effect.allCases),
                       [.save, .endSnooze, .rearmSelfTestTimer, .cancelPendingRetry, .resetHealthAlarm, .holdAwake,
                        .releaseAwake, .rebuildMenuAndIcon, .runSelfTestNow, .resetWatch, .openCheckWindowIfUrgent,
                        .evaluateWatch])
    }

    // MARK: - Whether the window opens at switch-on

    private func finding(_ kind: OnCallCheck.Finding.Kind) -> OnCallCheck.Finding {
        OnCallCheck.Finding(kind: kind, text: "x")
    }

    func testTheWindowOpensAtSwitchOnWhenAnyFindingIsUrgent() {
        XCTAssertTrue(OnCallCheck.shouldOpenWindow([finding(.notVerifiedYet)]))
        XCTAssertTrue(OnCallCheck.shouldOpenWindow([finding(.focus), finding(.loginItemOff), finding(.sleep)]),
                      "one urgent finding among advisories")
        for kind in OnCallCheck.Finding.Kind.allCases where kind.isUrgent {
            XCTAssertTrue(OnCallCheck.shouldOpenWindow([finding(.focus), finding(kind)]), "\(kind)")
        }
    }

    func testTheWindowDoesNotOpenAtSwitchOnWithNoFindingAndWithAdvisoriesAlone() {
        XCTAssertFalse(OnCallCheck.shouldOpenWindow([]))
        XCTAssertFalse(OnCallCheck.shouldOpenWindow([finding(.focus), finding(.sleep), finding(.noSoundOrShortcut)]))
    }
}

/// The step that ends a snooze, carried out against the real controller, as the
/// app's arm for it will (M5 plan, O10, Ruling 10). Nothing sounds, saves to the
/// real preferences or waits on a real clock: time is the manual scheduler and
/// the preferences are a dictionary.
@MainActor
final class OnCallSwitchSnoozeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let ruleID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    private var clock: ManualScheduler!
    private var preferences: [String: Any] = [:]
    private var announced = 0
    /// How many times the step that ends a snooze was carried out.
    private var ended = 0
    private var snooze: SnoozeController!

    override func setUp() {
        clock = ManualScheduler(start: t0)
        preferences = [:]
        announced = 0
        ended = 0
        snooze = SnoozeController(scheduler: clock, storedUntil: nil, storedHeld: nil,
                                  save: { [unowned self] key, value in preferences[key] = value },
                                  changed: {}, announce: { [unowned self] in announced += 1 })
    }

    /// A rule a snooze may hold.
    private var pager: Rule {
        Rule(id: ruleID, name: "On-call mentions", condition: .field(.app, .equals, "Microsoft Teams"),
             alert: .sound(name: "Glass", gainDB: 0), quietWhenSnoozed: true)
    }

    /// What the app's `carryOut` does with each effect of the switch that touches
    /// a snooze: ends it for `.endSnooze`, and touches it for no other.
    private func carryOut(_ effects: [OnCallSwitch.Effect]) {
        for effect in effects where effect == .endSnooze {
            ended += 1
            snooze.end()
        }
    }

    func testTurningOnEndsTheSnoozeKeepsWhatItHeldAndAnnouncesNothing() {
        snooze.start(.oneHour)
        XCTAssertTrue(snooze.holds(pager))
        XCTAssertTrue(snooze.holds(pager))
        XCTAssertTrue(snooze.isActive)

        carryOut(OnCallSwitch.effects(turningOn: true, snoozeActive: snooze.isActive))

        XCTAssertEqual(ended, 1, "the list ends it, once")
        XCTAssertFalse(snooze.isActive)
        XCTAssertNil(snooze.endsAt)
        XCTAssertEqual(snooze.summary.counts, [ruleID: 2], "what it held is kept for the user to see")
        XCTAssertNil(preferences[SnoozeController.untilKey], "and the saved end is gone, so a relaunch is not snoozed")
        XCTAssertNotNil(preferences[SnoozeController.heldKey], "and the held summary is still saved")
        XCTAssertEqual(announced, 0, "ending it is the user's own act")
        // Nor is it announced when the end it would have had comes round.
        clock.advance(by: 2 * 60 * 60)
        XCTAssertEqual(announced, 0)
        XCTAssertEqual(snooze.summary.counts, [ruleID: 2])
    }

    func testTurningOnWithNoSnoozeTouchesNothing() {
        XCTAssertFalse(snooze.isActive)
        let before = snooze.summary
        carryOut(OnCallSwitch.effects(turningOn: true, snoozeActive: snooze.isActive))
        XCTAssertEqual(ended, 0, "the list has no step that ends one")
        XCTAssertFalse(snooze.isActive)
        XCTAssertEqual(snooze.summary, before)
        XCTAssertTrue(preferences.isEmpty, "nothing was saved")
        XCTAssertEqual(announced, 0)
    }

    func testTurningOffLeavesARunningSnoozeRunning() {
        snooze.start(.thirtyMinutes)
        XCTAssertTrue(snooze.holds(pager))
        let endsAt = snooze.endsAt

        carryOut(OnCallSwitch.effects(turningOn: false, snoozeActive: snooze.isActive))

        XCTAssertEqual(ended, 0, "turning off ends nothing")
        XCTAssertTrue(snooze.isActive)
        XCTAssertEqual(snooze.endsAt, endsAt)
        XCTAssertEqual(snooze.summary.counts, [ruleID: 1])
        XCTAssertEqual(announced, 0)
    }
}

/// What launch does with the state it restored (M5 plan, O7): the hold is taken
/// at once when on-call mode was on, before capture starts, since nothing has
/// switched the mode on in this run and so nothing else would take it.
final class OnCallLaunchTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testARestoredOnCallStateHoldsTheMacAwake() {
        XCTAssertEqual(OnCallSwitch.launchEffects(restored: .on(since: now.addingTimeInterval(-3600))), [.holdAwake])
    }

    func testARestoredOffStateHoldsNothing() {
        XCTAssertEqual(OnCallSwitch.launchEffects(restored: .off), [])
    }

    /// A saved value that cannot be read as a time reads as on (Ruling 7), and a
    /// Mac that idle-sleeps while someone is on call captures nothing, so it is
    /// held as any other on-call state is.
    func testAnOnCallStateWhoseTimeIsNotKnownHoldsTheMacAwakeToo() {
        XCTAssertEqual(OnCallSwitch.launchEffects(restored: .on(since: nil)), [.holdAwake])
    }

    /// The decision follows what the preferences gave and not only a state built
    /// by hand: absent is off and holds nothing, and everything else is on, a
    /// number, a string, a Boolean and a negative number alike.
    func testWhatThePreferencesGaveDecidesTheHoldAsItDecidesTheState() {
        XCTAssertEqual(OnCallSwitch.launchEffects(restored: OnCallState(stored: nil, now: now)), [])
        let stored: [Any] = [now.timeIntervalSince1970 - 60, 0, "yesterday", true, -5.0, Double.nan]
        for value in stored {
            XCTAssertEqual(OnCallSwitch.launchEffects(restored: OnCallState(stored: value, now: now)),
                           [.holdAwake], "\(value)")
        }
    }
}
