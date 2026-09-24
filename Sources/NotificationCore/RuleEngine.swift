// Sources/NotificationCore/RuleEngine.swift
import Foundation

extension CapturedNotification {
    /// The one place a `Field` is turned into a string. Every matchable field
    /// is here so the Inspector, the engine and the M3c builder cannot disagree
    /// about what `app` or `raw` means.
    public func value(of field: Field) -> String {
        switch field {
        case .app:      return appNameGuess
        case .title:    return title
        case .subtitle: return subtitle
        case .body:     return body
        case .raw:      return rawText
        case .subrole:  return subrole
        }
    }
}

public enum RuleEvaluator {
    /// Pure and total: no clock, no I/O, no state. Every case of the condition
    /// tree is answered from the notification alone.
    ///
    /// Empty groups keep their mathematical meaning — `and([])` is true,
    /// `or([])` is false — and are rejected at load time instead
    /// (`RuleSetCodec.problems(in:)`). Redefining them here would make the
    /// evaluator surprising in order to protect against input that never
    /// reaches it.
    public static func matches(_ condition: RuleCondition, _ notification: CapturedNotification) -> Bool {
        switch condition {
        case .and(let conditions):
            return conditions.allSatisfy { matches($0, notification) }
        case .or(let conditions):
            return conditions.contains { matches($0, notification) }
        case .not(let inner):
            return !matches(inner, notification)
        case .field(let field, let op, let value):
            return compare(notification.value(of: field), op, value)
        }
    }

    /// Case- and diacritic-insensitive throughout (§5.11). A rule written as
    /// `app == "microsoft teams"` must match the banner's "Microsoft Teams" —
    /// the alternative is a rule that looks right and never fires.
    private static func compare(_ subject: String, _ op: Operator, _ value: String) -> Bool {
        switch op {
        case .equals:
            return subject.compare(value, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        case .notEquals:
            return subject.compare(value, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
        case .contains:
            return subject.localizedStandardContains(value)
        case .matches:
            return Glob.matches(subject, pattern: value)
        }
    }
}

public enum RuleEngine {
    /// Array order is priority order, and the first ENABLED match wins (§5.10).
    /// A notification triggers at most one rule, so "which rule fired?" always
    /// has exactly one answer and two rules can never sound over each other.
    public static func firstMatch(for notification: CapturedNotification, in rules: [Rule]) -> Rule? {
        rules.first { $0.isEnabled && RuleEvaluator.matches($0.condition, notification) }
    }
}
