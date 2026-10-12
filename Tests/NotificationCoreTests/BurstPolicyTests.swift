import XCTest
@testable import NotificationCore

/// The three timings of a burst (M5 plan, Ruling 14, O11), at the values the
/// owner's answers give by default.
final class BurstPolicyTests: XCTestCase {
    func testTheStandardTimingsAreTheOnesTheDefaultAnswersGive() {
        XCTAssertEqual(BurstPolicy.standard.quietGap, 60,
                       "O11a: a match within 60 seconds of the last joins a ladder that does not repeat")
        XCTAssertEqual(BurstPolicy.standard.silentJoinWindow, 60,
                       "O11a: a repeat due within 60 seconds, or one interval if shorter, stands in for a match's alert")
        XCTAssertEqual(BurstPolicy.standard.repageTime, 10 * 60, "O11b: a long escalation pages again after 10 minutes")
    }

    func testAPolicyHoldsWhatItIsGivenAndNotTheStandardOnes() {
        let policy = BurstPolicy(quietGap: 5, silentJoinWindow: 7, repageTime: 11)
        XCTAssertEqual(policy.quietGap, 5)
        XCTAssertEqual(policy.silentJoinWindow, 7)
        XCTAssertEqual(policy.repageTime, 11)
        XCTAssertNotEqual(policy, BurstPolicy.standard)
    }

    func testEachTimingIsItsOwnAndNoTwoAreMistakenForOneAnother() {
        // The quiet gap and the silent-join window are both 60 on the default,
        // so a swap between them would pass the test above. Moving one at a time
        // shows each is read from its own place.
        let standard = BurstPolicy.standard
        let gap = BurstPolicy(quietGap: 1, silentJoinWindow: standard.silentJoinWindow, repageTime: standard.repageTime)
        let window = BurstPolicy(quietGap: standard.quietGap, silentJoinWindow: 2, repageTime: standard.repageTime)
        let repage = BurstPolicy(quietGap: standard.quietGap, silentJoinWindow: standard.silentJoinWindow, repageTime: 3)
        XCTAssertEqual([gap.quietGap, gap.silentJoinWindow, gap.repageTime], [1, 60, 600])
        XCTAssertEqual([window.quietGap, window.silentJoinWindow, window.repageTime], [60, 2, 600])
        XCTAssertEqual([repage.quietGap, repage.silentJoinWindow, repage.repageTime], [60, 60, 3])
    }
}
