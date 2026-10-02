import XCTest
@testable import NotificationCore

/// What switching on-call mode does, as the list the app carries out (M5 plan,
/// Ruling 10). The lists here are those of the commit that builds the state and
/// the timers; the commits that hold the Mac awake, reset the alarm and open the
/// check window add to them, and each adds its own steps to these tests.
final class OnCallSwitchTests: XCTestCase {
    func testTurningOnSavesArmsTheTimerDropsAPendingRetryAndRunsASelfTestInThatOrder() {
        XCTAssertEqual(OnCallSwitch.effects(turningOn: true),
                       [.save, .rearmSelfTestTimer, .cancelPendingRetry, .runSelfTestNow])
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
