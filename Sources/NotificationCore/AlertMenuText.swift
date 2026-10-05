// Sources/NotificationCore/AlertMenuText.swift
import Foundation

/// The menu's lines about alerts, worded here where they are tested.
///
/// Warnings come before the last match. A sound that could not play, or an
/// output that cannot be heard, is the most important thing the rules section
/// can say, and the menu is read from the top.
public enum AlertMenuText {
    public static let outputSilentWarning = "⚠︎ \(outputSilentSentence)"

    /// The warning without its mark, for a place that marks an urgent line its
    /// own way (the on-call check), so the sentence is written once.
    public static let outputSilentSentence = "Sound output is muted or at zero volume — alerts will not be heard"

    /// The menu's lines about escalations: a Shortcut that did not run first,
    /// since it is the one alert that may have been meant to reach someone
    /// away from the Mac, then how many are escalating and how many were
    /// missed while asleep. Never what arrived (ruling 17, extended to the
    /// menu, which already held to it for speech).
    ///
    /// - Parameter listed: the escalations the coordinator lists.
    public static func escalationLines(listed: [EscalationSummary],
                                       shortcutFailure: CapturePipeline.ShortcutFailure?,
                                       time: (Date) -> String) -> [String] {
        var lines: [String] = []
        if let failure = shortcutFailure {
            lines.append("⚠︎ \(failure.ruleName) at \(time(failure.at)): \(failure.reason)")
        }
        let escalating = listed.filter(\.status.isEscalating).count
        if escalating > 0 {
            lines.append("\(escalating) alert\(escalating == 1 ? "" : "s") escalating")
        }
        let missed = listed.filter(\.status.isUnseenMiss).count
        if missed > 0 {
            lines.append("\(missed) alert\(missed == 1 ? "" : "s") missed while asleep")
        }
        return lines
    }

    /// The disabled line under the On Call item: when on-call mode was switched
    /// on, so that a switch someone forgot is there to be seen, and what the
    /// self-tests are doing.
    ///
    /// "On call since Mon 09:00". The weekday comes from the calendar and the
    /// time from `time`, which the menu's other lines use too. When what was
    /// saved could not be read as a time the line says so and shows none.
    ///
    /// - Parameters:
    ///   - since: when it was switched on, nil when that is not known.
    ///   - allowsSelfTest: whether a self-test can run now
    ///     (`SelfTestPlan.Conditions.allowsSelfTest`), nil before the first
    ///     health check has said. The cadence is named only while self-tests
    ///     are running, and a pause is named as one: neither is claimed
    ///     before it is known.
    ///   - calendar: names the weekday, in the user's language.
    public static func onCallSinceLine(since: Date?,
                                       allowsSelfTest: Bool?,
                                       calendar: Calendar,
                                       time: (Date) -> String) -> String {
        let moment: String
        if let since {
            let weekday = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: since) - 1]
            moment = "\(weekday) \(time(since))"
        } else {
            moment = OnCallText.sinceUnknown
        }
        let ending: String
        switch allowsSelfTest {
        case true?: ending = OnCallText.cadenceEnding
        case false?: ending = OnCallText.pausedEnding
        case nil: ending = ""
        }
        return "\(OnCallText.sinceStem) \(moment)\(ending)"
    }

    /// The disabled line that says on-call mode is holding the Mac awake, and
    /// what that does not do. Present only while the hold is held: it is said of
    /// what the app has read, and not of what the mode is meant to do.
    public static func awakeLine(held: Bool) -> String? {
        held ? OnCallText.awakeLine : nil
    }

    /// The menu item that acknowledges every listed escalation, as the hotkey
    /// does.
    public static func acknowledgeTitle(listed: Int) -> String {
        listed == 1 ? "Acknowledge" : "Acknowledge All (\(listed))"
    }

    /// - Parameters:
    ///   - anyRulePlaysSound: whether an enabled rule has a sound. The output
    ///     warning is noise without one: silence is exactly what a user with
    ///     no sounding rules has chosen.
    ///   - outputSilent: whether the default output device reports itself
    ///     muted or at zero volume right now.
    ///   - time: how a moment is shown, e.g. "14:02".
    public static func lines(lastMatch: CapturePipeline.LastMatch?,
                             unresolvedFailure: CapturePipeline.LastMatch?,
                             anyRulePlaysSound: Bool,
                             outputSilent: Bool,
                             time: (Date) -> String) -> [String] {
        var lines: [String] = []

        // Said once. When the failure is also the last match, the last-match
        // line already carries it.
        if let failure = unresolvedFailure, failure != lastMatch {
            lines.append("⚠︎ \(failure.ruleName) at \(time(failure.at)): \(InspectorRowText.alert(failure.alert))")
        }
        if anyRulePlaysSound && outputSilent {
            lines.append(outputSilentWarning)
        }
        if let last = lastMatch {
            let warning = last.alert.needsAttention ? "⚠︎ " : ""
            lines.append("\(warning)Last match: \(last.ruleName) at \(time(last.at)) — \(whatWasDone(last.alert))")
        }
        return lines
    }

    /// What the last-match line says was done: the Inspector row's words, except
    /// for a match a snooze held, which says so in the snooze's own words ("held
    /// while snoozed"), since the row's "Snoozed — no alert" would put a second
    /// dash in a line that has one already. Never what the notification said.
    private static func whatWasDone(_ alert: AlertOutcome) -> String {
        alert == .snoozed ? SnoozeText.heldStem : InspectorRowText.alert(alert)
    }
}
