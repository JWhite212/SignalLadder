// Sources/NotificationCore/RuleOrder.swift
import Foundation

/// How a drag in the rule editor's list reorders the draft. Order is
/// priority, since the first enabled rule that matches wins, so the editor
/// puts this order into the draft itself, where Save writes it.
public enum RuleOrder {
    /// The rules at `offsets`, in their order, taken out and put back before
    /// the rule that was at `destination`, or at the bottom when `destination`
    /// is past the last. Both are counted in the order before the move, as
    /// SwiftUI's `onMove` hands them over.
    ///
    /// An offset the draft no longer holds moves nothing, and a destination
    /// outside it is held to the top or the bottom, so no rule is ever lost
    /// or doubled.
    public static func moving(_ rules: [Rule], fromOffsets offsets: IndexSet, toOffset destination: Int) -> [Rule] {
        let taken = offsets.filter { rules.indices.contains($0) }
        guard !taken.isEmpty else { return rules }
        let target = min(max(destination, 0), rules.count)
        var kept = rules
        for index in taken.reversed() { kept.remove(at: index) }
        let above = taken.filter { $0 < target }.count
        kept.insert(contentsOf: taken.map { rules[$0] }, at: target - above)
        return kept
    }

    /// Which way a rule is stepped by the keyboard or a screen reader, which
    /// cannot drag.
    public enum Direction: CaseIterable, Sendable { case up, down }

    /// The `destination` that `moving` takes to step the rule at `index` one
    /// place, counted in the order before the move: the row above, or two rows
    /// on, since a place is named by the row a rule lands before. Nil for the
    /// top rule going up, the bottom rule going down, and a rule the list does
    /// not hold, so a menu offers only the steps that move something.
    public static func destination(of index: Int, _ direction: Direction, count: Int) -> Int? {
        guard (0..<count).contains(index) else { return nil }
        switch direction {
        case .up: return index > 0 ? index - 1 : nil
        case .down: return index < count - 1 ? index + 2 : nil
        }
    }
}
