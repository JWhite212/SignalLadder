import XCTest
@testable import NotificationCore

/// What switching on-call mode does, as the list the app carries out (M5 plan,
/// Ruling 10). The lists here are those of the commits that build the state and
/// the timers and that reset the health alarm; the commits that hold the Mac
/// awake and open the check window add to them, and each adds its own steps to
/// these tests.
final class OnCallSwitchTests: XCTestCase {
    func testTurningOnSavesArmsTheTimerDropsAPendingRetryResetsTheAlarmAndRunsASelfTestInThatOrder() {
        XCTAssertEqual(OnCallSwitch.effects(turningOn: true),
                       [.save, .rearmSelfTestTimer, .cancelPendingRetry, .resetHealthAlarm, .runSelfTestNow])
    }

    func testTurningOffSavesAndArmsTheTimerAndNothingElse() {
        XCTAssertEqual(OnCallSwitch.effects(turningOn: false), [.save, .rearmSelfTestTimer])
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
