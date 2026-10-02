import XCTest
@testable import NotificationCore

/// The reasons the app's two holds against idle sleep give the system (M5 plan,
/// Ruling 18, O7). `pmset -g assertions` prints them, and the live check of the
/// on-call hold finds the hold by its reason, so the words are held exactly.
final class PowerHoldTextTests: XCTestCase {
    /// The escalation's hold had these words before they moved here, so moving
    /// them changed nothing the system shows.
    func testTheEscalationsReasonIsTheWordsItHadBefore() {
        XCTAssertEqual(PowerHoldText.escalationReason, "An alert is still escalating")
    }

    func testTheOnCallReasonIsTheWordsThePlanGivesIt() {
        XCTAssertEqual(PowerHoldText.onCallReason, "On-call mode is on")
    }

    /// Two holds with one reason could not be told apart in what the system
    /// prints, and a check that one was let go of and the other was not would
    /// have nothing to read it by.
    func testTheTwoReasonsAreNotAlikeAndNeitherIsEmpty() {
        XCTAssertNotEqual(PowerHoldText.escalationReason, PowerHoldText.onCallReason)
        XCTAssertFalse(PowerHoldText.escalationReason.isEmpty)
        XCTAssertFalse(PowerHoldText.onCallReason.isEmpty)
    }
}
