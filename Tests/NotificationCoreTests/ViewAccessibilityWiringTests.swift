import XCTest
@testable import NotificationCore

/// The names a screen reader is given in the rule editor's views: the rule
/// list's tick box and its one-step moves, the condition builder's pickers and
/// menus, the alert editor's sliders and the dry run's marks. Each control
/// built without them still builds and still shows, so only these reads of the
/// app's sources hold them, as `RuleListWiringTests` does. They start nothing
/// and show no window.
final class ViewAccessibilityWiringTests: XCTestCase {
    // MARK: - The rule list

    func testTheTickBoxIsNamedForItsRule() throws {
        let view = try code("RuleEditorView.swift")
        XCTAssertEqual(count(".accessibilityLabel(EditorText.ruleRowName(rule.name))", in: view), 1)
        XCTAssertEqual(count("Text(EditorText.ruleRowName(rule.name))", in: view), 1, "the row shows the same name")
    }

    func testTheHandleIsHiddenFromAScreenReader() throws {
        let view = try code("RuleEditorView.swift")
        XCTAssertEqual(count(".accessibilityHidden(true)", in: view), 1)
    }

    func testEachRowOffersBothStepsAsAnActionAndInItsMenu() throws {
        let view = try code("RuleEditorView.swift")
        XCTAssertEqual(count("ForEach(RuleOrder.Direction.allCases", in: view), 2, "the menu and the actions")
        XCTAssertEqual(count(".accessibilityActions {", in: view), 1)
        XCTAssertEqual(count("Button(EditorText.moveWord(direction)) { model.step(rule.id, direction) }", in: view), 2)
        XCTAssertEqual(count("model.canStep(rule.id, direction)", in: view), 2,
                       "the menu dims a step that moves nothing, and the actions leave it out")
    }

    func testAStepIsTheCoresMoveIntoTheDraft() throws {
        let model = try code("RuleEditorModel.swift")
        let step = try XCTUnwrap(SourceCode.body(of: "func step(_ id: Rule.ID, _ direction: RuleOrder.Direction)",
                                                        in: model))
        XCTAssertEqual(count("RuleOrder.destination(of:", in: step), 1)
        XCTAssertEqual(count("move(from: [index], to: destination)", in: step), 1, "the same move a drop makes")
        let can = try XCTUnwrap(SourceCode.body(of: "func canStep(_ id: Rule.ID, _ direction: RuleOrder.Direction) -> Bool",
                                                       in: model))
        XCTAssertEqual(count("RuleOrder.destination(of:", in: can), 1)
    }

    // MARK: - The condition builder

    func testEveryPickerAndMenuOfTheConditionBuilderIsNamed() throws {
        let view = try code("ConditionBuilderView.swift")
        for control in ["conditionGroupMode", "conditionField", "conditionOperator", "conditionOptions", "groupOptions"] {
            XCTAssertEqual(count(".accessibilityLabel(EditorText.label(.\(control)))", in: view), 1, control)
        }
        XCTAssertEqual(count("Picker(\"\"", in: view), 3, "three pickers, each named above")
        XCTAssertEqual(count("Menu {", in: view), 2, "two menus, each named above")
    }

    // MARK: - The alert editor's sliders

    func testEachSliderIsNamedAndSpeaksItsUnit() throws {
        let view = try code("AlertEditorView.swift")
        XCTAssertEqual(count("Slider(", in: view), 2, "the gain row and the rate-and-pitch row")
        XCTAssertEqual(count(".accessibilityLabel(label)", in: view), 2)
        XCTAssertEqual(count(".accessibilityValue(EditorText.gainText(gain.wrappedValue))", in: view), 1)
        XCTAssertEqual(count(".accessibilityValue(EditorText.decimalText(value.wrappedValue))", in: view), 1)
    }

    // MARK: - The dry run

    func testADryRunRowIsOneElementWhoseMarkHasWords() throws {
        let view = try code("DryRunView.swift")
        XCTAssertEqual(count(".accessibilityElement(children: .combine)", in: view), 1)
        XCTAssertEqual(count(".accessibilityLabel(EditorText.verdictWord(verdict))", in: view), 1)
    }
}
