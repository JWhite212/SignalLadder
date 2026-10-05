import XCTest
@testable import NotificationCore

/// What switching on-call mode does, as the list the app carries out (M5 plan,
/// Ruling 10): the state, the timers, the health alarm and the watch, the hold
/// against sleep, the menu and the icon, the self-test, and the check window.
final class OnCallSwitchTests: XCTestCase {
    func testTurningOnSavesArmsTheTimerDropsAPendingRetryResetsTheAlarmAndTheWatchHoldsTheMacAwakeDrawsTheMenuRunsASelfTestAndThenOpensTheWindowAndWatchesInThatOrder() {
        XCTAssertEqual(OnCallSwitch.effects(turningOn: true),
                       [.save, .rearmSelfTestTimer, .cancelPendingRetry, .resetHealthAlarm, .resetWatch, .holdAwake,
                        .rebuildMenuAndIcon, .runSelfTestNow, .openCheckWindowIfUrgent, .evaluateWatch])
    }

    func testTurningOffSavesArmsTheTimerLetsGoOfTheHoldClearsTheWatchAndDrawsTheMenuAndNothingElse() {
        XCTAssertEqual(OnCallSwitch.effects(turningOn: false),
                       [.save, .rearmSelfTestTimer, .releaseAwake, .resetWatch, .rebuildMenuAndIcon])
    }

    /// A failed self-test promises "It will retry in a minute." Turning off runs
    /// no self-test in the retry's place, so cancelling it would leave a degraded
    /// state waiting up to half an hour under words that say otherwise (Ruling 8).
    func testTurningOffKeepsAPendingRetryAndRunsNoSelfTest() {
        let off = OnCallSwitch.effects(turningOn: false)
        XCTAssertFalse(off.contains(.cancelPendingRetry))
        XCTAssertFalse(off.contains(.runSelfTestNow))
    }

    /// Turning on says that the user is on call, so a fault already standing is
    /// told afresh: the alarm begins again, and it does so before the self-test
    /// whose report is the first it is asked about.
    func testTurningOnResetsTheHealthAlarmBeforeTheSelfTestThatReportsToIt() throws {
        let on = OnCallSwitch.effects(turningOn: true)
        let reset = try XCTUnwrap(on.firstIndex(of: .resetHealthAlarm))
        let run = try XCTUnwrap(on.firstIndex(of: .runSelfTestNow))
        XCTAssertLessThan(reset, run)
    }

    /// Turning off leaves the alarm's state alone (Ruling 8): what stood on call
    /// is not told again, and one reset would begin the once-per-change rule over.
    func testTurningOffLeavesTheHealthAlarmsStateAlone() {
        XCTAssertFalse(OnCallSwitch.effects(turningOn: false).contains(.resetHealthAlarm))
    }

    /// A self-test run at once takes a retry's place, so turning on drops it. And
    /// it drops it first: the run is awaited, and one that fails arms a retry of
    /// its own, which a cancel after it would take away.
    func testTurningOnDropsAPendingRetryBeforeTheSelfTestThatReplacesItRuns() throws {
        let on = OnCallSwitch.effects(turningOn: true)
        let cancel = try XCTUnwrap(on.firstIndex(of: .cancelPendingRetry))
        let run = try XCTUnwrap(on.firstIndex(of: .runSelfTestNow))
        XCTAssertLessThan(cancel, run)
    }

    /// The hold is taken before the self-test is run, because the run is awaited:
    /// a step after it would wait for the banner to come back, and the Mac would
    /// be free to sleep until it did.
    func testTurningOnHoldsTheMacAwakeBeforeTheSelfTestWhoseRunIsAwaited() throws {
        let on = OnCallSwitch.effects(turningOn: true)
        let hold = try XCTUnwrap(on.firstIndex(of: .holdAwake))
        let run = try XCTUnwrap(on.firstIndex(of: .runSelfTestNow))
        XCTAssertLessThan(hold, run)
    }

    /// Only turning on takes the hold and only turning off lets go of it. A list
    /// that did both would end the hold the moment it began, and one that did
    /// neither would leave a Mac held after the user said they were off call.
    func testOnlyTurningOnHoldsAndOnlyTurningOffReleases() {
        let on = OnCallSwitch.effects(turningOn: true)
        let off = OnCallSwitch.effects(turningOn: false)
        XCTAssertTrue(on.contains(.holdAwake))
        XCTAssertFalse(on.contains(.releaseAwake), "turning on lets go of the hold it has just taken")
        XCTAssertTrue(off.contains(.releaseAwake))
        XCTAssertFalse(off.contains(.holdAwake), "turning off takes a hold")
    }

    /// The timer is armed at the interval of the state, and the state is the one
    /// just saved.
    func testEitherSwitchSavesBeforeItArmsTheTimer() throws {
        for turningOn in [true, false] {
            let effects = OnCallSwitch.effects(turningOn: turningOn)
            let save = try XCTUnwrap(effects.firstIndex(of: .save))
            let arm = try XCTUnwrap(effects.firstIndex(of: .rearmSelfTestTimer))
            XCTAssertLessThan(save, arm, "turning \(turningOn ? "on" : "off")")
        }
    }

    /// The window is asked about once, when the self-test that turning on started
    /// has returned: a check made before it would say that nothing had been
    /// verified, which is true of every switch-on.
    func testTurningOnAsksAboutTheWindowAndWatchesOnlyAfterTheSelfTestHasReturned() throws {
        let on = OnCallSwitch.effects(turningOn: true)
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
        let on = OnCallSwitch.effects(turningOn: true)
        let reset = try XCTUnwrap(on.firstIndex(of: .resetWatch))
        let run = try XCTUnwrap(on.firstIndex(of: .runSelfTestNow))
        XCTAssertLessThan(reset, run)
    }

