import XCTest
import AppKit
@testable import AlertPanel

/// The escalation panel (M4 Task 4). The panel is built and read back, and
/// never put on screen: no test calls `present()`, so none needs a screen or
/// shows a window, and each checks the panel is still not visible.
@MainActor
final class AlertPanelControllerTests: XCTestCase {
    override func setUp() {
        // Windows expect an application object to exist.
        _ = NSApplication.shared
    }

    private func controller() -> AlertPanelController {
        AlertPanelController(title: "Waiting", acknowledgeTitle: "Acknowledge")
    }

    func testThePanelFloatsAboveEverythingOnEverySpaceWithoutTakingFocus() {
        let panel = controller().panel
        XCTAssertEqual(panel.level, .statusBar,
                       "set after isFloatingPanel, which would otherwise reset it to .floating (findings 2026-09-25)")
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.styleMask.contains(.titled), "borderless: no title bar to grab focus with")
        XCTAssertFalse(panel.hidesOnDeactivate, "this app is almost never the active one")
        XCTAssertFalse(panel.isVisible)
    }

    func testRowsKeepTheirOrderAndTheirLines() {
        let panel = controller()
        let ids = [UUID(), UUID(), UUID()]
        panel.setRows([(ids[0], "Newest — since 10:44 — tier 2"),
                       (ids[1], "Middle — since 10:43 — tier 3, repeat 1 of 20"),
                       (ids[2], "Oldest — since 10:42 — missed while asleep")], onAcknowledge: { _ in })
        XCTAssertEqual(panel.rows.map(\.id), ids)
        XCTAssertEqual(panel.rows.map(\.line), ["Newest — since 10:44 — tier 2",
                                               "Middle — since 10:43 — tier 3, repeat 1 of 20",
                                               "Oldest — since 10:42 — missed while asleep"])
        XCTAssertEqual(panel.buttons.map(\.escalationID), ids, "each row's button acknowledges that row")
        XCTAssertEqual(panel.buttons.map(\.title), Array(repeating: "Acknowledge", count: 3))
        XCTAssertFalse(panel.panel.isVisible, "laying rows out never shows the panel")
    }

    func testEachButtonAcknowledgesItsOwnRow() throws {
        let panel = controller()
        let ids = [UUID(), UUID()]
        var acknowledged: [UUID] = []
        panel.setRows([(ids[0], "A"), (ids[1], "B")], onAcknowledge: { acknowledged.append($0) })
        try XCTUnwrap(panel.buttons.last).performClick(nil)
        try XCTUnwrap(panel.buttons.first).performClick(nil)
        XCTAssertEqual(acknowledged, [ids[1], ids[0]])
    }

    func testNewRowsReplaceTheOld() {
        let panel = controller()
        panel.setRows([(UUID(), "A"), (UUID(), "B"), (UUID(), "C")], onAcknowledge: { _ in })
        let only = UUID()
        panel.setRows([(only, "D")], onAcknowledge: { _ in })
        XCTAssertEqual(panel.rows.map(\.id), [only])
        XCTAssertEqual(panel.buttons.count, 1)
    }

    func testMoreRowsMakeATallerPanel() {
        let panel = controller()
        panel.setRows([(UUID(), "A")], onAcknowledge: { _ in })
        let one = panel.panel.frame.height
        panel.setRows([(UUID(), "A"), (UUID(), "B"), (UUID(), "C")], onAcknowledge: { _ in })
        XCTAssertGreaterThan(panel.panel.frame.height, one)
    }

    func testShowingNoRowsHidesThePanelWithoutLayingAnythingOut() {
        let panel = controller()
        panel.setRows([(UUID(), "A")], onAcknowledge: { _ in })
        panel.show(rows: [], onAcknowledge: { _ in })
        XCTAssertFalse(panel.panel.isVisible)
        XCTAssertEqual(panel.rows.count, 1, "hiding keeps the last rows; nothing new was laid out")
    }

    func testTheHeadingIsTheOneGiven() {
        let panel = AlertPanelController(title: "SignalLadder: waiting for you to acknowledge", acknowledgeTitle: "OK")
        panel.setRows([(UUID(), "A")], onAcknowledge: { _ in })
        let texts = panel.panel.contentView.map(Self.strings(in:)) ?? []
        XCTAssertTrue(texts.contains("SignalLadder: waiting for you to acknowledge"), "\(texts)")
        XCTAssertEqual(panel.buttons.first?.title, "OK")
    }

    private static func strings(in view: NSView) -> [String] {
        let own = (view as? NSTextField).map { [$0.stringValue] } ?? []
        return own + view.subviews.flatMap(strings(in:))
    }
}
