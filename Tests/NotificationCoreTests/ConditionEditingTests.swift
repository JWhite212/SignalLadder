import XCTest
@testable import NotificationCore

/// Every edit the rule builder makes. The builder has no view model, so these
/// functions are the whole of its logic — and none may ever trap.
final class ConditionEditingTests: XCTestCase {
    private let a = RuleCondition.field(.app, .equals, "Microsoft Teams")
    private let b = RuleCondition.field(.raw, .contains, "@me")
    private let c = RuleCondition.field(.title, .contains, "All Hands")

    /// and[ a, or[ b, not(c) ] ]
    private var tree: RuleCondition { .and([a, .or([b, .not(c)])]) }

    // MARK: - Finding

    func testPathsLeadToTheirNodes() {
        XCTAssertEqual(tree.condition(at: []), tree)
        XCTAssertEqual(tree.condition(at: [0]), a)
        XCTAssertEqual(tree.condition(at: [1, 0]), b)
        XCTAssertEqual(tree.condition(at: [1, 1]), .not(c))
        XCTAssertEqual(tree.condition(at: [1, 1, 0]), c)
    }

    func testAStalePathLeadsNowhereRatherThanTrapping() {
        XCTAssertNil(tree.condition(at: [2]), "past the end of a group")
        XCTAssertNil(tree.condition(at: [0, 0]), "into a field")
        XCTAssertNil(tree.condition(at: [1, 1, 1]), "a not has one child")
        XCTAssertNil(tree.condition(at: [-1]))
    }

    func testPathsListEveryNodeParentsFirst() {
        XCTAssertEqual(tree.paths, [[], [0], [1], [1, 0], [1, 1], [1, 1, 0]])
        XCTAssertEqual(a.paths, [[]])
    }

    // MARK: - Changing a node

    func testReplacingChangesOnlyThatNode() {
        let edited = tree.replacing(at: [1, 0], with: .field(.raw, .contains, "@Jamie"))
        XCTAssertEqual(edited, .and([a, .or([.field(.raw, .contains, "@Jamie"), .not(c)])]))
    }

    func testReplacingTheRootReplacesEverything() {
        XCTAssertEqual(tree.replacing(at: [], with: a), a)
    }

    func testReplacingAtAStalePathChangesNothing() {
        XCTAssertNil(tree.replacing(at: [5], with: a))
        XCTAssertNil(tree.replacing(at: [0, 0], with: a))
    }

    // MARK: - Removing

    func testRemovingTakesANodeOutOfItsGroup() {
        XCTAssertEqual(tree.removing(at: [1, 0]), .and([a, .or([.not(c)])]))
        XCTAssertEqual(tree.removing(at: [0]), .and([.or([b, .not(c)])]))
    }

    func testRemovingTheOnlyChildOfANotRemovesTheNot() {
        XCTAssertEqual(tree.removing(at: [1, 1, 0]), .and([a, .or([b])]))
    }

    func testRemovingTheLastMemberLeavesAnEmptyGroupThatIsReported() {
        let emptied = RuleCondition.and([a]).removing(at: [0])
        XCTAssertEqual(emptied, .and([]))
        let rule = Rule(name: "r", condition: emptied!)
        XCTAssertTrue(RuleSetCodec.problems(in: rule).contains { $0.contains("empty") },
                      "the user sees what they did; nothing is tidied away silently")
    }

    func testTheRootCannotBeRemoved() {
        XCTAssertNil(tree.removing(at: []))
        XCTAssertNil(RuleCondition.not(a).removing(at: [0]), "that would remove the root")
    }

    func testRemovingAtAStalePathChangesNothing() {
        XCTAssertNil(tree.removing(at: [2]))
        XCTAssertNil(tree.removing(at: [0, 0]))
    }

    // MARK: - Inserting

    func testInsertingPlacesANodeInAGroup() {
        XCTAssertEqual(tree.inserting(c, intoGroupAt: [], at: 0), .and([c, a, .or([b, .not(c)])]))
        XCTAssertEqual(tree.inserting(c, intoGroupAt: [1], at: 2), .and([a, .or([b, .not(c), c])]))
    }

    func testInsertingOnlyGoesIntoGroupsAndWithinThem() {
        XCTAssertNil(tree.inserting(c, intoGroupAt: [], at: 3), "past the end")
        XCTAssertNil(tree.inserting(c, intoGroupAt: [], at: -1), "before the start")
        XCTAssertNil(tree.inserting(c, intoGroupAt: [1], at: -1))
        XCTAssertNil(tree.inserting(c, intoGroupAt: [0], at: 0), "a field is not a group")
        XCTAssertNil(tree.inserting(c, intoGroupAt: [1, 1], at: 0), "a not holds exactly one")
        XCTAssertNil(tree.inserting(c, intoGroupAt: [9], at: 0))
    }

    // MARK: - Restructuring

    func testWrappingPutsANodeInANewGroup() {
        XCTAssertEqual(a.wrapping(at: [], in: .and), .and([a]))
        XCTAssertEqual(tree.wrapping(at: [0], in: .or), .and([.or([a]), .or([b, .not(c)])]))
    }

