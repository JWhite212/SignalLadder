// Sources/NotificationCore/LadderStrip.swift
import Foundation

/// How far a rule's ladder reaches, for the strip of four segments on its row
/// in the rule editor's list (M7 plan, Stage 6a).
///
/// A row in the list said its alert and its preset in words. The strip shows
/// the same thing at a glance: one segment for each tier, in the tier's colour
/// when the rule has that tier and plain when it has not. Tier 1 is the rule's
/// first alert, and the others are the escalation's. It is read from the rule
/// as it stands in the draft and nothing of it is stored.
///
/// A rule that is switched off keeps its strip, drawn faint, since it shows
/// what the rule would do, and the row's tick box says it is off.
public struct LadderStrip: Equatable, Sendable {
    public struct Segment: Equatable, Sendable {
        /// 1 to 4.
        public let tier: Int
        public let isOn: Bool
        public let tone: TierTone
    }

    /// Four, tier 1 first.
    public let segments: [Segment]

    public init(for rule: Rule) {
        let on = [rule.alert != nil, rule.escalation?.tier2 != nil, rule.escalation?.tier3 != nil,
                  rule.escalation?.tier4 != nil]
        segments = on.enumerated().map { Segment(tier: $0.offset + 1, isOn: $0.element, tone: TierTone(tier: $0.offset + 1)) }
    }

    /// The tier whose settings the rule editor shows when a rule is opened:
    /// the first alert, which every rule begins with.
    public static let firstTier = 1

    /// Which tier's settings are shown after a preset is chosen (M7 plan, Stage
    /// 6b). A preset may remove the tier that was selected, and the settings of
    /// a tier that is gone are only its switch, so the selection goes back to
    /// the first alert. A tier the preset keeps, or adds, stays selected, and so
    /// does a tier outside 1 to 4, held to the first.
    public func selection(afterPreset selected: Int) -> Int {
        segments.first { $0.tier == selected }?.isOn == true ? selected : Self.firstTier
    }

    /// The tiers the rule has, lowest first.
    public var tiersOn: [Int] {
        segments.filter(\.isOn).map(\.tier)
    }

    /// What a screen reader is told in place of the strip, and its tooltip:
    /// "No tier is on", "Tier 1 is on", "Tiers 1 and 3 are on", "Tiers 1, 2 and
    /// 3 are on".
    public var description: String {
        let tiers = tiersOn.map(String.init)
        switch tiers.count {
        case 0: return "No tier is on"
        case 1: return "Tier \(tiers[0]) is on"
        default: return "Tiers \(tiers.dropLast().joined(separator: ", ")) and \(tiers[tiers.count - 1]) are on"
        }
    }
}

extension RuleOrder {
    /// Where a rule stands in the list, from 1, which is its priority: the top
    /// rule wins. nil for a rule the list does not hold. It is the row's place
    /// and nothing is stored.
    public static func position(of id: Rule.ID, in rules: [Rule]) -> Int? {
        rules.firstIndex { $0.id == id }.map { $0 + 1 }
    }
}

extension EditorText {
    /// The number at the head of a rule's row, in fixed-width figures: "1".
    public static func position(_ position: Int) -> String { "\(position)" }

    /// What a screen reader is told for that number, and its tooltip: "Priority 1".
    public static func priority(_ position: Int) -> String { "Priority \(position)" }
}
