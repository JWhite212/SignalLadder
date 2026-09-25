// Sources/NotificationCore/DryRun.swift
import Foundation

/// What a rule in the editor would do to the notifications still held in
/// memory — the step the spec calls essential (§7.3): a rule is proven on real
/// traffic before it is trusted, not discovered to be wrong at an incident.
///
/// It answers for the rules as they will be once saved: first match wins, in
/// the draft's order, and a rule with problems takes no part — the loader
/// drops it, so it will claim nothing. The selected rule is tried even if it
/// is switched off, so it can be shaped before it is turned on.
public struct DryRun: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable {
        case matched
        /// This rule matches it, but an earlier rule in effect takes it first.
        case claimedBy(index: Int, name: String)
        case notMatched
    }

    public struct Row: Equatable, Sendable {
        public let entryID: UUID
        public let verdict: Verdict
    }

    /// Every retained notification, in the order given (newest first).
    public let rows: [Row]
    /// The selected rule is switched off: these are what it WOULD do.
    public let ruleIsOff: Bool
    /// The selected rule has problems, so once saved it will not run at all.
    public let ruleHasProblems: Bool

    public var matchedCount: Int { rows.filter { $0.verdict == .matched }.count }
    public var claimedCount: Int { rows.filter { if case .claimedBy = $0.verdict { return true }; return false }.count }

    /// The rules above that take this rule's notifications, earliest first.
    public var claimers: [(index: Int, name: String)] {
        var seen = Set<Int>()
        return rows.compactMap { row -> (Int, String)? in
            guard case .claimedBy(let index, let name) = row.verdict, seen.insert(index).inserted else { return nil }
            return (index, name)
        }.sorted { $0.0 < $1.0 }
    }

    /// Where to move the rule so nothing above claims its notifications: just
    /// above the earliest claimer. nil when nothing claims them.
    public var moveAboveIndex: Int? { claimers.first?.index }

    public static func report(forRuleAt index: Int, in rules: [Rule], over entries: [InspectorEntry],
                              sounds: RuleSetCodec.SoundCheck) -> DryRun {
        guard rules.indices.contains(index) else { return DryRun(rows: [], ruleIsOff: false, ruleHasProblems: false) }
        let rule = rules[index]
        let above = rules[..<index].enumerated().filter { _, candidate in
            candidate.isEnabled && RulesDocument.problems(in: candidate, sounds: sounds).isEmpty
        }
        let rows = entries.map { entry -> Row in
            guard RuleEvaluator.matches(rule.condition, entry.captured) else {
                return Row(entryID: entry.id, verdict: .notMatched)
            }
            if let claimer = above.first(where: { RuleEvaluator.matches($0.element.condition, entry.captured) }) {
                return Row(entryID: entry.id, verdict: .claimedBy(index: claimer.offset, name: claimer.element.name))
            }
            return Row(entryID: entry.id, verdict: .matched)
        }
        return DryRun(rows: rows, ruleIsOff: !rule.isEnabled,
                      ruleHasProblems: !RulesDocument.problems(in: rule, sounds: sounds).isEmpty)
    }
}

/// A new rule made from a real notification (§7.3 step 2).
///
/// Seeds only the app. The one real Teams banner captured so far put message
/// text in its title, so an `equals` on the title would match that one
/// notification and nothing else, leaving nothing for the dry-run to widen.
/// The rule starts switched off and silent, and is named from the app alone:
/// a name is shown everywhere and saved, and message text has no place in it.
public enum RuleSeed {
    public static func rule(from notification: CapturedNotification) -> Rule {
        let app = notification.appNameGuess.trimmingCharacters(in: .whitespaces)
        return Rule(name: app.isEmpty ? "New rule" : "New rule for \(app)",
                    condition: .field(.app, .equals, notification.appNameGuess),
                    isEnabled: false,
                    alert: nil)
    }

    /// Where the new rule goes: just above the first rule in effect that would
    /// take this notification, so it is never born shadowed; otherwise last.
    public static func insertionIndex(for notification: CapturedNotification, in rules: [Rule],
                                      sounds: RuleSetCodec.SoundCheck) -> Int {
        rules.firstIndex { rule in
            rule.isEnabled && RulesDocument.problems(in: rule, sounds: sounds).isEmpty
                && RuleEvaluator.matches(rule.condition, notification)
        } ?? rules.count
    }

    /// One condition per field, for "Add Condition from This Notification".
    /// Free text is matched with `contains` — the user trims it to the part
    /// that matters — and the app and subrole with `equals`. An empty field is
    /// offered as `equals ""` ("has no subtitle"), because `contains ""` is
    /// meaningless and is reported as a problem.
    public static func offers(from notification: CapturedNotification) -> [RuleCondition] {
        Field.allCases.map { field in
            let value = notification.value(of: field)
            if value.isEmpty { return .field(field, .equals, "") }
            switch field {
            case .app, .subrole: return .field(field, .equals, value)
            case .title, .subtitle, .body, .raw: return .field(field, .contains, value)
            }
        }
    }
}
