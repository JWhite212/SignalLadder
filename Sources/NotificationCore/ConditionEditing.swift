// Sources/NotificationCore/ConditionEditing.swift
import Foundation

/// Where a node sits in a condition tree: the child index at each level, from
/// the root. The root itself is `[]`; a `not`'s one child is index 0.
public typealias ConditionPath = [Int]

/// Every edit the rule builder makes, as pure functions on the condition
/// itself — the builder binds straight to `RuleCondition` (§5.14), and there
/// is no second tree for it to drift from.
///
/// Every function is total. A path that no longer leads anywhere returns nil
/// rather than trapping, because a view can ask about a row once more after
/// that row's node has been deleted. A stale path is a no-op, never a crash.
extension RuleCondition {
    public enum GroupKind: Sendable { case and, or }

    /// What a new condition starts as. Its empty value is reported as a
    /// problem until it is filled, so a half-made condition cannot be saved
    /// looking finished.
    public static let blank = RuleCondition.field(.title, .contains, "")

    /// The node at `path`, or nil when the path no longer leads anywhere.
    public func condition(at path: ConditionPath) -> RuleCondition? {
        guard let head = path.first else { return self }
        guard let child = child(at: head) else { return nil }
        return child.condition(at: Array(path.dropFirst()))
    }

    /// A copy with the node at `path` replaced, or nil when the path is stale.
    public func replacing(at path: ConditionPath, with replacement: RuleCondition) -> RuleCondition? {
        guard let head = path.first else { return replacement }
        guard let child = child(at: head),
              let updated = child.replacing(at: Array(path.dropFirst()), with: replacement) else { return nil }
        return replacingChild(at: head, with: updated)
    }

    /// A copy without the node at `path`. Removing a `not`'s only child
    /// removes the `not`. The root cannot be removed.
    ///
    /// Removing a group's last child leaves an empty group. That is allowed
    /// and reported as a problem ("an empty group would match everything"),
    /// not silently tidied away: the user sees what they did.
    public func removing(at path: ConditionPath) -> RuleCondition? {
        guard !path.isEmpty, condition(at: path) != nil else { return nil }
        let parentPath = Array(path.dropLast())
        guard let parent = condition(at: parentPath) else { return nil }
        switch parent {
        case .and(var children):
            children.remove(at: path.last!)
            return replacing(at: parentPath, with: .and(children))
        case .or(var children):
            children.remove(at: path.last!)
            return replacing(at: parentPath, with: .or(children))
        case .not:
            return parentPath.isEmpty ? nil : removing(at: parentPath)
        case .field:
            return nil
        }
    }

    /// A copy with `child` inserted into the group at `groupPath`, at
    /// `index` (0...count). Nil unless `groupPath` is an and/or group.
    public func inserting(_ child: RuleCondition, intoGroupAt groupPath: ConditionPath, at index: Int) -> RuleCondition? {
        switch condition(at: groupPath) {
        case .and(var children)?:
            guard (0...children.count).contains(index) else { return nil }
            children.insert(child, at: index)
            return replacing(at: groupPath, with: .and(children))
        case .or(var children)?:
            guard (0...children.count).contains(index) else { return nil }
            children.insert(child, at: index)
            return replacing(at: groupPath, with: .or(children))
        default:
            return nil
        }
    }

    /// Puts the node at `path` inside a new group, as its only member — the
    /// first step of "and also…" or "or else…".
    public func wrapping(at path: ConditionPath, in kind: GroupKind) -> RuleCondition? {
        guard let node = condition(at: path) else { return nil }
        return replacing(at: path, with: kind == .and ? .and([node]) : .or([node]))
    }

    /// Negates the node at `path`. Negating a `not`, or the one child of a
    /// `not`, cancels that `not` instead of adding another, so the builder
    /// never shows "not not". Each form means exactly what wrapping the node
    /// in `not` would.
    public func negating(at path: ConditionPath) -> RuleCondition? {
        guard let node = condition(at: path) else { return nil }
        if case .not(let inner) = node { return replacing(at: path, with: inner) }
        if !path.isEmpty {
            let parentPath = Array(path.dropLast())
            if case .not? = condition(at: parentPath) { return replacing(at: parentPath, with: node) }
        }
        return replacing(at: path, with: .not(node))
    }

    /// Replaces a group of exactly one member, or a `not`, with what it
    /// contains. Nil for anything else: unwrapping a group of several would
    /// have to choose which members to lose.
    public func unwrapping(at path: ConditionPath) -> RuleCondition? {
        switch condition(at: path) {
        case .and(let children)? where children.count == 1,
             .or(let children)? where children.count == 1:
            return replacing(at: path, with: children[0])
        case .not(let inner)?:
            return replacing(at: path, with: inner)
        default:
            return nil
        }
    }

    /// Turns an "all of" group into "any of", or back, keeping its members.
    public func switchingGroup(at path: ConditionPath) -> RuleCondition? {
        switch condition(at: path) {
        case .and(let children)?: return replacing(at: path, with: .or(children))
        case .or(let children)?: return replacing(at: path, with: .and(children))
        default: return nil
        }
    }

    /// A copy with `child` added at the top level: appended when the whole
    /// condition is already an and/or group, otherwise alongside it in a new
    /// "all of" group — so adding to a rule seeded with one condition
    /// narrows it, as the user expects.
    public func adding(_ child: RuleCondition) -> RuleCondition {
        switch self {
        case .and(let children): return .and(children + [child])
        case .or(let children): return .or(children + [child])
        case .not, .field: return .and([self, child])
        }
    }

    /// Every node's path, parents before children, in reading order.
    public var paths: [ConditionPath] {
        [[]] + childNodes.enumerated().flatMap { index, child in child.paths.map { [index] + $0 } }
    }

    // MARK: - One level

    private var childNodes: [RuleCondition] {
        switch self {
        case .and(let children), .or(let children): return children
        case .not(let inner): return [inner]
        case .field: return []
        }
    }

    private func child(at index: Int) -> RuleCondition? {
        let children = childNodes
        return children.indices.contains(index) ? children[index] : nil
    }

    private func replacingChild(at index: Int, with child: RuleCondition) -> RuleCondition {
        switch self {
        case .and(var children):
            children[index] = child
            return .and(children)
        case .or(var children):
            children[index] = child
            return .or(children)
        case .not:
            return .not(child)
        case .field:
            return self
        }
    }
}