    /// Turning off asks nothing of the window and does not watch: it clears what
    /// the watch remembers, so that switching on afterwards sounds for a finding
    /// that is still standing, and opens nothing.
    func testTurningOffClearsTheWatchAndOpensNoWindowAndWatchesNothing() {
        let off = OnCallSwitch.effects(turningOn: false)
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
        let on = OnCallSwitch.effects(turningOn: true)
        let draw = try XCTUnwrap(on.firstIndex(of: .rebuildMenuAndIcon))
        XCTAssertLessThan(try XCTUnwrap(on.firstIndex(of: .save)), draw, "from the state just saved")
        XCTAssertLessThan(try XCTUnwrap(on.firstIndex(of: .holdAwake)), draw, "the menu says what is held")
        XCTAssertLessThan(draw, try XCTUnwrap(on.firstIndex(of: .runSelfTestNow)), "not after the wait")
        XCTAssertEqual(on.filter { $0 == .rebuildMenuAndIcon }.count, 1)
    }

    /// Turning off runs no self-test to end in a rebuild, so it draws them itself,
    /// last: after the hold is let go of, or the menu would go on saying it is held.
    func testTurningOffDrawsTheMenuAndTheIconLastAfterTheHoldIsLetGoOf() throws {
        let off = OnCallSwitch.effects(turningOn: false)
        XCTAssertEqual(off.last, .rebuildMenuAndIcon)
        XCTAssertLessThan(try XCTUnwrap(off.firstIndex(of: .releaseAwake)), try XCTUnwrap(off.firstIndex(of: .rebuildMenuAndIcon)))
    }

    // MARK: - What waits for the self-test, and the mode switched off again meanwhile

    /// The self-test waits on a banner. It is the one effect that does, so it is
    /// where a list is split, and a second awaited effect would have to be named.
    func testTheSelfTestIsTheOnlyEffectThatIsAwaited() {
        XCTAssertEqual(OnCallSwitch.Effect.allCases.filter(\.isAwaited), [.runSelfTestNow])
        for turningOn in [true, false] {
            XCTAssertLessThanOrEqual(OnCallSwitch.effects(turningOn: turningOn).filter(\.isAwaited).count, 1)
        }
    }

    /// The list is carried out in two parts, up to and including the wait and then
    /// what waited, and the two parts make the whole list in its order.
    func testTurningOnIsSplitAtTheSelfTestSoThatTheWindowAndTheWatchWaitForIt() {
        XCTAssertEqual(OnCallSwitch.effectsUntilSelfTestReturns(turningOn: true),
                       [.save, .rearmSelfTestTimer, .cancelPendingRetry, .resetHealthAlarm, .resetWatch, .holdAwake,
                        .rebuildMenuAndIcon, .runSelfTestNow])
        XCTAssertEqual(OnCallSwitch.effectsAfterSelfTestReturns(turningOn: true, stillOn: true),
                       [.openCheckWindowIfUrgent, .evaluateWatch])
    }

    func testTheTwoPartsMakeTheWholeListInItsOrderForEitherSwitch() {
        for turningOn in [true, false] {
            XCTAssertEqual(OnCallSwitch.effectsUntilSelfTestReturns(turningOn: turningOn)
                           + OnCallSwitch.effectsAfterSelfTestReturns(turningOn: turningOn, stillOn: true),
                           OnCallSwitch.effects(turningOn: turningOn), "turning \(turningOn ? "on" : "off")")
        }
    }

    /// Turning off awaits nothing, so all of it is carried out at once and nothing
    /// waits, whether or not the mode is on when it is asked.
    func testTurningOffHasNothingThatWaits() {
        XCTAssertEqual(OnCallSwitch.effectsUntilSelfTestReturns(turningOn: false), OnCallSwitch.effects(turningOn: false))
        for stillOn in [true, false] {
            XCTAssertEqual(OnCallSwitch.effectsAfterSelfTestReturns(turningOn: false, stillOn: stillOn), [])
        }
    }

    /// The user can switch the mode off in the seconds the self-test takes. A check
    /// window opened for a mode that is off again is a window nobody asked for, and
    /// a watch begun for it begins nothing, so nothing that waited runs.
    func testNothingThatWaitedForTheSelfTestRunsIfTheModeWasSwitchedOffMeanwhile() {
        XCTAssertEqual(OnCallSwitch.effectsAfterSelfTestReturns(turningOn: true, stillOn: false), [])
        XCTAssertFalse(OnCallSwitch.effectsAfterSelfTestReturns(turningOn: true, stillOn: true).isEmpty)
    }

    /// What is carried out before the wait does not depend on it, and includes the
    /// self-test whose return is waited for.
    func testTheFirstPartEndsInTheSelfTestAndHoldsNeitherTheWindowNorTheWatch() throws {
        let first = OnCallSwitch.effectsUntilSelfTestReturns(turningOn: true)
        XCTAssertEqual(first.last, .runSelfTestNow)
        XCTAssertFalse(first.contains(.openCheckWindowIfUrgent))
        XCTAssertFalse(first.contains(.evaluateWatch))
    }

    func testEachListNamesEachStepOnce() {
        for turningOn in [true, false] {
            let effects = OnCallSwitch.effects(turningOn: turningOn)
            XCTAssertEqual(effects.count, Set(effects).count, "turning \(turningOn ? "on" : "off")")
        }
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
