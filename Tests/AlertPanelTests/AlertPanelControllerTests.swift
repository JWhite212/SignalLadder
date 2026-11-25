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

    /// A controller with no screen to measure against, so how many rows it shows
    /// does not depend on the display of the Mac the tests run on: CI's is small
    /// enough that six of the tallest rows do not fit it. The tests of fitting a
    /// screen, and of placement, give screens of their own.
    private func controller() -> AlertPanelController {
        AlertPanelController(title: "Waiting", acknowledgeTitle: "Acknowledge", overflowLine: { "and \($0) more" },
                             screens: { [] }, pointer: { .zero }) {
            NSPanel(contentRect: $0, styleMask: $1, backing: .buffered, defer: true)
        }
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

    /// A row as the app would give it, with the line as its name, so a test
    /// that reads what is drawn reads the words it gave.
    private func row(_ id: UUID, _ line: String, mark: PanelRow.Mark = .tier(3)) -> PanelRow {
        PanelRow(id: id, name: line, detail: [], spoken: line, mark: mark)
    }

    private func rows(_ count: Int) -> [PanelRow] {
        (0..<count).map {
            PanelRow(id: UUID(), name: "Rule \($0)",
                     detail: [.words("since "), .figure("10:42"), .words(" — repeat "), .figure("03/20")],
                     spoken: "Rule \($0) — since 10:42 — tier 3, repeat 3 of 20", mark: .tier(3))
        }
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
        panel.setRows([row(UUID(), "A")], onAcknowledge: { _ in })
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
        panel.setRows(zip(ids, lines).map { row($0, $1) }, onAcknowledge: { _ in })
        XCTAssertEqual(panel.rows.map(\.id), ids)
        XCTAssertEqual(panel.drawnNames, lines, "read from the labels, not the model")
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
        panel.setRows([row(ids[0], "A"), row(ids[1], "B")], onAcknowledge: { acknowledged.append($0) })
        try XCTUnwrap(panel.buttons.last).performClick(nil)
        try XCTUnwrap(panel.buttons.first).performClick(nil)
        XCTAssertEqual(acknowledged, [ids[1], ids[0]])
    }

    func testNewRowsReplaceTheOldAndTheOldAreGone() throws {
        let panel = controller()
        panel.setRows([row(UUID(), "A"), row(UUID(), "B"), row(UUID(), "C")], onAcknowledge: { _ in })
        let only = UUID()
        panel.setRows([row(only, "D")], onAcknowledge: { _ in })
        XCTAssertEqual(panel.rows.map(\.id), [only])
        XCTAssertEqual(panel.buttons.count, 1)
        let texts = try XCTUnwrap(panel.panel.contentView.map(Self.strings(in:)))
        // The heading, then the one row's numeral, its name and its line, which this row has none of.
        XCTAssertEqual(texts, ["Waiting", "3", "D", ""], "a replaced row is taken out of the window, not only the stack")
    }

    func testARowThatStaysKeepsItsViewsAndChangesItsWords() throws {
        // Every tier-3 repeat updates the panel; a button built again under a
        // press would lose the click.
        let panel = controller()
        let stays = UUID()
        panel.setRows([row(stays, "Kept — tier 3, repeat 1 of 20")], onAcknowledge: { _ in })
        let button = try XCTUnwrap(panel.buttons.first)
        panel.setRows([row(UUID(), "New — tier 1"), row(stays, "Kept — tier 3, repeat 2 of 20")], onAcknowledge: { _ in })
        XCTAssertTrue(panel.buttons.last === button)
        XCTAssertEqual(panel.drawnNames, ["New — tier 1", "Kept — tier 3, repeat 2 of 20"])
        XCTAssertEqual(button.accessibilityLabel(), "Acknowledge: Kept — tier 3, repeat 2 of 20")
    }

    func testTheButtonsLineUpInsideTheMargin() throws {
        let panel = controller()
        panel.setRows([row(UUID(), "Short"),
                       row(UUID(), "On-call mentions — since 10:42 — tier 3, repeat 3 of 20, no longer repeating"),
                       row(UUID(), "Mid-length rule — since 10:40 — tier 2")], onAcknowledge: { _ in })
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
        XCTAssertEqual(panel.rows.map(\.id), many.prefix(AlertPanelController.maxRows).map(\.id), "the newest")
        XCTAssertEqual(panel.buttons.count, AlertPanelController.maxRows)
        XCTAssertEqual(panel.hiddenCount, 60 - AlertPanelController.maxRows)
        XCTAssertEqual(panel.drawnOverflow, "and \(60 - AlertPanelController.maxRows) more")
        XCTAssertLessThan(panel.panel.frame.height, full + 60, "one more line, not 54 more rows")

        panel.setRows(rows(2), onAcknowledge: { _ in })
        XCTAssertNil(panel.drawnOverflow)
        XCTAssertFalse((panel.panel.contentView.map(Self.strings(in:)) ?? []).contains { $0.hasPrefix("and ") },
                       "the count leaves the window with the rows it counted")
    }

    // MARK: - The Night watch design (M7 plan, Stage 3)

    private func hex(_ colour: CGColor?) throws -> String {
        let srgb = try XCTUnwrap(NSColor(cgColor: try XCTUnwrap(colour))?.usingColorSpace(.sRGB))
        return String(format: "%02X%02X%02X", Int((srgb.redComponent * 255).rounded()),
                      Int((srgb.greenComponent * 255).rounded()), Int((srgb.blueComponent * 255).rounded()))
    }

    private func said(_ name: String, mark: PanelRow.Mark, id: UUID = UUID()) -> PanelRow {
        PanelRow(id: id, name: name, detail: [.words("since "), .figure("10:42"), .words(" — repeat "), .figure("03/20")],
                 spoken: "\(name) — since 10:42 — tier 3, repeat 3 of 20", mark: mark)
    }

    /// The ground is the design's navy whatever the system's appearance, so the
    /// panel is drawn for a dark ground and its corners are the design's.
    func testTheGroundIsNavyAndThePanelIsDrawnForADarkGround() throws {
        let panel = controller()
        let ground = try XCTUnwrap(panel.panel.contentView)
        XCTAssertEqual(try hex(ground.layer?.backgroundColor), "0C1224")
        XCTAssertEqual(ground.layer?.cornerRadius, AlertPanelController.cornerRadius)
        XCTAssertEqual(ground.layer?.masksToBounds, true)
        XCTAssertEqual(panel.panel.appearance?.name, .darkAqua)
        XCTAssertFalse(ground is NSVisualEffectView, "no material of the system's shows through it")
    }

    // MARK: - Glass (M7 plan, Stage 7)

    private func controller(ground: @escaping @MainActor () -> PanelGround.Material) -> AlertPanelController {
        AlertPanelController(title: "Waiting", acknowledgeTitle: "Acknowledge", overflowLine: { "and \($0) more" },
                             ground: ground, screens: { [] }, pointer: { .zero }) {
            NSPanel(contentRect: $0, styleMask: $1, backing: .buffered, defer: true)
        }
    }

    /// A caller that says nothing of the ground gets the navy, as before.
    func testThePanelsGroundIsSolidUnlessTheAppAsksForGlass() throws {
        let panel = controller()
        panel.setRows(rows(2), onAcknowledge: { _ in })
        let ground = try XCTUnwrap(panel.panel.contentView as? PanelGroundView)
        XCTAssertEqual(ground.material, .solid)
        XCTAssertEqual(ground.layer?.backgroundColor?.alpha, 1)
    }

    /// The ground is asked for each time rows are laid out, since Reduce
    /// transparency can be switched while the panel is up, and before any rows
    /// the panel is solid.
    func testTheGroundIsAskedForEachTimeRowsAreLaidOut() throws {
        var wanted = PanelGround.Material.glass
        var asked = 0
        let panel = controller(ground: { asked += 1; return wanted })
        let ground = try XCTUnwrap(panel.panel.contentView as? PanelGroundView)
        XCTAssertEqual(asked, 0)
        XCTAssertEqual(ground.material, .solid)

        panel.setRows(rows(1), onAcknowledge: { _ in })
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(ground.material, PanelGround.glassIsAvailable ? .glass : .solid)

        wanted = .solid
        panel.setRows(rows(1), onAcknowledge: { _ in })
        XCTAssertEqual(asked, 2)
        XCTAssertEqual(ground.material, .solid)
        XCTAssertEqual(ground.layer?.backgroundColor?.alpha, 1)
    }

    /// Only the ground is glass. A tier's block keeps its colour, opaque, and a
    /// fault's block its navy, since they carry the words; and the rows are the
    /// same views on either ground, so a press is not lost to the change.
    func testOnGlassTheBlocksAreAsOpaqueAsOnNavy() throws {
        var wanted = PanelGround.Material.solid
        let panel = controller(ground: { wanted })
        let said = [said("First", mark: .tier(1)), said("Second", mark: .tier(2)), said("Upper", mark: .tier(3)),
                    said("Failed", mark: .fault)]
        panel.setRows(said, onAcknowledge: { _ in })
        let onNavy = panel.blocks
        let buttons = panel.buttons
        wanted = .glass
        panel.setRows(said, onAcknowledge: { _ in })
        XCTAssertEqual(panel.blocks, onNavy)
        XCTAssertEqual(panel.buttons, buttons)
        XCTAssertEqual(try panel.blocks.map { try hex($0.layer?.backgroundColor) }, ["FFC857", "FF8A2B", "FF4D3D", "0C1224"])
        XCTAssertEqual(panel.blocks.map { $0.layer?.backgroundColor?.alpha }, [1, 1, 1, 1])
        let ground = try XCTUnwrap(panel.panel.contentView as? PanelGroundView)
        for block in panel.blocks {
            XCTAssertTrue(block.isDescendant(of: ground.holder))
        }
    }

    /// The panel is the same size on either ground.
    func testThePanelIsTheSameSizeOnGlass() {
        var wanted = PanelGround.Material.solid
        let panel = controller(ground: { wanted })
        panel.setRows(rows(3), onAcknowledge: { _ in })
        let onNavy = panel.panel.frame.size
        wanted = .glass
        panel.setRows(rows(3), onAcknowledge: { _ in })
        XCTAssertEqual(panel.panel.frame.size, onNavy)
    }

    /// A block's corners follow the panel's: its radius is the panel's less the
    /// inset between them.
    func testABlocksCornersRunWithThePanels() {
        XCTAssertEqual(AlertPanelController.blockRadius, AlertPanelController.cornerRadius - AlertPanelController.insets.left)
        let panel = controller()
        panel.setRows([said("A", mark: .tier(2))], onAcknowledge: { _ in })
        XCTAssertEqual(panel.blocks.first?.layer?.cornerRadius, AlertPanelController.blockRadius)
    }

    /// Each tier's block is its tone's colour, with the tier's number beside
    /// the words and no line round it.
    func testEachTiersBlockIsItsColourWithItsNumber() throws {
        let panel = controller()
        panel.setRows([said("One", mark: .tier(1)), said("Two", mark: .tier(2)), said("Three", mark: .tier(3)),
                       said("Four", mark: .tier(4))], onAcknowledge: { _ in })
        XCTAssertEqual(try panel.blocks.map { try hex($0.layer?.backgroundColor) }, ["FFC857", "FF8A2B", "FF4D3D", "FF4D3D"])
        XCTAssertEqual(panel.drawnNumerals, ["1", "2", "3", "4"])
        XCTAssertEqual(panel.blocks.map { $0.layer?.borderWidth }, [0, 0, 0, 0])
        XCTAssertEqual(panel.buttons.map(\.look), [.filled, .filled, .filled, .filled])
        XCTAssertEqual(panel.drawnNames, ["One", "Two", "Three", "Four"])
    }

    /// A fault has no colour: the ground's navy, a line round it, the slashed
    /// bell where a number would be, and a button that is a line too.
    func testAFaultHasALineRoundItAndNoColourOrNumber() throws {
        let panel = controller()
        panel.setRows([said("Failed", mark: .fault), said("Fine", mark: .tier(2))], onAcknowledge: { _ in })
        let fault = try XCTUnwrap(panel.blocks.first)
        XCTAssertEqual(try hex(fault.layer?.backgroundColor), "0C1224")
        XCTAssertEqual(try hex(fault.layer?.borderColor), "FFFFFF")
        XCTAssertEqual(fault.layer?.borderWidth, AlertPanelController.defaultOutlineWidth + 1,
                       "a point heavier than the button's, so the row is not lost beside a filled one")
        XCTAssertEqual(panel.drawnNumerals, [nil, "2"])
        XCTAssertEqual(panel.buttons.map(\.look), [.outlined, .filled])
        XCTAssertEqual(panel.buttons.first?.layer?.borderWidth, AlertPanelController.defaultOutlineWidth)
        let symbols = Self.views(in: fault).compactMap { $0 as? NSImageView }
        XCTAssertEqual(symbols.count, 1)
        XCTAssertEqual(symbols.first?.isHidden, false)
        XCTAssertNotNil(symbols.first?.image, "the slashed bell is a symbol macOS 14 has")
    }

    /// The line round a fault is as wide as the app says when rows are laid
    /// out, so a display setting changed while the panel shows is followed.
    func testTheLineRoundAFaultIsAsWideAsTheAppSaysEachTime() throws {
        var width: CGFloat = 1.5
        let panel = AlertPanelController(title: "Waiting", acknowledgeTitle: "Acknowledge", overflowLine: { "\($0)" },
                                         outlineWidth: { width })
        let row = said("Failed", mark: .fault)
        panel.setRows([row], onAcknowledge: { _ in })
        XCTAssertEqual(panel.blocks.first?.layer?.borderWidth, 2.5)
        XCTAssertEqual(panel.buttons.first?.layer?.borderWidth, 1.5)
        width = 2.5
        panel.setRows([row], onAcknowledge: { _ in })
        XCTAssertEqual(panel.blocks.first?.layer?.borderWidth, 3.5, "the same row, drawn again with the heavier line")
        XCTAssertEqual(panel.buttons.first?.layer?.borderWidth, 2.5)
    }

    /// Words on a tier's block are the palette's ink and words on a fault are
    /// white, and a time or a count is in fixed-width figures.
    func testTheWordsAreInkOnATierAndWhiteOnAFaultAndFiguresAreFixedWidth() throws {
        let panel = controller()
        panel.setRows([said("Tier", mark: .tier(3)), said("Fault", mark: .fault)], onAcknowledge: { _ in })
        let details = panel.drawnDetails
        XCTAssertEqual(details.map(\.string), ["since 10:42 — repeat 03/20", "since 10:42 — repeat 03/20"])
        for (detail, ink) in zip(details, ["0C1224", "FFFFFF"]) {
            var figures: [String] = []
            var words: [String] = []
            detail.enumerateAttributes(in: NSRange(location: 0, length: detail.length)) { attributes, range, _ in
                let text = detail.attributedSubstring(from: range).string
                let font = attributes[.font] as? NSFont
                if font?.isFixedPitch == true { figures.append(text) } else { words.append(text) }
                let colour = (attributes[.foregroundColor] as? NSColor)?.cgColor
                XCTAssertEqual(try? hex(colour), ink, text)
            }
            XCTAssertEqual(figures, ["10:42", "03/20"])
            XCTAssertEqual(words, ["since ", " — repeat "])
        }
    }

    /// A tier that rises changes the block's colour and number in place: the
    /// button is the same one, so a press in progress is not lost.
    func testATierThatRisesRestylesTheRowInPlace() throws {
        let panel = controller()
        let id = UUID()
        panel.setRows([said("Rule", mark: .tier(2), id: id)], onAcknowledge: { _ in })
        let button = try XCTUnwrap(panel.buttons.first)
        let block = try XCTUnwrap(panel.blocks.first)
        panel.setRows([said("Rule", mark: .tier(3), id: id)], onAcknowledge: { _ in })
        XCTAssertTrue(panel.buttons.first === button)
        XCTAssertTrue(panel.blocks.first === block)
        XCTAssertEqual(try hex(block.layer?.backgroundColor), "FF4D3D")
        XCTAssertEqual(panel.drawnNumerals, ["3"])
        panel.setRows([said("Rule", mark: .fault, id: id)], onAcknowledge: { _ in })
        XCTAssertTrue(panel.buttons.first === button, "and when its Shortcut then fails")
        XCTAssertEqual(panel.drawnNumerals, [nil])
        XCTAssertEqual(button.look, .outlined)
    }

    /// The button is a capsule with room round its title, and its title is
    /// still the one given, which is what the tests and VoiceOver read.
    func testTheButtonIsACapsuleWithItsTitle() throws {
        let panel = controller()
        panel.setRows([said("Rule", mark: .tier(2))], onAcknowledge: { _ in })
        let button = try XCTUnwrap(panel.buttons.first)
        XCTAssertEqual(button.title, "Acknowledge")
        XCTAssertFalse(button.isBordered)
        XCTAssertEqual(try hex(button.layer?.backgroundColor), "0C1224")
        XCTAssertGreaterThanOrEqual(button.intrinsicContentSize.height, 26)
        button.layoutSubtreeIfNeeded()
        XCTAssertEqual(button.layer?.cornerRadius, button.bounds.height / 2)
    }

    /// VoiceOver is told the row's whole line, which says the tier in words,
    /// and not its name alone; and the label follows the row as it changes.
    func testTheButtonsLabelIsTheWholeLineAndFollowsTheRow() throws {
        let panel = controller()
        let id = UUID()
        panel.setRows([said("Rule", mark: .tier(3), id: id)], onAcknowledge: { _ in })
        let button = try XCTUnwrap(panel.buttons.first)
        XCTAssertEqual(button.accessibilityLabel(), "Acknowledge: Rule — since 10:42 — tier 3, repeat 3 of 20")
        XCTAssertNotEqual(panel.drawnNames.first, "Rule — since 10:42 — tier 3, repeat 3 of 20", "the name is not the line")
        panel.setRows([PanelRow(id: id, name: "Rule", detail: [.words("since "), .figure("10:42")],
                                spoken: "Rule — since 10:42 — tier 4", mark: .tier(4))], onAcknowledge: { _ in })
        XCTAssertEqual(button.accessibilityLabel(), "Acknowledge: Rule — since 10:42 — tier 4")
    }

    /// A button with no bezel dims while it is pressed, and comes back.
    func testTheButtonDimsWhileItIsPressed() throws {
        let panel = controller()
        panel.setRows([said("Rule", mark: .tier(2))], onAcknowledge: { _ in })
        let button = try XCTUnwrap(panel.buttons.first)
        XCTAssertEqual(button.layer?.opacity, 1)
        button.isHighlighted = true
        XCTAssertEqual(button.layer?.opacity, 0.6)
        button.isHighlighted = false
        XCTAssertEqual(button.layer?.opacity, 1)
    }

    /// The tallest row there is: a name of two lines over a fault's longest line.
    private func tallest(_ index: Int) -> PanelRow {
        PanelRow(id: UUID(), name: "Deploy failures on the payments service in the EU region \(index)",
                 detail: [.words("since "), .figure("10:42"), .words(" — 7 matches — tier 4, repeat "), .figure("20/20"),
                          .words(", no longer repeating — its Shortcut failed")],
                 spoken: "Row \(index)", mark: .fault)
    }

    /// With long words the buttons still stand in one column inside the margin,
    /// and the words wrap beside them: nothing is pushed out of the panel.
    func testLongWordsWrapBesideTheButtonAndPushNothingOut() throws {
        let panel = controller()
        panel.setRows([tallest(0), said("Short", mark: .tier(2)), tallest(1)], onAcknowledge: { _ in })
        let content = try XCTUnwrap(panel.panel.contentView)
        let edges = try panel.buttons.map { button -> CGFloat in
            let superview = try XCTUnwrap(button.superview)
            return superview.convert(button.alignmentRect(forFrame: button.frame), to: content).maxX
        }
        XCTAssertEqual(Set(edges).count, 1, "one column: \(edges)")
        XCTAssertLessThanOrEqual(try XCTUnwrap(edges.first), AlertPanelController.width - AlertPanelController.insets.right + 0.5)
        XCTAssertEqual(panel.panel.frame.width, AlertPanelController.width)
        for block in panel.blocks {
            XCTAssertLessThanOrEqual(block.frame.maxX, AlertPanelController.width - AlertPanelController.insets.right + 0.5)
        }
        XCTAssertGreaterThan(try XCTUnwrap(panel.blocks.first).frame.height, try XCTUnwrap(panel.blocks.dropFirst().first).frame.height,
                             "the long row is taller, since its words wrapped")
    }

    /// How tall six rows are, measured and not assumed: about 500 points with
    /// one-line words, and under 700 with the tallest there are.
    func testSixRowsAreAboutFiveHundredPointsAndTheTallestSixUnderSevenHundred() {
        let panel = controller()
        panel.setRows(rows(AlertPanelController.maxRows), onAcknowledge: { _ in })
        XCTAssertLessThan(panel.panel.frame.height, 520)
        panel.setRows((0..<6).map(tallest), onAcknowledge: { _ in })
        XCTAssertEqual(panel.rows.count, 6, "with no screen given to measure against, six are shown")
        XCTAssertGreaterThan(panel.panel.frame.height, 520)
        XCTAssertLessThan(panel.panel.frame.height, 700)
    }

    /// On a screen too short for six, fewer are shown and the rest counted, so
    /// that no button sits below the screen's edge; and never fewer than one.
    func testOnAShortScreenFewerRowsAreShownSoThatAllOfThemFit() {
        func panel(visibleHeight: CGFloat) -> AlertPanelController {
            let area = AlertPanelController.ScreenArea(frame: NSRect(x: 0, y: 0, width: 1024, height: visibleHeight + 60),
                                                       visible: NSRect(x: 0, y: 40, width: 1024, height: visibleHeight))
            return AlertPanelController(title: "Waiting", acknowledgeTitle: "Acknowledge", overflowLine: { "and \($0) more" },
                                        screens: { [area] }, pointer: { NSPoint(x: 10, y: 10) }) {
                NSPanel(contentRect: $0, styleMask: $1, backing: .buffered, defer: true)
            }
        }
        let short = panel(visibleHeight: 545)
        let many = (0..<6).map(tallest)
        short.setRows(many, onAcknowledge: { _ in })
        XCTAssertLessThan(short.rows.count, 6)
        XCTAssertGreaterThanOrEqual(short.rows.count, 1)
        XCTAssertLessThanOrEqual(short.panel.frame.height, 545 - 2 * AlertPanelController.margin)
        XCTAssertEqual(short.hiddenCount, 6 - short.rows.count)
        XCTAssertEqual(short.drawnOverflow, "and \(6 - short.rows.count) more")
        XCTAssertEqual(short.rows.map(\.id), many.prefix(short.rows.count).map(\.id), "the newest are the ones kept")
        XCTAssertEqual(short.buttons.count, short.rows.count)

        let roomy = panel(visibleHeight: 1000)
        roomy.setRows(many, onAcknowledge: { _ in })
        XCTAssertEqual(roomy.rows.count, 6)
        XCTAssertNil(roomy.drawnOverflow)

        let tiny = panel(visibleHeight: 90)
        tiny.setRows(many, onAcknowledge: { _ in })
        XCTAssertEqual(tiny.rows.count, 1, "one row is shown whatever the screen")
        XCTAssertEqual(tiny.hiddenCount, 5)
    }

    private static func views(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(views(in:))
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
        // Every file, in folders too, so a file moved into one is held as well.
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let files = walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
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
