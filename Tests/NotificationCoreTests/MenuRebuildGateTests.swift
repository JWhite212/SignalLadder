import XCTest
@testable import NotificationCore

/// When the status menu's items may be rebuilt (M5 plan, Ruling 22). The gate
/// has no menu and no clock: each test tells it what the app would, in the order
/// the app would, and reads what it answers.
final class MenuRebuildGateTests: XCTestCase {
    private typealias Step = MenuRebuildGate.Step

    /// What every change does, in the order it is done.
    private let everyChange: [Step] = [.syncInspector, .updatePulse, .refreshGlyph]

    // MARK: - Closed

    func testARequestWhileTheMenuIsClosedIsToRebuildNow() {
        var gate = MenuRebuildGate()
        XCTAssertEqual(gate.request(), everyChange + [.rebuildItems])
        XCTAssertFalse(gate.isOpen)
    }

    func testARequestWhileClosedOwesNothingAtTheNextClose() {
        var gate = MenuRebuildGate()
        _ = gate.request()
        gate.menuOpened()
        XCTAssertEqual(gate.menuClosed(), [], "it was made when it was asked for")
    }

    // MARK: - Open

    func testARequestWhileTheMenuIsOpenIsLaterAndTheItemsAreLeftOut() {
        var gate = MenuRebuildGate()
        gate.menuOpened()
        XCTAssertTrue(gate.isOpen)
        let steps = gate.request()
        XCTAssertEqual(steps, everyChange)
        XCTAssertFalse(steps.contains(.rebuildItems), "a row under the pointer does not move")
    }

    func testClosingAfterARequestWasHeldRebuildsTheItems() {
        var gate = MenuRebuildGate()
        gate.menuOpened()
        _ = gate.request()
        XCTAssertEqual(gate.menuClosed(), [.rebuildItems])
        XCTAssertFalse(gate.isOpen)
    }

    func testClosingRebuildsOnceHoweverManyWereHeld() {
        var gate = MenuRebuildGate()
        gate.menuOpened()
        for _ in 0..<5 { _ = gate.request() }
        XCTAssertEqual(gate.menuClosed(), [.rebuildItems], "one, not five")
        XCTAssertEqual(gate.menuClosed(), [], "and not again for the same ones")
    }

    func testClosingWithNothingHeldRebuildsNothing() {
        var gate = MenuRebuildGate()
        gate.menuOpened()
        XCTAssertEqual(gate.menuClosed(), [])
    }

    func testARequestAfterTheMenuClosesIsNowAgain() {
        var gate = MenuRebuildGate()
        gate.menuOpened()
        _ = gate.request()
        _ = gate.menuClosed()
        XCTAssertEqual(gate.request(), everyChange + [.rebuildItems])
    }

    func testOpeningTwiceWithNoCloseBetweenLeavesTheGateOpen() {
        var gate = MenuRebuildGate()
        gate.menuOpened()
        gate.menuOpened()
        XCTAssertTrue(gate.isOpen)
        XCTAssertEqual(gate.request(), everyChange, "still held: the second open did not close it")
        XCTAssertEqual(gate.menuClosed(), [.rebuildItems], "and the next close rebuilds once")
        XCTAssertEqual(gate.menuClosed(), [])
    }

    func testAnOwedRebuildThatWasMadeIsNotMadeAgainAtTheNextClose() {
        var gate = MenuRebuildGate()
        gate.menuOpened()
        _ = gate.request()
        XCTAssertEqual(gate.menuClosed(), [.rebuildItems])
        gate.menuOpened()
        XCTAssertEqual(gate.menuClosed(), [], "nothing was asked for during the second open")
    }

    // MARK: - How the app opens it

    func testTheRebuildAMenuMakesAsItOpensIsTheOneThatWasOwed() {
        // A close that was never reported leaves a rebuild owed. The app tells
        // the gate the menu is closed as it is about to be shown, rebuilds as it
        // does when it is opened, and then tells it it is open.
        var gate = MenuRebuildGate()
        gate.menuOpened()
        _ = gate.request()

        _ = gate.menuClosed()
        XCTAssertEqual(gate.request(), everyChange + [.rebuildItems], "the rebuild the opening makes goes ahead")
        gate.menuOpened()

        XCTAssertEqual(gate.request(), everyChange, "and from then on the menu is held")
        XCTAssertEqual(gate.menuClosed(), [.rebuildItems])
    }

    func testANewGateIsClosed() {
        XCTAssertFalse(MenuRebuildGate().isOpen)
    }

    // MARK: - What "later" never reaches (Ruling 22)

    func testTheSyncThePulseAndTheGlyphAreInEveryRequestOpenOrClosed() {
        // A page that begins while the menu is open must still pulse the icon
        // and reach the Inspector at once. Only the items are held.
        var closed = MenuRebuildGate()
        var open = MenuRebuildGate()
        open.menuOpened()
        for steps in [closed.request(), open.request(), open.request()] {
            XCTAssertEqual(Array(steps.prefix(3)), everyChange, "the three come first, in this order")
        }
    }

    func testTheItemRebuildComesLastAndOnlyWhenTheMenuIsClosedOrClosesWithOneOwed() {
        var gate = MenuRebuildGate()
        XCTAssertEqual(gate.request().last, .rebuildItems, "closed")
        gate.menuOpened()
        XCTAssertNotEqual(gate.request().last, .rebuildItems, "open")
        XCTAssertEqual(gate.menuClosed(), [.rebuildItems], "closing with one owed")
        gate.menuOpened()
        XCTAssertEqual(gate.menuClosed(), [], "closing with none owed")
    }

    func testClosingNeverAsksForTheThreeThatRanAtEachRequest() {
        var gate = MenuRebuildGate()
        gate.menuOpened()
        _ = gate.request()
        let closing = gate.menuClosed()
        XCTAssertEqual(closing, [.rebuildItems])
        for step in everyChange {
            XCTAssertFalse(closing.contains(step), "\(step) already ran when the change was made")
        }
    }
}
