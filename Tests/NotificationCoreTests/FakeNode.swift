// Tests/NotificationCoreTests/FakeNode.swift
import Foundation
@testable import NotificationCore

/// In-memory AccessibilityNode for building arbitrary test trees.
final class FakeNode: AccessibilityNode {
    let role: String?
    let subrole: String?
    let attributedDescription: String?
    let value: String?
    private let kids: [FakeNode]
    private let id: AnyHashable?

    var children: [AccessibilityNode] { kids }

    /// Unique to this node unless an `id` was given, so that two nodes built
    /// with the same `id` stand for two reads of one live element.
    var identity: AnyHashable { id ?? AnyHashable(ObjectIdentifier(self)) }

    var isGone = false
    var isFocused: Bool

    init(role: String? = nil,
         subrole: String? = nil,
         description: String? = nil,
         value: String? = nil,
         id: AnyHashable? = nil,
         focused: Bool = false,
         children: [FakeNode] = []) {
        self.role = role
        self.subrole = subrole
        self.isFocused = focused
        self.attributedDescription = description
        self.value = value
        self.id = id
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
