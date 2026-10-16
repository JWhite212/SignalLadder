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
}
