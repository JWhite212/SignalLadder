import XCTest
@testable import NotificationCore

/// The fake clock every coordinator test rests on, checked on its own.
@MainActor
final class ManualSchedulerTests: XCTestCase {
    func testTimersFireInDueOrderAndEarliestScheduledFirstOnATie() {
        let clock = ManualScheduler()
        var fired: [String] = []
        _ = clock.schedule(after: 20) { fired.append("b") }
        _ = clock.schedule(after: 10) { fired.append("a") }
        _ = clock.schedule(after: 20) { fired.append("c") }
        clock.advance(by: 30)
        XCTAssertEqual(fired, ["a", "b", "c"])
    }

    func testATimerRunsAtItsDueTimeWithBothClocksThere() {
        let clock = ManualScheduler()
        var seen: (Date, TimeInterval)?
        _ = clock.schedule(after: 10) { seen = (clock.now(), clock.awakeTime()) }
        clock.advance(by: 30)
        XCTAssertEqual(seen?.1, 10)
        XCTAssertEqual(seen?.0, Date(timeIntervalSince1970: 1_790_000_010))
        XCTAssertEqual(clock.awakeTime(), 30)
    }

    func testATimerScheduledByAnotherFiresInTheSameAdvance() {
        let clock = ManualScheduler()
        var fired = 0
        _ = clock.schedule(after: 10) { _ = clock.schedule(after: 10) { fired += 1 } }
        clock.advance(by: 25)
        XCTAssertEqual(fired, 1)
    }

    func testSleepMovesOnlyTheWallClockAndFiresNothing() {
        let clock = ManualScheduler()
        var fired = 0
        _ = clock.schedule(after: 10) { fired += 1 }
        clock.sleep(for: 100)
        XCTAssertEqual(fired, 0)
        XCTAssertEqual(clock.awakeTime(), 0)
        XCTAssertEqual(clock.now(), Date(timeIntervalSince1970: 1_790_000_100))
    }

    func testACancelledTimerNeverFiresUntilRunLate() {
        let clock = ManualScheduler()
        var fired = 0
        clock.cancel(clock.schedule(after: 10) { fired += 1 })
        clock.advance(by: 30)
        XCTAssertEqual(fired, 0)
        XCTAssertEqual(clock.runCancelled(), 1)
        XCTAssertEqual(fired, 1)
    }

    func testRefiringDeliversTheLastTimerOnceMore() {
        let clock = ManualScheduler()
        var fired = 0
        _ = clock.schedule(after: 10) { fired += 1 }
        clock.advance(by: 10)
        XCTAssertEqual(clock.refireLast(), 1)
        XCTAssertEqual(fired, 2)
    }

    func testLatenessDelaysEveryTimer() {
        let clock = ManualScheduler()
        clock.lateness = 0.5
        var fired = 0
        _ = clock.schedule(after: 10) { fired += 1 }
        clock.advance(by: 10.4)
        XCTAssertEqual(fired, 0)
        clock.advance(by: 0.1)
        XCTAssertEqual(fired, 1)
    }
}
