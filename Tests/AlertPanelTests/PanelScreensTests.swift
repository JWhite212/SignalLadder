import XCTest
import AppKit
@testable import AlertPanel

/// A display unplugged while the panel shows (#104). Measured on macOS 27.2 on
/// 2026-10-18, macOS left the panel on the display that had gone, so the controller
/// places it again when the screens change. The screens and the pointer are given,
/// as two displays side by side were measured, so nothing here needs a real screen.
@MainActor
final class PanelScreensTests: XCTestCase {
    /// The main display, with a menu bar and a Dock, and one to its right.
    private let main = AlertPanelController.ScreenArea(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
                                                       visible: NSRect(x: 0, y: 58, width: 1920, height: 992))
    private let right = AlertPanelController.ScreenArea(frame: NSRect(x: 1920, y: 369, width: 1920, height: 1080),
                                                        visible: NSRect(x: 1920, y: 369, width: 1920, height: 1080))

    private var areas: [AlertPanelController.ScreenArea] = []
    private var at = NSPoint.zero

    override func setUp() {
        _ = NSApplication.shared
        areas = [main, right]
        at = NSPoint(x: 3227, y: 935)
    }

    /// Records being ordered in and out, and never draws.
    private final class RecordingPanel: NSPanel {
        private var onScreen = false
        override var isVisible: Bool { onScreen }
        override func orderFrontRegardless() { onScreen = true }
        override func orderOut(_ sender: Any?) { onScreen = false }
    }

    private func recording() -> (AlertPanelController, RecordingPanel) {
        var made: RecordingPanel!
        let controller = AlertPanelController(title: "Waiting", acknowledgeTitle: "Acknowledge",
                                              overflowLine: { "and \($0) more" },
                                              screens: { [unowned self] in areas }, pointer: { [unowned self] in at }) {
            made = RecordingPanel(contentRect: $0, styleMask: $1, backing: .buffered, defer: true)
            return made
        }
        return (controller, made)
    }

    private func showOne(_ controller: AlertPanelController) {
        controller.show(rows: [(UUID(), "On-call mentions — since 10:42 — tier 2")], onAcknowledge: { _ in })
    }

    private func screensChange() {
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func testThePanelOpensTopRightOfTheScreenThePointerIsOn() {
        let (controller, window) = recording()
        showOne(controller)
        XCTAssertTrue(right.frame.contains(window.frame), "on the display to the right, where the pointer is")
        XCTAssertEqual(window.frame.maxX, right.visible.maxX - AlertPanelController.margin, accuracy: 0.5)
        XCTAssertEqual(window.frame.maxY, right.visible.maxY - AlertPanelController.margin, accuracy: 0.5)
    }

    func testAPanelOnADisplayThatHasGoneIsPutOnOneThatIs() {
        let (controller, window) = recording()
        showOne(controller)
        XCTAssertFalse(main.frame.contains(window.frame))

        // The display on the right is unplugged, and macOS moves the pointer to the
        // main display's edge, as was measured.
        areas = [main]
        at = NSPoint(x: 1919.98, y: 400)
        screensChange()

        XCTAssertTrue(main.frame.contains(window.frame), "put back on the screen that is left")
        XCTAssertEqual(window.frame.maxX, main.visible.maxX - AlertPanelController.margin, accuracy: 0.5)
        XCTAssertEqual(window.frame.maxY, main.visible.maxY - AlertPanelController.margin, accuracy: 0.5)
        XCTAssertTrue(window.isVisible, "and still showing")
    }

    func testAPanelStillOnAScreenStaysWhereItIsWhenTheScreensChange() {
        at = NSPoint(x: 600, y: 400)
        let (controller, window) = recording()
        showOne(controller)
        let before = window.frame
        XCTAssertTrue(main.frame.contains(before))

        areas = [main]
        screensChange()
        XCTAssertEqual(window.frame, before, "the display that went was not the panel's")

        areas = [main, right]
        at = NSPoint(x: 3227, y: 935)
        screensChange()
        XCTAssertEqual(window.frame, before, "nor does a display added, with the pointer on it, move it")
    }

    func testAHiddenPanelIsNotPlacedWhenTheScreensChange() {
        let (controller, window) = recording()
        showOne(controller)
        controller.hide()
        let before = window.frame
        areas = [main]
        screensChange()
        XCTAssertEqual(window.frame, before, "placed when it is next shown, as always")
    }

    /// With no screen at all there is nowhere to put it, and it is left where it is.
    func testWithNoScreenAtAllThePanelIsLeftWhereItIs() {
        let (controller, window) = recording()
        showOne(controller)
        let before = window.frame
        areas = []
        screensChange()
        XCTAssertEqual(window.frame, before)
    }

    func testAFrameIsOnAScreenOnlyWhenOneHoldsItWhole() {
        // Where the panel was measured, in screen coordinates.
        let gone = NSRect(x: 3400, y: 1312, width: 420, height: 86)
        XCTAssertFalse(AlertPanelController.isOnAScreen(gone, among: [main]), "a frame no screen contains")
        XCTAssertTrue(AlertPanelController.isOnAScreen(gone, among: [main, right]))
        XCTAssertTrue(AlertPanelController.isOnAScreen(NSRect(x: 1480, y: 950, width: 420, height: 86), among: [main]))
        XCTAssertFalse(AlertPanelController.isOnAScreen(NSRect(x: 1700, y: 950, width: 420, height: 86), among: [main]),
                       "half off the edge is not on it")
        XCTAssertFalse(AlertPanelController.isOnAScreen(gone, among: []))
    }
}
