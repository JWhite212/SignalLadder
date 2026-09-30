import XCTest
import AppKit
@testable import AlertPanel

/// The escalation panel (M4 Task 4). No window is ever put on screen: rows are
/// laid out and read back, and showing and hiding are checked on a panel that
/// records being ordered in and out instead of doing it.
@MainActor
final class AlertPanelControllerTests: XCTestCase {
    override func setUp() {
        // AppKit makes the shared application itself when the first window
        // or control is built (seen 2026-09-30). Made here first, so every
        // test starts from the same state whichever runs first.
        _ = NSApplication.shared
    }

    private func controller() -> AlertPanelController {
        AlertPanelController(title: "Waiting", acknowledgeTitle: "Acknowledge", overflowLine: { "and \($0) more" })
    }

    /// Records being ordered in and out, and never draws.
    private final class RecordingPanel: NSPanel {
        private(set) var orderedIn = 0
        private(set) var orderedOut = 0
        private var onScreen = false
        override var isVisible: Bool { onScreen }
        override func orderFrontRegardless() { orderedIn += 1; onScreen = true }
        override func orderOut(_ sender: Any?) { orderedOut += 1; onScreen = false }
    }

    private func recording() -> (AlertPanelController, RecordingPanel) {
        var made: RecordingPanel!
        let controller = AlertPanelController(title: "Waiting", acknowledgeTitle: "Acknowledge",
                                              overflowLine: { "and \($0) more" }) {
            made = RecordingPanel(contentRect: $0, styleMask: $1, backing: .buffered, defer: true)
            return made
        }
        return (controller, made)
    }

    private func rows(_ count: Int) -> [(UUID, String)] {
        (0..<count).map { (UUID(), "Rule \($0) — since 10:42 — tier 3, repeat 3 of 20") }
    }

