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
}
