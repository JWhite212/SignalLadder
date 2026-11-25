import XCTest
@testable import NotificationCore

/// How the rule editor's list carries out a drag: the list's rows are the draft
/// itself, a drop is handed to the model, and the model puts the core's order
/// into the draft.
///
/// Each row once allowed a move only while the pointer was over its handle, as
/// `onHover` reported it. On macOS 27.2 that came to no move at all: a drag
/// from the handle was refused, and the same list without the gate reordered.
/// The app builds either way without a warning, so these tests read the app's
/// sources, as `SetupWiringTests` and `ViewLiteralsTests` do. They start
/// nothing and show no window.
final class RuleListWiringTests: XCTestCase {
    func testTheListShowsTheDraftAndHandsADropToTheModel() throws {
        let view = try code("RuleEditorView.swift")
        XCTAssertEqual(count("ForEach($model.rules)", in: view), 1, "the rows are the draft, not a copy of it")
        XCTAssertEqual(count(".onMove(perform: model.move)", in: view), 1)
    }

    func testNoRowIsKeptFromMoving() throws {
        let view = try code("RuleEditorView.swift")
        XCTAssertEqual(count("moveDisabled", in: view), 0,
                       "a row gated on hover could not be dragged at all on macOS 27.2")
        XCTAssertEqual(count("overHandle", in: view), 0)
    }

    func testADropPutsTheCoresOrderIntoTheDraft() throws {
        let model = try code("RuleEditorModel.swift")
        let body = try XCTUnwrap(SourceCode.body(of: "func move(from source: IndexSet, to destination: Int)",
                                                        in: model))
        XCTAssertEqual(body.trimmingCharacters(in: .whitespacesAndNewlines),
                       "rules = RuleOrder.moving(rules, fromOffsets: source, toOffset: destination)")
    }

    // MARK: - The row's number and its strip (M7 plan, Stage 6a)

    /// The number is the row's place in the draft as it stands, asked of the
    /// core at each drawing, so it follows a drag and nothing is stored.
    func testARowsNumberIsItsPlaceInTheDraftAndIsStoredNowhere() throws {
        let view = try code("RuleEditorView.swift")
        XCTAssertEqual(count("position: RuleOrder.position(of: rule.id, in: model.rules),", in: view), 1)
        XCTAssertEqual(count("Text(EditorText.position(position))", in: view), 1)
        XCTAssertEqual(count(".font(.mono(.caption, weight: .semibold))", in: view), 1, "in fixed-width figures")
        XCTAssertEqual(count(".accessibilityLabel(EditorText.priority(position))", in: view), 1,
                       "a screen reader is told it is the rule's priority")
        XCTAssertEqual(count(".help(EditorText.priority(position))", in: view), 1)
        XCTAssertFalse(try code("RuleEditorModel.swift").contains("position"), "the model keeps no number")
    }

    /// The strip is the core's reading of the rule in the draft, drawn in the
    /// palette's colours, and told to a screen reader in the core's words.
    func testTheStripIsTheCoresAndIsToldInWords() throws {
        let view = try code("RuleEditorView.swift")
        XCTAssertEqual(count("LadderStripView(strip: LadderStrip(for: rule), isEnabled: rule.isEnabled)", in: view), 1)
        XCTAssertEqual(count("Capsule().fill(NightWatchPalette.block(segment.tone))", in: view), 1, "a tier it has, in the tier's colour")
        XCTAssertEqual(count("Capsule().strokeBorder(.tertiary, lineWidth: 1)", in: view), 1,
                       "a tier it has not is hollow, so the two differ by more than colour")
        XCTAssertEqual(count(".accessibilityLabel(strip.description)", in: view), 1)
        XCTAssertEqual(count(".accessibilityElement(children: .ignore)", in: view), 1)
        XCTAssertEqual(count(".opacity(isEnabled ? 1 : 0.4)", in: view), 1, "a rule that is off keeps its strip, faint")
        XCTAssertEqual(count(".help(EditorText.alertSummary(rule.alert, escalation: rule.escalation))", in: view), 1,
                       "the summary is one line, and whole in its tooltip")
        XCTAssertEqual(count(".clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))", in: view), 1,
                       "the panel's corners hold a row scrolled to the edge")
    }

    /// The selected rule is navy, with the label colours of the dark
    /// appearance over it, and a dark window gives it the shade above, which
    /// can be told from the window.
    func testTheSelectedRowIsNavyWithLightWordsOverIt() throws {
        let view = try code("RuleEditorView.swift")
        XCTAssertEqual(count(".listRowBackground(RuleRowGround(isSelected: isSelected))", in: view), 1)
        XCTAssertEqual(count(".fill(isSelected ? (scheme == .dark ? NightWatchPalette.raised : NightWatchPalette.ground) : .clear)",
                             in: view), 1)
        XCTAssertEqual(count(".environment(\\.colorScheme, isSelected ? .dark : scheme)", in: view), 1)
        XCTAssertEqual(count("let isSelected = model.selection == rule.id", in: view), 1)
    }

    /// What the list did before, it still does.
    func testDragTheDeleteKeyTheMenuAndTopRuleWinsAreUnchanged() throws {
        let view = try code("RuleEditorView.swift")
        XCTAssertEqual(count(".onDeleteCommand { if let id = model.selection { delete(id) } }", in: view), 1)
        XCTAssertEqual(count(".contextMenu {", in: view), 1)
        XCTAssertEqual(count("Button(EditorText.duplicate) { model.duplicate(rule.id) }", in: view), 1)
        XCTAssertEqual(count("Button(EditorText.delete, role: .destructive) { delete(rule.id) }", in: view), 1)
        XCTAssertEqual(count("Text(EditorText.topRuleWins)", in: view), 1)
        XCTAssertEqual(count("List(selection: $model.selection) {", in: view), 1)
    }
}
