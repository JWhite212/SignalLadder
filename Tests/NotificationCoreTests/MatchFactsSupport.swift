import Foundation
@testable import NotificationCore

/// For the tests of what a rule says about a notification's own text, which
/// no fact changes: the facts are the ones its own time gives, with the lock
/// not read and nothing sent before it.
extension RuleEvaluator {
    static func matches(_ condition: RuleCondition, _ notification: CapturedNotification) -> Bool {
        matches(condition, notification, MatchFacts(date: notification.timestamp))
    }
}

extension RuleEngine {
    static func firstMatch(for notification: CapturedNotification, in rules: [Rule]) -> Rule? {
        firstMatch(for: notification, facts: MatchFacts(date: notification.timestamp), in: rules)
    }
}

extension RuleSeed {
    static func insertionIndex(for notification: CapturedNotification, in rules: [Rule]) -> Int {
        insertionIndex(for: notification, facts: MatchFacts(date: notification.timestamp), in: rules)
    }
}
