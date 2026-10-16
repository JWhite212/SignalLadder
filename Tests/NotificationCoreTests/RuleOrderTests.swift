import XCTest
@testable import NotificationCore

/// How a drag in the rule editor's list reorders the draft. Order is priority,
/// since the first enabled rule that matches wins, so a move must change the
/// draft itself, be offered for saving, and come back from the file in its
/// new order.
final class RuleOrderTests: XCTestCase {
    private func rule(_ name: String, app: String = "Microsoft Teams") -> Rule {
        Rule(name: name, condition: .field(.app, .contains, app), alert: .silent)
    }

    private lazy var rules = ["A", "B", "C", "D"].map { rule($0) }

    private func names(_ rules: [Rule]) -> [String] { rules.map(\.name) }

    // MARK: - Where a dragged rule lands

    /// The list names the place by the row it is dropped before, counted in
    /// the order before the drag, as SwiftUI's `onMove` does.
    func testADragDownLandsAboveTheRowItIsDroppedOn() {
        XCTAssertEqual(names(RuleOrder.moving(rules, fromOffsets: [0], toOffset: 3)), ["B", "C", "A", "D"])
    }

    func testADragUpLandsAboveTheRowItIsDroppedOn() {
        XCTAssertEqual(names(RuleOrder.moving(rules, fromOffsets: [3], toOffset: 0)), ["D", "A", "B", "C"])
    }

    func testADragPastTheLastRowLandsAtTheBottom() {
        XCTAssertEqual(names(RuleOrder.moving(rules, fromOffsets: [1], toOffset: 4)), ["A", "C", "D", "B"])
    }

    func testADropBesideItselfLeavesTheOrderAlone() {
        XCTAssertEqual(names(RuleOrder.moving(rules, fromOffsets: [1], toOffset: 1)), ["A", "B", "C", "D"])
        XCTAssertEqual(names(RuleOrder.moving(rules, fromOffsets: [1], toOffset: 2)), ["A", "B", "C", "D"])
    }

    func testSeveralRulesMoveTogetherInTheirOrder() {
        XCTAssertEqual(names(RuleOrder.moving(rules, fromOffsets: [0, 2], toOffset: 4)), ["B", "D", "A", "C"])
    }

    /// A list can hand over a place the draft has since lost, if a rule was
    /// deleted while the drag was in the air. No rule is lost or doubled.
    func testAnOffsetPastTheDraftMovesNothingAndLosesNothing() {
        XCTAssertEqual(names(RuleOrder.moving(rules, fromOffsets: [9], toOffset: 0)), ["A", "B", "C", "D"])
        XCTAssertEqual(names(RuleOrder.moving(rules, fromOffsets: [0], toOffset: 9)), ["B", "C", "D", "A"])
        XCTAssertEqual(names(RuleOrder.moving(rules, fromOffsets: [3], toOffset: -1)), ["D", "A", "B", "C"])
    }

    func testAMoveKeepsEveryRuleAsItWas() {
        let moved = RuleOrder.moving(rules, fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(Set(moved.map(\.id)), Set(rules.map(\.id)))
        XCTAssertEqual(moved.first, rules[2], "only the place changes, not the rule")
    }

    // MARK: - What a move means

    func testAMoveChangesWhichRuleWins() {
        let note = CapturedNotification(timestamp: .distantPast, appNameGuess: "Microsoft Teams", title: "t",
                                        subtitle: "", body: "b", rawText: "r", subrole: "AXNotificationCenterBanner")
        XCTAssertEqual(RuleEngine.firstMatch(for: note, in: rules)?.name, "A")
        let moved = RuleOrder.moving(rules, fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(RuleEngine.firstMatch(for: note, in: moved)?.name, "C", "order is priority")
    }

    func testAMoveIsAnEditThatCanBeSaved() {
        let version = RuleSetCodec.version(for: rules)
        XCTAssertFalse(RulesDocument.canSave(draft: rules, loaded: rules, fileVersion: version))
        let moved = RuleOrder.moving(rules, fromOffsets: [0], toOffset: 2)
        XCTAssertTrue(RulesDocument.canSave(draft: moved, loaded: rules, fileVersion: version),
                      "a reorder alone marks the draft unsaved and offers Save")
    }

    func testAMovedOrderComesBackFromTheFile() throws {
        let moved = RuleOrder.moving(rules, fromOffsets: [3], toOffset: 1)
        let read = try RuleSetCodec.decode(RuleSetCodec.encode(moved))
        XCTAssertEqual(names(read.rules), ["A", "D", "B", "C"])
        XCTAssertEqual(read.problems, [])
    }
}
