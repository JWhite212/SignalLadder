// Sources/NotificationCore/BannerTreeLocator.swift
import Foundation

/// Finds notification banner elements inside an accessibility tree.
///
/// Deliberately breadth-first and subrole-driven. It never uses a
/// child-index path, because Apple restructures this tree between releases
/// (spec section 5.3) — matching on subrole survives extra wrapper levels,
/// a hard-coded path does not.
public struct BannerTreeLocator {
    public let maxDepth: Int
    public let maxVisited: Int

    public init(maxDepth: Int = 12, maxVisited: Int = 256) {
        self.maxDepth = maxDepth
        self.maxVisited = maxVisited
    }

    public func locate(in root: AccessibilityNode) -> [AccessibilityNode] {
        var found: [AccessibilityNode] = []
        var visited = 0
        var queue: [(node: AccessibilityNode, depth: Int)] = [(root, 0)]

        while !queue.isEmpty {
            let (node, depth) = queue.removeFirst()

            visited += 1
            if visited > maxVisited { break }

            if BannerSubrole.isBanner(node.subrole) {
                found.append(node)
                // Do not descend into a banner; nested banners are not a
                // thing, and its children are the banner's own text nodes.
                continue
            }

            if depth < maxDepth {
                for child in node.children {
                    queue.append((child, depth + 1))
                }
            }
        }

        return found
    }
}
