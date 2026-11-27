import XCTest
@testable import NotificationCore

/// The numbers renders are asked for with, so that a result that is not the newest is dropped and the window
/// can say it is catching up (sound editor plan, Ruling 6).
final class SoundRenderTicketsTests: XCTestCase {
    func testNothingHasBeenAskedForAtFirstAndSoNothingIsCatchingUp() {
        let tickets = SoundRenderTickets()
        XCTAssertFalse(tickets.isCatchingUp)
    }

    func testTheNumbersCountUpFromOne() {
        var tickets = SoundRenderTickets()
        XCTAssertEqual(tickets.request(), 1)
        XCTAssertEqual(tickets.request(), 2)
        XCTAssertEqual(tickets.request(), 3)
    }

    func testARenderIsUnderWayFromBeingAskedForUntilItsResultIsTaken() {
        var tickets = SoundRenderTickets()
        let first = tickets.request()
        XCTAssertTrue(tickets.isCatchingUp)
        XCTAssertTrue(tickets.accept(first))
        XCTAssertFalse(tickets.isCatchingUp)
    }

    func testAResultThatIsNotTheNewestIsDroppedAndTheNewestIsTaken() {
        var tickets = SoundRenderTickets()
        let first = tickets.request()
        let second = tickets.request()
        XCTAssertFalse(tickets.accept(first), "a newer one has been asked for since")
        XCTAssertTrue(tickets.isCatchingUp, "and the window is still waiting for it")
        XCTAssertTrue(tickets.accept(second))
        XCTAssertFalse(tickets.isCatchingUp)
    }

    func testAnOlderResultIsDroppedEvenWhenItComesLast() {
        var tickets = SoundRenderTickets()
        let first = tickets.request()
        let second = tickets.request()
        XCTAssertTrue(tickets.accept(second))
        XCTAssertFalse(tickets.accept(first), "it is older than what the window already has")
        XCTAssertFalse(tickets.isCatchingUp)
    }

    func testTheSameResultIsNotTakenTwice() {
        var tickets = SoundRenderTickets()
        let first = tickets.request()
        XCTAssertTrue(tickets.accept(first))
        XCTAssertFalse(tickets.accept(first))
    }

    func testANumberNeverAskedForIsNeverTaken() {
        var tickets = SoundRenderTickets()
        XCTAssertFalse(tickets.accept(1))
        let first = tickets.request()
        XCTAssertFalse(tickets.accept(first + 1))
        XCTAssertFalse(tickets.accept(0))
        XCTAssertTrue(tickets.accept(first))
    }

    func testAfterItIsCancelledNoResultIsTakenAndNothingIsCatchingUp() {
        var tickets = SoundRenderTickets()
        let first = tickets.request()
        tickets.cancelAll()
        XCTAssertFalse(tickets.accept(first))
        XCTAssertFalse(tickets.isCatchingUp)
        let next = tickets.request()
        XCTAssertGreaterThan(next, first, "numbers are never reused")
        XCTAssertTrue(tickets.accept(next))
    }
}