    // MARK: - The window

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
        XCTAssertTrue(panel.worksWhenModal, "the buttons must answer while one of the app's alerts is up")
        XCTAssertFalse(panel.isVisible)
    }

    func testTheRecordingPanelIsBuiltTheSameWay() {
        let (_, panel) = recording()
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.styleMask.contains(.titled))
        XCTAssertEqual(panel.level, .statusBar)
    }

    func testTheHeadingIsTheOneGivenAndNamesTheWindow() {
        let panel = AlertPanelController(title: "SignalLadder: waiting for you to acknowledge", acknowledgeTitle: "OK",
                                         overflowLine: { "\($0)" })
        panel.setRows([(UUID(), "A")], onAcknowledge: { _ in })
        let texts = panel.panel.contentView.map(Self.strings(in:)) ?? []
        XCTAssertTrue(texts.contains("SignalLadder: waiting for you to acknowledge"), "\(texts)")
        XCTAssertEqual(panel.panel.title, "SignalLadder: waiting for you to acknowledge", "what VoiceOver calls it")
        XCTAssertEqual(panel.buttons.first?.title, "OK")
    }

    // MARK: - Rows

    func testEachRowDrawsTheLineItWasGivenInOrder() {
        let panel = controller()
        let ids = [UUID(), UUID(), UUID()]
        let lines = ["Newest — since 10:44 — tier 2",
                     "Middle — since 10:43 — tier 3, repeat 1 of 20",
                     "Oldest — since 10:42 — missed while asleep"]
        panel.setRows(Array(zip(ids, lines)), onAcknowledge: { _ in })
        XCTAssertEqual(panel.rows.map(\.id), ids)
        XCTAssertEqual(panel.drawnLines, lines, "read from the labels, not the model")
        XCTAssertEqual(panel.buttons.map(\.escalationID), ids, "each row's button acknowledges that row")
        XCTAssertEqual(panel.buttons.map(\.title), Array(repeating: "Acknowledge", count: 3))
        XCTAssertEqual(panel.buttons.map { $0.accessibilityLabel() }, lines.map { "Acknowledge: \($0)" },
                       "VoiceOver is told which row each button acknowledges")
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

    func testNewRowsReplaceTheOldAndTheOldAreGone() throws {
        let panel = controller()
        panel.setRows([(UUID(), "A"), (UUID(), "B"), (UUID(), "C")], onAcknowledge: { _ in })
        let only = UUID()
        panel.setRows([(only, "D")], onAcknowledge: { _ in })
        XCTAssertEqual(panel.rows.map(\.id), [only])
        XCTAssertEqual(panel.buttons.count, 1)
        let texts = try XCTUnwrap(panel.panel.contentView.map(Self.strings(in:)))
        XCTAssertEqual(texts, ["Waiting", "D"], "a replaced row is taken out of the window, not only the stack")
    }

    func testARowThatStaysKeepsItsViewsAndChangesItsWords() throws {
        // Every tier-3 repeat updates the panel; a button built again under a
        // press would lose the click.
        let panel = controller()
        let stays = UUID()
        panel.setRows([(stays, "Kept — tier 3, repeat 1 of 20")], onAcknowledge: { _ in })
        let button = try XCTUnwrap(panel.buttons.first)
        panel.setRows([(UUID(), "New — tier 1"), (stays, "Kept — tier 3, repeat 2 of 20")], onAcknowledge: { _ in })
        XCTAssertTrue(panel.buttons.last === button)
        XCTAssertEqual(panel.drawnLines, ["New — tier 1", "Kept — tier 3, repeat 2 of 20"])
        XCTAssertEqual(button.accessibilityLabel(), "Acknowledge: Kept — tier 3, repeat 2 of 20")
    }

    func testTheButtonsLineUpInsideTheMargin() throws {
        let panel = controller()
        panel.setRows([(UUID(), "Short"),
                       (UUID(), "On-call mentions — since 10:42 — tier 3, repeat 3 of 20, no longer repeating"),
                       (UUID(), "Mid-length rule — since 10:40 — tier 2")], onAcknowledge: { _ in })
        let content = try XCTUnwrap(panel.panel.contentView)
        // Auto Layout places a button by its alignment rectangle. Its frame
        // also takes in the bezel's shadow, 7 pt wider on macOS 15 and not at
        // all on macOS 26 (CI and this Mac, 2026-09-30).
        let edges = try panel.buttons.map { button -> CGFloat in
            let superview = try XCTUnwrap(button.superview)
            return superview.convert(button.alignmentRect(forFrame: button.frame), to: content).maxX
        }
        XCTAssertEqual(Set(edges).count, 1, "one column: \(edges)")
        XCTAssertLessThanOrEqual(try XCTUnwrap(edges.first), AlertPanelController.width - AlertPanelController.insets.right + 0.5)
    }

    func testMoreRowsMakeATallerPanel() {
        let panel = controller()
        panel.setRows(rows(1), onAcknowledge: { _ in })
        let one = panel.panel.frame.height
        panel.setRows(rows(3), onAcknowledge: { _ in })
        XCTAssertGreaterThan(panel.panel.frame.height, one)
    }

    func testRowsBeyondTheLimitAreCountedNotShown() {
        let panel = controller()
        panel.setRows(rows(AlertPanelController.maxRows), onAcknowledge: { _ in })
        let full = panel.panel.frame.height
        XCTAssertNil(panel.drawnOverflow)

        let many = rows(60)
        panel.setRows(many, onAcknowledge: { _ in })
        XCTAssertEqual(panel.rows.map(\.id), many.prefix(AlertPanelController.maxRows).map(\.0), "the newest")
        XCTAssertEqual(panel.buttons.count, AlertPanelController.maxRows)
        XCTAssertEqual(panel.hiddenCount, 60 - AlertPanelController.maxRows)
        XCTAssertEqual(panel.drawnOverflow, "and \(60 - AlertPanelController.maxRows) more")
        XCTAssertLessThan(panel.panel.frame.height, full + 60, "one more line, not 54 more rows")

        panel.setRows(rows(2), onAcknowledge: { _ in })
        XCTAssertNil(panel.drawnOverflow)
        XCTAssertFalse((panel.panel.contentView.map(Self.strings(in:)) ?? []).contains { $0.hasPrefix("and ") },
                       "the count leaves the window with the rows it counted")
    }

    // MARK: - Showing and hiding

    func testShowingPutsThePanelUpOnceAndKeepsItsTopEdge() {
        let (panel, window) = recording()
        panel.show(rows: rows(1), onAcknowledge: { _ in })
        XCTAssertEqual(window.orderedIn, 1)
        let top = window.frame.maxY

        panel.show(rows: rows(3), onAcknowledge: { _ in })
        XCTAssertEqual(window.orderedIn, 1, "already up: not put up again, nor moved to the pointer's screen")
        XCTAssertEqual(window.frame.maxY, top, accuracy: 0.5, "grows downwards from where it is")
        XCTAssertEqual(panel.rows.count, 3)
    }

    func testShowingNoRowsHidesThePanel() {
        let (panel, window) = recording()
        panel.show(rows: rows(1), onAcknowledge: { _ in })
        panel.show(rows: [], onAcknowledge: { _ in })
        XCTAssertEqual(window.orderedOut, 1)
        XCTAssertFalse(window.isVisible)

        panel.show(rows: rows(1), onAcknowledge: { _ in })
        XCTAssertEqual(window.orderedIn, 2, "put up again once there is something to show")
    }

    func testThePanelSitsTopRightInsideTheMargin() {
        let visible = NSRect(x: 0, y: 40, width: 1920, height: 1000)
        let origin = AlertPanelController.origin(for: NSSize(width: 420, height: 100), in: visible)
        XCTAssertEqual(origin, NSPoint(x: 1920 - 420 - 20, y: 1040 - 100 - 20))
    }

    /// The text the panel's labels draw. A button's own title is left out:
    /// on macOS 15 a button draws it with a text field of its own, and on
    /// macOS 26 it does not (CI, 2026-09-30). Tests read it from `title`.
    private static func strings(in view: NSView) -> [String] {
        if view is NSButton { return [] }
        let own = (view as? NSTextField).map { [$0.stringValue] } ?? []
        return own + view.subviews.flatMap(strings(in:))
    }
}

/// The panel cannot show what arrived because it cannot name it: its target
/// depends on nothing (ruling 17). Nothing at run time would show a breach,
/// so it is checked here, as `PurityTests` checks `NotificationCore`.
final class AlertPanelPurityTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // AlertPanelTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // package root

    func testThePanelImportsOnlyAppKitAndFoundation() throws {
        let sources = root.appendingPathComponent("Sources/AlertPanel")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "found no sources at \(sources.path)")
        for file in files {
            let imports = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("import ") || $0.contains(" import ") }
            for line in imports {
                XCTAssertTrue(["import AppKit", "import Foundation"].contains(line),
                              "\(file.lastPathComponent): \(line) (ruling 17: the panel depends on nothing)")
            }
        }
    }

    func testThePanelTargetHasNoDependencies() throws {
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(manifest.contains(".target(name: \"AlertPanel\"),"),
                      "the AlertPanel target must stay declared with a name alone (ruling 17)")
    }
}
