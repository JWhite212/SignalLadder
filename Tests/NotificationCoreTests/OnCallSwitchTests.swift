import XCTest
@testable import NotificationCore

/// What switching on-call mode does, as the list the app carries out (M5 plan,
/// Ruling 10). The lists here are those of the commits that build the state and
/// the timers, that reset the health alarm and that hold the Mac awake; the
/// commit that opens the check window adds to them, and adds its own steps to
/// these tests.
final class OnCallSwitchTests: XCTestCase {
    func testTurningOnSavesArmsTheTimerDropsAPendingRetryResetsTheAlarmHoldsTheMacAwakeAndRunsASelfTestInThatOrder() {
        XCTAssertEqual(OnCallSwitch.effects(turningOn: true),
                       [.save, .rearmSelfTestTimer, .cancelPendingRetry, .resetHealthAlarm, .holdAwake, .runSelfTestNow])
    }

    func testTurningOffSavesArmsTheTimerAndLetsGoOfTheHoldAndNothingElse() {
        XCTAssertEqual(OnCallSwitch.effects(turningOn: false), [.save, .rearmSelfTestTimer, .releaseAwake])
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

    func testEachListNamesEachStepOnce() {
        for turningOn in [true, false] {
            let effects = OnCallSwitch.effects(turningOn: turningOn)
            XCTAssertEqual(effects.count, Set(effects).count, "turning \(turningOn ? "on" : "off")")
        }
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
