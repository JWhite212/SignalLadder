// Sources/NotificationCore/StatusProblem.swift

/// Whether the status icon says "problem", as one pure decision, so that the
/// app target, which has no tests, builds no boolean of its own (M5 ruling
/// 10).
///
/// A rule that did not load, an alert or a Shortcut that could not run, and a
/// rule that is in effect but names a Shortcut the Shortcuts app does not list
/// each leave the app as silent as a blind pipeline does, so each claims the
/// same icon (§7.1: a broken pipeline is the most important fact on screen).
/// A live escalation comes next, and is never folded into it: a working
/// ladder must not look like a broken pipeline. That order is the caller's.
public enum StatusProblem {
    /// - Parameters:
    ///   - healthAlarming: capture is not working, or cannot be shown to be.
    ///   - ruleStatusProblem: something the user wrote is not in effect.
    ///   - warningCount: rules in effect whose Shortcut was not found. Not
    ///     a refusal, but a page that may not reach the phone, so above zero
    ///     it is a problem.
    ///   - unresolvedAlertFailure: the last alert could not play, and no
    ///     alert has played since.
    ///   - unresolvedShortcutFailure: a Shortcut did not run, and that
    ///     Shortcut has not started since.
    public static func isProblem(healthAlarming: Bool, ruleStatusProblem: Bool, warningCount: Int,
                                 unresolvedAlertFailure: Bool, unresolvedShortcutFailure: Bool) -> Bool {
        healthAlarming || ruleStatusProblem || warningCount > 0
            || unresolvedAlertFailure || unresolvedShortcutFailure
    }
}
