// Sources/NotificationCore/BannerTreeLocator.swift
import Foundation

/// Finds notification banner elements inside an accessibility tree.
///
/// Deliberately subrole-driven and deepest-match-wins. It never uses a
/// child-index path, because Apple restructures this tree between releases
/// (spec section 5.3) — matching on subrole survives extra wrapper levels,
/// a hard-coded path does not.
///
/// A matched node is only returned if none of its descendants also matched;
/// otherwise the descendants are returned instead. This holds correctly
/// under every tree shape the allowlist implies — a lone banner, a wrapper
/// around a banner, or a stack containing banners — without needing to know
/// which shape is real in advance.
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
        search(root, depth: 0, visited: &visited, into: &found)
        return found
    }

    /// Depth-first so that deeper matches can displace their matched ancestors.
    /// A banner that contains banners (e.g. a stack) must yield its children,
    /// not itself — otherwise stacked notifications are silently swallowed.
    private func search(_ node: AccessibilityNode,
                        depth: Int,
                        visited: inout Int,
                        into found: inout [AccessibilityNode]) {
        visited += 1
        if visited > maxVisited { return }

        var childMatches: [AccessibilityNode] = []
        if depth < maxDepth {
            for child in node.children {
                search(child, depth: depth + 1, visited: &visited, into: &childMatches)
            }
        }

        if !childMatches.isEmpty {
            found.append(contentsOf: childMatches)
        } else if BannerSubrole.isBanner(node.subrole) {
            found.append(node)
        }
    }
}
