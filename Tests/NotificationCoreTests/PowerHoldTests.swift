import XCTest
@testable import NotificationCore

/// Which reason and which options each of the app's two holds against idle
/// sleep gets (M5 plan, O7, Ruling 10). The app target makes a hold from one of
/// these cases and decides nothing about it, so this is where the pairing is
/// pinned: a hold with the other's reason is listed by `pmset -g assertions`
/// under words that say the wrong thing, and one that holds the display as well
/// keeps a screen lit for as long as on-call mode is on.
///
/// These tests read two values and take no hold: nothing here asks the system to
/// keep a Mac awake.
final class PowerHoldTests: XCTestCase {
    func testThereAreTwoHoldsAndTheseAreThey() {
        XCTAssertEqual(PowerHold.allCases, [.escalation, .onCall])
    }

    // MARK: What each is called

    func testEachHoldIsListedUnderItsOwnReasonAndNotTheOthers() {
        XCTAssertEqual(PowerHold.escalation.reason, PowerHoldText.escalationReason)
        XCTAssertEqual(PowerHold.onCall.reason, PowerHoldText.onCallReason)
    }

    func testNoTwoHoldsShareAReasonAndNoneIsEmpty() {
        let reasons = PowerHold.allCases.map(\.reason)
        XCTAssertEqual(Set(reasons).count, reasons.count)
        XCTAssertFalse(reasons.contains(""))
    }

    // MARK: What each holds against

    /// The one the live check of the hold is made on (O7): idle system sleep and
    /// nothing else. `.userInitiated` is a wider set that also turns off sudden
    /// and automatic termination, which on-call mode has no reason to do.
    func testTheOnCallHoldHoldsAgainstIdleSystemSleepAndNothingElse() {
        XCTAssertEqual(PowerHold.onCall.options, [.idleSystemSleepDisabled])
    }

    /// A Mac held awake for as long as someone is on call must still be free to
    /// turn its display off, so the on-call hold says nothing of the display.
    func testTheOnCallHoldDoesNotHoldTheDisplay() {
        XCTAssertTrue(PowerHold.onCall.options.contains(.idleSystemSleepDisabled))
        XCTAssertFalse(PowerHold.onCall.options.contains(.idleDisplaySleepDisabled))
    }

    /// The escalation's hold is as it was before the second hold existed.
    func testTheEscalationsHoldHoldsAsItAlwaysDid() {
        XCTAssertEqual(PowerHold.escalation.options, [.userInitiated])
    }

    func testNeitherHoldHoldsTheDisplay() {
        for hold in PowerHold.allCases {
            XCTAssertFalse(hold.options.contains(.idleDisplaySleepDisabled), "\(hold)")
        }
    }

    /// Both stop a Mac idle-sleeping, which is what each is for: the escalation's
    /// until its last tier has fired, on-call mode's for as long as the mode is on.
    func testBothHoldsStopTheMacIdleSleeping() {
        for hold in PowerHold.allCases {
            XCTAssertTrue(hold.options.contains(.idleSystemSleepDisabled), "\(hold)")
        }
    }
}
