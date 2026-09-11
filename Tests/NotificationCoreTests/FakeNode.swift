// Tests/NotificationCoreTests/FakeNode.swift
import Foundation
@testable import NotificationCore

/// In-memory AccessibilityNode for building arbitrary test trees.
final class FakeNode: AccessibilityNode {
    let subrole: String?
    let attributedDescription: String?
    private let kids: [FakeNode]

    var children: [AccessibilityNode] { kids }

    init(subrole: String? = nil,
         description: String? = nil,
         children: [FakeNode] = []) {
        self.subrole = subrole
        self.attributedDescription = description
        self.kids = children
    }

    /// Builds a linear chain `depth` levels deep with `leaf` at the bottom.
    static func chain(depth: Int, leaf: FakeNode) -> FakeNode {
        var node = leaf
        for _ in 0..<depth {
            node = FakeNode(subrole: "AXGroup", children: [node])
        }
        return node
    }
}