    func testNegatingANotRemovesItRatherThanDoublingIt() {
        XCTAssertEqual(tree.negating(at: [0]), .and([.not(a), .or([b, .not(c)])]))
        XCTAssertEqual(tree.negating(at: [1, 1]), .and([a, .or([b, c])]), "never \"not not\"")
        XCTAssertEqual(tree.negating(at: [1, 1, 0]), .and([a, .or([b, c])]), "nor from its child")
    }

    func testUnwrappingKeepsTheOnlyMember() {
        XCTAssertEqual(RuleCondition.and([a]).unwrapping(at: []), a)
        XCTAssertEqual(tree.unwrapping(at: [1, 1]), .and([a, .or([b, c])]))
    }

    func testUnwrappingAGroupOfSeveralIsRefused() {
        XCTAssertNil(tree.unwrapping(at: []), "which members would it drop?")
        XCTAssertNil(tree.unwrapping(at: [0]), "a field has nothing to unwrap")
    }

    func testSwitchingAGroupKeepsItsMembers() {
        XCTAssertEqual(tree.switchingGroup(at: [1]), .and([a, .and([b, .not(c)])]))
        XCTAssertEqual(tree.switchingGroup(at: []), .or([a, .or([b, .not(c)])]))
        XCTAssertNil(tree.switchingGroup(at: [0]))
    }

    func testAddingToASingleConditionNarrowsIt() {
        XCTAssertEqual(a.adding(b), .and([a, b]), "a seeded rule gains an \"and\"")
        XCTAssertEqual(RuleCondition.and([a]).adding(b), .and([a, b]))
        XCTAssertEqual(RuleCondition.or([a]).adding(b), .or([a, b]), "an \"any of\" stays one")
        XCTAssertEqual(RuleCondition.not(a).adding(b), .and([.not(a), b]))
    }

    func testANewConditionIsReportedUntilItIsFilledIn() {
        XCTAssertFalse(RuleSetCodec.problems(in: Rule(name: "r", condition: .blank)).isEmpty)
    }

    // MARK: - Over many trees

    /// A small deterministic generator, so a failure reproduces.
    private struct Generator {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
        mutating func tree(depth: Int) -> RuleCondition {
            let leaf = RuleCondition.field(Field.allCases[next(Field.allCases.count)], .contains, "v\(next(9))")
            guard depth > 0 else { return leaf }
            switch next(4) {
            case 0: return .and((0..<next(4)).map { _ in tree(depth: depth - 1) })
            case 1: return .or((0..<next(4)).map { _ in tree(depth: depth - 1) })
            case 2: return .not(tree(depth: depth - 1))
            default: return leaf
            }
        }
    }

    /// Notifications whose fields hold a random few of the generator's
    /// values, so conditions over them come out true and false.
    private func samples(_ generator: inout Generator) -> [CapturedNotification] {
        (0..<24).map { _ in
            func text() -> String { (0..<generator.next(4)).map { _ in "v\(generator.next(9))" }.joined(separator: " ") }
            let (app, title, subtitle, body, subrole) = (text(), text(), text(), text(), text())
            return CapturedNotification(timestamp: Date(timeIntervalSince1970: 0), appNameGuess: app, title: title,
                                        subtitle: subtitle, body: body,
                                        rawText: [app, title, subtitle, body].joined(separator: ", "), subrole: subrole)
        }
    }

    func testNoEditEverTrapsAndEveryValidPathRoundTrips() {
        var generator = Generator(state: 42)
        for _ in 0..<300 {
            let root = generator.tree(depth: 4)
            let notifications = samples(&generator)
            let valid = root.paths
            for path in valid {
                let node = root.condition(at: path)
                XCTAssertNotNil(node)
                XCTAssertEqual(root.replacing(at: path, with: node!), root, "replacing a node with itself changes nothing")
                _ = root.removing(at: path)
                _ = root.wrapping(at: path, in: .and)

                // However it tidies up, negating means wrapping in `not`.
                let negated = root.negating(at: path)!
                let meant = root.replacing(at: path, with: .not(node!))!
                for n in notifications {
                    XCTAssertEqual(RuleEvaluator.matches(negated, n), RuleEvaluator.matches(meant, n), "\(root) at \(path)")
                }
            }
            // Paths that do not exist — the shape a stale row asks with.
            for stale in valid.map({ $0 + [7] }) + [[99], [0, 99], [-3]] where root.condition(at: stale) == nil {
                XCTAssertNil(root.replacing(at: stale, with: .blank))
                XCTAssertNil(root.removing(at: stale))
                XCTAssertNil(root.wrapping(at: stale, in: .or))
                XCTAssertNil(root.negating(at: stale))
                XCTAssertNil(root.unwrapping(at: stale))
                XCTAssertNil(root.switchingGroup(at: stale))
                XCTAssertNil(root.inserting(.blank, intoGroupAt: stale, at: 0))
            }
        }
    }
}
